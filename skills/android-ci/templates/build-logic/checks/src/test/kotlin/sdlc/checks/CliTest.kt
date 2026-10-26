package sdlc.checks

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path
import kotlin.io.path.writeText
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CliTest {
    private val files =
        mapOf(
            "clean.kt" to "val a = 1",
            "dirty.kt" to "val a = 1\n// x",
            "dirty.yml" to "# y",
            "good-commit" to "feat: x\n\nWhy: a\nWhat: b",
            "bad-commit" to "Feat: x",
            "commits" to "feat: x\n\nWhy: a\nWhat: b\u0000fix: y\u0000",
            "title-good" to "feat(domain): add x\n",
            "title-bad" to "Feat: x\n",
            "body-good" to "## Why\n\nA\n\nCloses #1\n\n## Evidence\n\n```\nok\n```\n",
            "body-bad" to "## Why\n\nA\n",
            "labels-none" to "",
            "labels-deps" to "bug\ndependencies\n",
            "paths-ok" to "domain/src/main/A.kt\ndomain/src/test/ATest.kt\n\ndocs/x.md\n",
            "paths-bad" to "domain/src/main/A.kt\n",
            "wf-clean" to "permissions: {}\non: push\n",
            "wf-bad" to "permissions: {}\non: pull_request_target\n",
            "manifest-good" to manifestXml(""),
            "manifest-bad" to manifestXml("""<uses-permission android:name="android.permission.INTERNET" />"""),
        )

    private fun manifestXml(permission: String) =
        """
        <manifest xmlns:android="http://schemas.android.com/apk/res/android">
            $permission
            <application android:allowBackup="true" android:dataExtractionRules="@xml/d" android:fullBackupContent="@xml/b" />
        </manifest>
        """.trimIndent()

    private fun run(vararg args: String): Pair<Int, List<String>> {
        val printed = mutableListOf<String>()
        val code = Cli.run(args.toList(), { files.getValue(it) }, { printed += it })
        return code to printed
    }

    @Test
    fun noFindingsExitsZeroAndPrintsNothing() {
        val (code, printed) = run("no-comments", "clean.kt")
        assertEquals(0, code)
        assertEquals(emptyList<String>(), printed)
    }

    @Test
    fun findingsExitOneAndArePrintedAsPathLineMessage() {
        val (code, printed) = run("no-comments", "clean.kt", "dirty.kt", "dirty.yml")
        assertEquals(1, code)
        assertEquals(
            listOf(
                "dirty.kt:2: comment not allowed (why/what belong in the commit message)",
                "dirty.yml:1: comment not allowed (why/what belong in the commit message)",
            ),
            printed,
        )
    }

    @Test
    fun noArgumentsPrintsUsageAndExitsTwo() {
        val (code, printed) = run()
        assertEquals(2, code)
        assertEquals(listOf(Cli.USAGE), printed)
    }

    @Test
    fun unknownSubcommandPrintsUsageAndExitsTwo() {
        val (code, printed) = run("nope", "clean.kt")
        assertEquals(2, code)
        assertEquals(listOf(Cli.USAGE), printed)
    }

    @Test
    fun noCommentsWithoutPathsPrintsUsageAndExitsTwo() {
        val (code, printed) = run("no-comments")
        assertEquals(2, code)
        assertEquals(listOf(Cli.USAGE), printed)
    }

    @Test
    fun commitMessageValidMessageExitsZero() {
        assertEquals(0 to emptyList<String>(), run("commit-message", "good-commit"))
    }

    @Test
    fun commitMessageInvalidMessageExitsOneWithTheError() {
        val (code, printed) = run("commit-message", "bad-commit")
        assertEquals(1, code)
        assertTrue(printed.single().contains("type must be one of"))
    }

    @Test
    fun commitMessagesChecksEveryNulSeparatedMessageAndNamesTheHeader() {
        val (code, printed) = run("commit-messages", "commits")
        assertEquals(1, code)
        assertEquals(1, printed.size)
        assertTrue(printed.single().startsWith("fix: y: "))
        assertTrue(printed.single().contains("body required"))
    }

    @Test
    fun commitMessagesRejectsFixupBecauseItRunsInCi() {
        val printed = mutableListOf<String>()
        val code = Cli.run(listOf("commit-messages", "f"), { "fixup! feat: x" }, { printed += it })
        assertEquals(1, code)
        assertTrue(printed.single().contains("autosquash"))
    }

    @Test
    fun prTitleValidExitsZero() {
        assertEquals(0 to emptyList<String>(), run("pr-title", "title-good"))
    }

    @Test
    fun prTitleInvalidExitsOneWithTheError() {
        val (code, printed) = run("pr-title", "title-bad")
        assertEquals(1, code)
        assertTrue(printed.single().contains("type must be one of"))
    }

    @Test
    fun prBodyValidExitsZero() {
        assertEquals(0 to emptyList<String>(), run("pr-body", "body-good", "labels-none"))
    }

    @Test
    fun prBodyInvalidExitsOneAndLabelsWaiveTheIssueLink() {
        val (code, printed) = run("pr-body", "body-bad", "labels-deps")
        assertEquals(1, code)
        assertEquals(1, printed.size)
        assertTrue(printed.single().contains("Evidence"))
    }

    @Test
    fun testsChangedValidExitsZero() {
        assertEquals(0 to emptyList<String>(), run("tests-changed", "paths-ok", "domain", "data"))
    }

    @Test
    fun testsChangedMissingTestsExitsOne() {
        val (code, printed) = run("tests-changed", "paths-bad", "domain", "data")
        assertEquals(1, code)
        assertTrue(printed.single().contains("domain"))
    }

    @Test
    fun workflowsCleanExitsZero() {
        assertEquals(0 to emptyList<String>(), run("workflows", "wf-clean"))
    }

    @Test
    fun workflowsFindingExitsOneAndIsPrintedAsPathLineMessage() {
        val (code, printed) = run("workflows", "wf-clean", "wf-bad")
        assertEquals(1, code)
        assertEquals(1, printed.size)
        assertTrue(printed.single().startsWith("wf-bad:2: "))
        assertTrue("forbidden trigger" in printed.single())
    }

    @Test
    fun manifestCleanExitsZero() {
        assertEquals(0 to emptyList<String>(), run("manifest", "manifest-good"))
    }

    @Test
    fun manifestViolationExitsOne() {
        val (code, printed) = run("manifest", "manifest-bad")
        assertEquals(1, code)
        assertTrue("INTERNET" in printed.single())
    }

    @Test
    fun wrongArgumentCountPrintsUsageAndExitsTwo() {
        listOf(
            arrayOf("commit-message"),
            arrayOf("commit-message", "a", "b"),
            arrayOf("commit-messages"),
            arrayOf("pr-title"),
            arrayOf("pr-body", "body-good"),
            arrayOf("pr-body", "body-good", "labels-none", "x"),
            arrayOf("tests-changed", "paths-ok"),
            arrayOf("tests-changed"),
            arrayOf("workflows"),
            arrayOf("manifest"),
            arrayOf("manifest", "manifest-good", "manifest-bad"),
        ).forEach {
            assertEquals(2 to listOf(Cli.USAGE), run(*it), it.toList().toString())
        }
    }

    @Test
    fun mainReadsRealFilesAndTerminatesWithTheExitCode(
        @TempDir dir: Path,
    ) {
        val clean = dir.resolve("a.kt").also { it.writeText("val a = 1") }
        val dirty = dir.resolve("b.kt").also { it.writeText("val b = 1 // x") }
        val exits = mutableListOf<Int>()
        terminate = { exits += it }
        try {
            main(arrayOf("no-comments", clean.toString()))
            main(arrayOf("no-comments", dirty.toString()))
            main(arrayOf())
        } finally {
            terminate = System::exit
        }
        assertEquals(listOf(0, 1, 2), exits)
    }
}
