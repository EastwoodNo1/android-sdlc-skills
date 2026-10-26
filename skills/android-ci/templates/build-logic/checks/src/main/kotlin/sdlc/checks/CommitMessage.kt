package sdlc.checks

enum class CommitContext { LOCAL, CI }

object CommitMessage {
    private val types =
        listOf("build", "chore", "ci", "docs", "feat", "fix", "perf", "refactor", "revert", "style", "test")
    private val bodyRequired = setOf("feat", "fix", "perf", "refactor")
    private val header = Regex("^(${types.joinToString("|")})(\\([a-z0-9-]+\\))?!?: \\S.*$")
    private val trailer = Regex("^[A-Za-z]+(-[A-Za-z]+)+: .+$")
    private const val MAX_HEADER = 72
    private const val MAX_TITLE = 64
    private const val FIXUP = "fixup! "
    private const val DEFAULT_REVERT = "Revert \""

    fun validate(
        message: String,
        context: CommitContext,
    ): List<String> {
        val lines = message.trimEnd().lines()
        val first = lines.first()
        if (first.startsWith(FIXUP)) {
            return if (context == CommitContext.LOCAL) {
                emptyList()
            } else {
                listOf("fixup! commit must be squashed (git rebase -i --autosquash) before pushing")
            }
        }
        val errors = headerErrors(first)
        if (errors.isNotEmpty()) return errors
        val type = first.substringBefore(':').substringBefore('(').removeSuffix("!")
        val body =
            lines
                .drop(1)
                .dropWhile { it.isNotBlank() }
                .dropLastWhile { it.isBlank() || trailer.matches(it) }
                .joinToString("\n")
                .trim()
        return if (type in bodyRequired && body.isEmpty()) {
            listOf("body required for $type commits: state Why: and What:")
        } else {
            emptyList()
        }
    }

    fun validateTitle(title: String) = headerErrors(title.trim(), MAX_TITLE)

    private fun headerErrors(
        head: String,
        limit: Int = MAX_HEADER,
    ): List<String> =
        when {
            head.startsWith(DEFAULT_REVERT) -> {
                listOf("use \"revert:\" (for example revert: add x), not the default Revert \"...\" message")
            }

            head.startsWith(FIXUP) -> {
                listOf("fixup! is not allowed here, squash it first")
            }

            else -> {
                buildList {
                    if (head.length > limit) add("header is ${head.length} characters, the limit is $limit")
                    if (!header.matches(head)) {
                        add("type must be one of ${types.joinToString(", ")}, in the form type(scope)!: description")
                    }
                }
            }
        }
}
