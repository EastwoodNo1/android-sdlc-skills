package sdlc.checks

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class WorkflowSafetyTest {
    private val sha = "a".repeat(40)

    private fun scan(body: String) = WorkflowSafety.scan("wf.yml", "permissions: {}\n$body")

    private fun assertOne(
        message: String,
        line: Int,
        body: String,
    ) {
        val findings = scan(body)
        assertEquals(1, findings.size, findings.toString())
        assertEquals("wf.yml", findings.single().path)
        assertEquals(line, findings.single().line)
        assertTrue(message in findings.single().message, findings.single().message)
    }

    @Test
    fun pullRequestTargetTriggerIsForbidden() = assertOne("forbidden trigger", 2, "on: pull_request_target\n")

    @Test
    fun workflowRunTriggerIsForbidden() = assertOne("forbidden trigger", 3, "on:\n  workflow_run:\n")

    @Test
    fun safeTriggersAreAccepted() {
        assertEquals(emptyList(), scan("on:\n  pull_request:\n  push:\n"))
    }

    @Test
    fun interpolatingEventDataInInlineRunIsFlagged() =
        assertOne("pass event data through env", 2, "run: echo \"\${{ github.event.pull_request.body }}\"\n")

    @Test
    fun interpolatingEventDataInListItemRunIsFlagged() =
        assertOne("pass event data through env", 2, "- run: echo \${{ github.event.issue.title }}\n")

    @Test
    fun interpolatingEventDataInsideARunBlockLineIsFlagged() {
        val body = "    steps:\n      - run: |\n          echo hi\n\n          echo \${{ github.event.issue.title }}\n"
        assertOne("pass event data through env", 6, body)
    }

    @Test
    fun foldedRunBlockWithModifiersIsTracked() {
        assertOne("pass event data through env", 3, "run: >-\n  echo \${{ github.event.issue.title }}\n")
    }

    @Test
    fun linesAfterTheRunBlockEndsAreNotInterpolationChecked() {
        val body = "run: |\n  echo hi\nenv:\n  BODY: \${{ github.event.pull_request.body }}\n"
        assertEquals(emptyList(), scan(body))
    }

    @Test
    fun eventDataOutsideRunIsNotFlagged() {
        assertEquals(emptyList(), scan("env:\n  BODY: \${{ github.event.pull_request.body }}\n"))
    }

    @Test
    fun nonBlockRunValueDoesNotStartABlock() {
        val body = "run: echo hi\n  name: \${{ github.event.issue.title }}\n"
        assertEquals(emptyList(), scan(body))
    }

    @Test
    fun otherExpressionsInRunAreNotFlagged() {
        assertEquals(emptyList(), scan("run: echo \${{ github.sha }}\n"))
    }

    @Test
    fun unpinnedActionIsFlagged() = assertOne("pin to a full commit SHA", 2, "uses: actions/checkout@v7\n")

    @Test
    fun unpinnedActionInListItemIsFlagged() = assertOne("pin to a full commit SHA", 2, "- uses: actions/checkout@v7\n")

    @Test
    fun actionWithoutVersionIsFlagged() = assertOne("pin to a full commit SHA", 2, "uses: actions/checkout\n")

    @Test
    fun shortShaIsFlagged() = assertOne("pin to a full commit SHA", 2, "uses: actions/checkout@${"a".repeat(39)}\n")

    @Test
    fun pinnedActionWithTrailingVersionCommentIsAccepted() {
        assertEquals(emptyList(), scan("- uses: actions/checkout@$sha # v7.0.1\n"))
    }

    @Test
    fun pinnedActionWithTrailingWhitespaceIsAccepted() {
        assertEquals(emptyList(), scan("uses: actions/checkout@$sha   \n"))
    }

    @Test
    fun quotedPinnedActionIsAccepted() {
        assertEquals(emptyList(), scan("uses: \"actions/checkout@$sha\"\n"))
        assertEquals(emptyList(), scan("uses: 'actions/checkout@$sha'\n"))
    }

    @Test
    fun quotedLocalActionIsExempt() {
        assertEquals(emptyList(), scan("uses: './x'\n"))
    }

    @Test
    fun quotedUnpinnedActionIsFlagged() = assertOne("pin to a full commit SHA", 2, "uses: \"actions/checkout@v7\"\n")

    @Test
    fun localActionsAreExempt() {
        assertEquals(emptyList(), scan("uses: ./.github/actions/setup\n"))
    }

    @Test
    fun missingPermissionsIsOneFindingAtLineOne() {
        val findings = WorkflowSafety.scan("wf.yml", "on: push\n")
        assertEquals(1, findings.size)
        assertEquals(1, findings.single().line)
        assertTrue("top-level permissions: {}" in findings.single().message)
    }

    @Test
    fun indentedPermissionsIsNotTopLevel() {
        val findings = WorkflowSafety.scan("wf.yml", "jobs:\n  a:\n    permissions: {}\n")
        assertEquals(1, findings.size)
        assertTrue("top-level permissions: {}" in findings.single().message)
    }

    @Test
    fun readPermissionsAreNotTheEmptyMapping() {
        val findings = WorkflowSafety.scan("wf.yml", "permissions:\n  contents: read\n")
        assertEquals(1, findings.size)
    }

    @Test
    fun emptyPermissionsWithTrailingWhitespaceIsAccepted() {
        assertEquals(emptyList(), WorkflowSafety.scan("wf.yml", "permissions: {}  \n"))
    }

    @Test
    fun everyViolationLineIsReportedSeparately() {
        val body = "on: pull_request_target\njobs:\n  a:\n    steps:\n      - uses: x/y@v1\n"
        assertEquals(listOf(2, 6), scan(body).map { it.line })
    }
}
