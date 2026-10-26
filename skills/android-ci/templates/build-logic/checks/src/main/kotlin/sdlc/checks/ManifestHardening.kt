package sdlc.checks

import org.w3c.dom.Element
import org.w3c.dom.NodeList
import org.xml.sax.InputSource
import org.xml.sax.SAXException
import org.xml.sax.helpers.DefaultHandler
import java.io.StringReader
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory

object ManifestHardening {
    private const val ANDROID = "http://schemas.android.com/apk/res/android"
    private val permissionTags = listOf("uses-permission", "uses-permission-sdk-23")
    private val launcherTags = listOf("activity", "activity-alias")
    private val guardedExports =
        setOf("androidx.profileinstaller.ProfileInstallReceiver" to "android.permission.DUMP")
    private val componentTags = listOf("activity", "activity-alias", "service", "receiver", "provider")

    fun validate(mergedManifestXml: String): List<String> {
        val root =
            try {
                parse(mergedManifestXml)
            } catch (e: SAXException) {
                return listOf("manifest is not valid XML: ${e.message}")
            }
        return permissionErrors(root) + applicationErrors(root) + componentErrors(root)
    }

    private fun parse(xml: String): Element {
        val factory = DocumentBuilderFactory.newInstance()
        factory.isNamespaceAware = true
        factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        val builder = factory.newDocumentBuilder()
        builder.setErrorHandler(DefaultHandler())
        return builder.parse(InputSource(StringReader(xml))).documentElement
    }

    private fun permissionErrors(root: Element) =
        permissionTags
            .flatMap { root.getElementsByTagName(it).elements() }
            .filter { it.android("name") == "android.permission.INTERNET" }
            .map { "INTERNET permission is forbidden" }

    private fun applicationErrors(root: Element): List<String> {
        val applications = root.getElementsByTagName("application").elements()
        if (applications.isEmpty()) return listOf("application element is missing")
        return applications.flatMap { application ->
            listOfNotNull(
                "android:debuggable must not be true".takeIf { application.android("debuggable") == "true" },
                "android:allowBackup must be true".takeIf { application.android("allowBackup") != "true" },
                "android:dataExtractionRules must be set".takeIf { application.android("dataExtractionRules").isEmpty() },
                "android:fullBackupContent must be set".takeIf { application.android("fullBackupContent").isEmpty() },
            )
        }
    }

    private fun componentErrors(root: Element) =
        componentTags
            .flatMap { root.getElementsByTagName(it).elements() }
            .filter { it.android("exported") == "true" && !isGuardedExport(it) && !isLauncher(it) }
            .map { "${it.tagName} ${it.android("name")} is exported without being the launcher" }

    private fun isGuardedExport(component: Element) = (component.android("name") to component.android("permission")) in guardedExports

    private fun isLauncher(component: Element) =
        component.tagName in launcherTags &&
            component.getElementsByTagName("intent-filter").elements().any { filter ->
                "android.intent.action.MAIN" in filter.names("action") &&
                    "android.intent.category.LAUNCHER" in filter.names("category")
            }

    private fun Element.names(tag: String) = getElementsByTagName(tag).elements().map { it.android("name") }

    private fun Element.android(name: String) = getAttributeNS(ANDROID, name)

    private fun NodeList.elements() = (0 until length).map { item(it) as Element }
}
