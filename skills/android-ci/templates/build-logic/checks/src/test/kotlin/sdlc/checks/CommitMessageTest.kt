package sdlc.checks

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CommitMessageTest {
    private val body = "\n\nWhy: a reason\nWhat: a change"

    private fun assertError(
        expected: String,
        errors: List<String>,
    ) {
        assertTrue(errors.isNotEmpty(), "expected an error containing '$expected'")
        assertTrue(errors.any { expected in it }, "no error contains '$expected': $errors")
    }

    private fun local(message: String) = CommitMessage.validate(message, CommitContext.LOCAL)

    private fun ci(message: String) = CommitMessage.validate(message, CommitContext.CI)

    @Test
    fun validMessageWithBodyHasNoErrors() {
        assertEquals(emptyList(), local("feat(domain): add x$body"))
    }

    @Test
    fun uppercaseTypeIsRejectedWithTheAllowedTypes() {
        assertError(
            "type must be one of build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test",
            local("Feat: x"),
        )
    }

    @Test
    fun missingDescriptionIsRejected() {
        assertError("type must be one of", local("feat:"))
    }

    @Test
    fun emptyMessageIsRejected() {
        assertError("type must be one of", local(""))
    }

    @Test
    fun fixWithoutBodyIsRejected() {
        assertError("body required", local("fix: x"))
    }

    @Test
    fun everyBodyRequiredTypeIsRejectedWithoutBody() {
        listOf("feat", "fix", "refactor", "perf").forEach {
            assertError("body required", local("$it: x"))
        }
    }

    @Test
    fun trailersOnlyBodyDoesNotCount() {
        assertError("body required", local("feat: x\n\nCo-Authored-By: A <a@b>"))
    }

    @Test
    fun bodyFollowedByTrailerIsAccepted() {
        assertEquals(emptyList(), local("feat: x$body\n\nCo-Authored-By: A <a@b>\n"))
    }

    @Test
    fun whyAndWhatLinesAreBodyNotTrailers() {
        assertEquals(emptyList(), local("fix: x\n\nWhy: a reason"))
    }

    @Test
    fun missingBlankLineAfterHeaderMeansNoBody() {
        assertError("body required", local("feat: x\nWhy: a reason"))
    }

    @Test
    fun choreNeedsNoBody() {
        assertEquals(emptyList(), local("chore: bump"))
    }

    @Test
    fun headerOverSeventyTwoCharactersIsRejected() {
        val header = "feat: " + "x".repeat(67)
        assertEquals(73, header.length)
        assertError("72", local(header + body))
    }

    @Test
    fun headerOfExactlySeventyTwoCharactersIsAccepted() {
        val header = "feat: " + "x".repeat(66)
        assertEquals(72, header.length)
        assertEquals(emptyList(), local(header + body))
    }

    @Test
    fun defaultRevertMessageIsRejected() {
        assertError("use \"revert:\"", local("Revert \"feat: x\"$body"))
    }

    @Test
    fun fixupIsAllowedLocally() {
        assertEquals(emptyList(), local("fixup! feat: x"))
    }

    @Test
    fun fixupIsRejectedInCi() {
        assertError("autosquash", ci("fixup! feat: x"))
    }

    @Test
    fun breakingChangeMarkerIsAccepted() {
        assertEquals(emptyList(), local("feat!: x$body"))
    }

    @Test
    fun scopedBreakingChangeMarkerIsAccepted() {
        assertEquals(emptyList(), local("refactor(domain)!: x$body"))
    }

    @Test
    fun validTitleHasNoErrors() {
        assertEquals(emptyList(), CommitMessage.validateTitle("feat(domain): add x"))
    }

    @Test
    fun titleWithoutBodyIsAccepted() {
        assertEquals(emptyList(), CommitMessage.validateTitle("fix: x"))
    }

    @Test
    fun invalidTitleIsRejected() {
        assertError("type must be one of", CommitMessage.validateTitle("Feat: x"))
    }

    @Test
    fun longTitleIsRejected() {
        assertError("64", CommitMessage.validateTitle("feat: " + "x".repeat(59)))
    }

    @Test
    fun titleOfExactlySixtyFourCharactersIsAccepted() {
        val title = "feat: " + "x".repeat(58)
        assertEquals(64, title.length)
        assertEquals(emptyList(), CommitMessage.validateTitle(title))
    }

    @Test
    fun revertAndFixupTitlesAreRejected() {
        assertError("use \"revert:\"", CommitMessage.validateTitle("Revert \"feat: x\""))
        assertError("fixup!", CommitMessage.validateTitle("fixup! feat: x"))
    }
}
