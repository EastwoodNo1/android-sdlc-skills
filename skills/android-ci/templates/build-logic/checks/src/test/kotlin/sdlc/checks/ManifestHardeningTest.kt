package sdlc.checks

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path
import kotlin.io.path.writeText
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ManifestHardeningTest {
    private val launcher =
        """
        <activity android:name=".Main" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        """.trimIndent()

    private val applicationAttributes =
        """
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        """.trimIndent()

    private fun manifest(
        applicationAttrs: String = applicationAttributes,
        components: String = launcher,
        permissions: String = "",
    ) = """
        <manifest xmlns:android="http://schemas.android.com/apk/res/android">
            $permissions
            <application $applicationAttrs>
                $components
            </application>
        </manifest>
        """.trimIndent()

    private fun assertOneError(
        fragment: String,
        xml: String,
    ) {
        val errors = ManifestHardening.validate(xml)
        assertEquals(1, errors.size, errors.toString())
        assertTrue(fragment in errors.single(), errors.single())
    }

    @Test
    fun validMinimalManifestHasNoErrors() {
        assertEquals(emptyList(), ManifestHardening.validate(manifest()))
    }

    @Test
    fun internetPermissionIsRejected() {
        val permission = """<uses-permission android:name="android.permission.INTERNET" />"""
        assertOneError("INTERNET", manifest(permissions = permission))
    }

    @Test
    fun internetPermissionFromSdk23IsRejected() {
        val permission = """<uses-permission-sdk-23 android:name="android.permission.INTERNET" />"""
        assertOneError("INTERNET", manifest(permissions = permission))
    }

    @Test
    fun otherPermissionsAreAccepted() {
        val permission = """<uses-permission android:name="android.permission.VIBRATE" />"""
        assertEquals(emptyList(), ManifestHardening.validate(manifest(permissions = permission)))
    }

    @Test
    fun debuggableApplicationIsRejected() {
        assertOneError("debuggable", manifest("$applicationAttributes android:debuggable=\"true\""))
    }

    @Test
    fun explicitlyNonDebuggableApplicationIsAccepted() {
        assertEquals(
            emptyList(),
            ManifestHardening.validate(manifest("$applicationAttributes android:debuggable=\"false\"")),
        )
    }

    @Test
    fun exportedActivityWithoutLauncherFilterIsRejected() {
        val extra = """<activity android:name=".Other" android:exported="true" />"""
        assertOneError("exported", manifest(components = launcher + extra))
    }

    @Test
    fun exportedServiceWithoutLauncherFilterIsRejected() {
        val extra = """<service android:name=".S" android:exported="true" />"""
        assertOneError("exported", manifest(components = launcher + extra))
    }

    @Test
    fun nonExportedAndUnspecifiedComponentsAreAccepted() {
        val extra =
            """
            <activity android:name=".A" android:exported="false" />
            <activity android:name=".B" />
            """.trimIndent()
        assertEquals(emptyList(), ManifestHardening.validate(manifest(components = launcher + extra)))
    }

    private val profileReceiver = "androidx.profileinstaller.ProfileInstallReceiver"

    private fun receiver(
        name: String,
        permission: String,
    ) = """<receiver android:name="$name" android:exported="true" android:permission="$permission" />"""

    @Test
    fun allowlistedReceiverWithItsRequiredPermissionIsAccepted() {
        val extra = receiver(profileReceiver, "android.permission.DUMP")
        assertEquals(emptyList(), ManifestHardening.validate(manifest(components = launcher + extra)))
    }

    @Test
    fun allowlistedReceiverWithAnotherPermissionIsRejected() {
        val extra = receiver(profileReceiver, "android.permission.VIBRATE")
        assertOneError("exported", manifest(components = launcher + extra))
    }

    @Test
    fun otherReceiverWithTheDumpPermissionIsRejected() {
        val extra = receiver("com.example.Other", "android.permission.DUMP")
        assertOneError("exported", manifest(components = launcher + extra))
    }

    @Test
    fun exportedProviderWithReadAndWritePermissionsIsRejected() {
        val extra =
            """
            <provider android:name=".P" android:exported="true"
                android:readPermission="android.permission.DUMP"
                android:writePermission="android.permission.DUMP" />
            """.trimIndent()
        assertOneError("exported", manifest(components = launcher + extra))
    }

    @Test
    fun exportedServiceWithLauncherFilterIsRejected() {
        val extra =
            """
            <service android:name=".S" android:exported="true">
                <intent-filter>
                    <action android:name="android.intent.action.MAIN" />
                    <category android:name="android.intent.category.LAUNCHER" />
                </intent-filter>
            </service>
            """.trimIndent()
        assertOneError("exported", manifest(components = launcher + extra))
    }

    @Test
    fun exportedActivityAliasWithLauncherFilterIsAccepted() {
        val extra =
            """
            <activity-alias android:name=".Alias" android:targetActivity=".Main" android:exported="true">
                <intent-filter>
                    <action android:name="android.intent.action.MAIN" />
                    <category android:name="android.intent.category.LAUNCHER" />
                </intent-filter>
            </activity-alias>
            """.trimIndent()
        assertEquals(emptyList(), ManifestHardening.validate(manifest(components = launcher + extra)))
    }

    @Test
    fun mainActionWithoutLauncherCategoryIsNotALauncher() {
        val extra =
            """
            <activity android:name=".A" android:exported="true">
                <intent-filter><action android:name="android.intent.action.MAIN" /></intent-filter>
            </activity>
            """.trimIndent()
        assertOneError("exported", manifest(components = launcher + extra))
    }

    @Test
    fun launcherCategoryWithoutMainActionIsNotALauncher() {
        val extra =
            """
            <activity android:name=".A" android:exported="true">
                <intent-filter>
                    <category android:name="android.intent.category.LAUNCHER" />
                </intent-filter>
            </activity>
            """.trimIndent()
        assertOneError("exported", manifest(components = launcher + extra))
    }

    @Test
    fun mainAndLauncherSplitAcrossFiltersIsNotALauncher() {
        val extra =
            """
            <activity android:name=".A" android:exported="true">
                <intent-filter><action android:name="android.intent.action.MAIN" /></intent-filter>
                <intent-filter>
                    <category android:name="android.intent.category.LAUNCHER" />
                </intent-filter>
            </activity>
            """.trimIndent()
        assertOneError("exported", manifest(components = launcher + extra))
    }

    @Test
    fun disabledBackupIsRejected() {
        assertOneError("allowBackup", manifest(applicationAttributes.replace("allowBackup=\"true\"", "allowBackup=\"false\"")))
    }

    @Test
    fun missingDataExtractionRulesIsRejected() {
        val attrs = applicationAttributes.lines().filterNot { "dataExtractionRules" in it }.joinToString("\n")
        assertOneError("dataExtractionRules", manifest(attrs))
    }

    @Test
    fun missingFullBackupContentIsRejected() {
        val attrs = applicationAttributes.lines().filterNot { "fullBackupContent" in it }.joinToString("\n")
        assertOneError("fullBackupContent", manifest(attrs))
    }

    @Test
    fun missingApplicationIsRejected() {
        assertOneError(
            "application",
            """<manifest xmlns:android="http://schemas.android.com/apk/res/android" />""",
        )
    }

    @Test
    fun attributesInAnotherNamespaceAreIgnored() {
        val attrs = applicationAttributes.replace("android:allowBackup", "other:allowBackup")
        val xml = manifest(attrs).replace("<manifest ", "<manifest xmlns:other=\"urn:other\" ")
        assertOneError("allowBackup", xml)
    }

    @Test
    fun doctypeWithExternalEntityIsAnErrorAndReadsNoFile(
        @TempDir dir: Path,
    ) {
        val secret = "TOP-SECRET-CONTENT"
        val file = dir.resolve("secret.txt").also { it.writeText(secret) }
        val xml =
            """
            <?xml version="1.0"?>
            <!DOCTYPE manifest [<!ENTITY leak SYSTEM "${file.toUri()}">]>
            <manifest xmlns:android="http://schemas.android.com/apk/res/android">&leak;</manifest>
            """.trimIndent()
        val errors = ManifestHardening.validate(xml)
        assertEquals(1, errors.size, errors.toString())
        assertTrue("DOCTYPE" in errors.single(), errors.single())
        assertFalse(secret in errors.single())
    }

    @Test
    fun malformedXmlIsAnError() {
        val errors = ManifestHardening.validate("<manifest>")
        assertEquals(1, errors.size)
        assertTrue("not valid XML" in errors.single())
    }
}
