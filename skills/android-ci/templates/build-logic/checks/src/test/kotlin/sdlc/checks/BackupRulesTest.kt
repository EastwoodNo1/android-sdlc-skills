package sdlc.checks

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BackupRulesTest {
    private val allowed = setOf("datastore/settings.txt", "datastore/high_scores.txt")

    private fun includes(
        domain: String = "file",
        vararg paths: String,
    ) = paths.joinToString("\n") { """<include domain="$domain" path="$it" />""" }

    private val both = includes("file", "datastore/settings.txt", "datastore/high_scores.txt")

    private fun fullBackup(body: String = both) = "<full-backup-content>$body</full-backup-content>"

    private fun extraction(
        cloud: String = both,
        transfer: String = both,
    ) = "<data-extraction-rules><cloud-backup>$cloud</cloud-backup><device-transfer>$transfer</device-transfer></data-extraction-rules>"

    @Test
    fun acceptsExactlyTheTwoFiles() {
        assertEquals(emptyList(), BackupRules.validate(fullBackup(), allowed))
        assertEquals(emptyList(), BackupRules.validate(extraction(), allowed))
    }

    @Test
    fun rejectsDirectoryInclude() {
        val findings = BackupRules.validate(fullBackup(includes("file", "datastore/")), allowed)
        assertTrue(findings.any { "datastore/" in it && "not allowed" in it })
        assertTrue(findings.any { "datastore/settings.txt" in it && "missing" in it })
    }

    @Test
    fun rejectsOtherDomain() {
        val findings = BackupRules.validate(fullBackup(includes("root", "datastore/settings.txt", "datastore/high_scores.txt")), allowed)
        assertEquals(2, findings.count { "domain" in it && "root" in it })
    }

    @Test
    fun rejectsMissingFileInDeviceTransfer() {
        val findings = BackupRules.validate(extraction(transfer = includes("file", "datastore/settings.txt")), allowed)
        assertEquals(1, findings.size)
        assertTrue("device-transfer" in findings.single() && "datastore/high_scores.txt" in findings.single())
    }

    @Test
    fun rejectsInvalidXml() {
        val findings = BackupRules.validate("<full-backup-content>", allowed)
        assertTrue(findings.single().startsWith("backup rules are not valid XML"))
    }

    @Test
    fun rejectsDoctype() {
        val findings = BackupRules.validate("<!DOCTYPE a []><full-backup-content/>", allowed)
        assertTrue(findings.single().startsWith("backup rules are not valid XML"))
    }

    @Test
    fun rejectsDocumentWithoutAnySection() {
        assertEquals(listOf("no backup section found"), BackupRules.validate("<other/>", allowed))
    }
}
