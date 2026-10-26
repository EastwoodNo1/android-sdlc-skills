package sdlc.checks

import org.junit.jupiter.api.Test
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PullRequestBodyTest {
    private val fence = "```"

    private fun body(
        link: String = "Closes #12",
        evidence: String = "$fence\n$ ./gradlew check\nBUILD SUCCESSFUL\n$fence",
    ) = "## Why\n\nA reason\n\n## What\n\nA change\n\n$link\n\n## Evidence\n\n$evidence\n"

    private fun assertError(
        expected: String,
        errors: List<String>,
    ) {
        assertTrue(errors.any { expected in it }, "no error contains '$expected': $errors")
    }

    @Test
    fun validBodyHasNoErrors() {
        assertEquals(emptyList(), PullRequestBody.validate(body(), emptySet()))
    }

    @Test
    fun missingIssueLinkIsRejected() {
        assertError("link an issue", PullRequestBody.validate(body(link = "No link"), emptySet()))
    }

    @Test
    fun fixesAndResolvesCountCaseInsensitively() {
        listOf("Fixes #3", "resolves #4", "CLOSES #5").forEach {
            assertEquals(emptyList(), PullRequestBody.validate(body(link = it), emptySet()))
        }
    }

    @Test
    fun linkWithoutNumberDoesNotCount() {
        assertError("link an issue", PullRequestBody.validate(body(link = "Closes #"), emptySet()))
    }

    @Test
    fun dependenciesLabelWaivesTheIssueLink() {
        assertEquals(
            emptyList(),
            PullRequestBody.validate(body(link = "Bump x"), setOf("dependencies")),
        )
    }

    @Test
    fun otherLabelsDoNotWaiveTheIssueLink() {
        assertError("link an issue", PullRequestBody.validate(body(link = "Bump x"), setOf("bug")))
    }

    @Test
    fun placeholderOnlyEvidenceIsRejected() {
        assertError(
            "Evidence",
            PullRequestBody.validate(body(evidence = PullRequestBody.EVIDENCE_PLACEHOLDER), emptySet()),
        )
    }

    @Test
    fun placeholderBesideARealFencedBlockIsAccepted() {
        val evidence = "${PullRequestBody.EVIDENCE_PLACEHOLDER}\n$fence\nok\n$fence"
        assertEquals(emptyList(), PullRequestBody.validate(body(evidence = evidence), emptySet()))
    }

    @Test
    fun emptyEvidenceIsRejected() {
        assertError("Evidence", PullRequestBody.validate(body(evidence = ""), emptySet()))
    }

    @Test
    fun emptyFencedBlockIsRejected() {
        assertError(
            "Evidence",
            PullRequestBody.validate(body(evidence = "$fence\n\n$fence"), emptySet()),
        )
    }

    @Test
    fun missingEvidenceHeadingIsRejected() {
        assertError(
            "Evidence",
            PullRequestBody.validate("## Why\n\nx\n\nCloses #1\n$fence\nout\n$fence", emptySet()),
        )
    }

    @Test
    fun fencedBlockInAnotherSectionDoesNotCountAsEvidence() {
        val text = "## Why\n\n$fence\nout\n$fence\n\nCloses #1\n\n## Evidence\n\nnothing\n\n## Notes\n\n$fence\nout\n$fence"
        assertError("Evidence", PullRequestBody.validate(text, emptySet()))
    }

    @Test
    fun headingInsideBacktickFenceDoesNotEndEvidence() {
        val evidence = "$fence\n$ git status -sb\n## main...origin/main\n$fence"
        assertEquals(emptyList(), PullRequestBody.validate(body(evidence = evidence), emptySet()))
    }

    @Test
    fun headingInsideTildeFenceDoesNotEndEvidence() {
        val evidence = "~~~\n## main...origin/main\n~~~\n$fence\nok\n$fence"
        assertEquals(emptyList(), PullRequestBody.validate(body(evidence = evidence), emptySet()))
    }

    @Test
    fun otherFenceMarkerInsideAFenceDoesNotCloseIt() {
        val evidence = "$fence\n~~~\n## main...origin/main\nout\n$fence"
        assertEquals(emptyList(), PullRequestBody.validate(body(evidence = evidence), emptySet()))
    }

    @Test
    fun longerClosingFenceClosesTheBlock() {
        val text = "## Evidence\n\n$fence\nx\n$fence`\n\n## Notes\n\ntext"
        assertEquals(emptyList(), PullRequestBody.validate("Closes #1\n\n$text", emptySet()))
    }

    @Test
    fun headingAfterAClosedFenceStillEndsEvidence() {
        val text = "Closes #1\n\n## Evidence\n\n$fence\n\n$fence\n\n## Notes\n\n$fence\nout\n$fence"
        assertError("Evidence", PullRequestBody.validate(text, emptySet()))
    }

    @Test
    fun windowsLineEndingsAreAccepted() {
        assertEquals(emptyList(), PullRequestBody.validate(body().replace("\n", "\r\n"), emptySet()))
    }

    @Test
    fun templatePlaceholderMatchesTheConstant() {
        val template = File(System.getProperty("repoRoot"), ".github/pull_request_template.md").readText()
        assertTrue(PullRequestBody.EVIDENCE_PLACEHOLDER in template.lines())
    }
}
