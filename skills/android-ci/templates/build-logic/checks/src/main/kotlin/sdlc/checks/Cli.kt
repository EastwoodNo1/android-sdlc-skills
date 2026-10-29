package sdlc.checks

import java.io.File

object Cli {
    const val USAGE =
        "usage: checks no-comments <path...> | commit-message <file> | commit-messages <file> | " +
            "pr-body <bodyFile> <labelsFile> | pr-title <titleFile> | tests-changed <pathsFile> <module...> | " +
            "workflows <path...> | manifest <path> | backup-rules <allowedCsv> <path...>"

    fun run(
        args: List<String>,
        readFile: (String) -> String,
        out: (String) -> Unit,
    ): Int {
        val rest = args.drop(1)
        val errors =
            when (args.firstOrNull()) {
                "no-comments" -> {
                    rest.takeIf { it.isNotEmpty() }?.flatMap { path ->
                        NoComments.scan(path, readFile(path)).map(Finding::toString)
                    }
                }

                "commit-message" -> {
                    rest.singleOrNull()?.let { CommitMessage.validate(readFile(it), CommitContext.LOCAL) }
                }

                "commit-messages" -> {
                    rest.singleOrNull()?.let { file ->
                        readFile(file).split('\u0000').filter { it.isNotBlank() }.flatMap { message ->
                            val header = message.trim().lineSequence().first()
                            CommitMessage.validate(message, CommitContext.CI).map { "$header: $it" }
                        }
                    }
                }

                "pr-title" -> {
                    rest.singleOrNull()?.let { CommitMessage.validateTitle(readFile(it)) }
                }

                "pr-body" -> {
                    rest.takeIf { it.size == 2 }?.let {
                        PullRequestBody.validate(readFile(it[0]), nonBlankLines(readFile(it[1])).toSet())
                    }
                }

                "tests-changed" -> {
                    rest.takeIf { it.size >= 2 }?.let {
                        TestsChanged.validate(nonBlankLines(readFile(it[0])), it.drop(1).toSet())
                    }
                }

                "workflows" -> {
                    rest.takeIf { it.isNotEmpty() }?.flatMap { path ->
                        WorkflowSafety.scan(path, readFile(path)).map(Finding::toString)
                    }
                }

                "manifest" -> {
                    rest.singleOrNull()?.let { ManifestHardening.validate(readFile(it)) }
                }

                "backup-rules" -> {
                    rest.takeIf { it.size >= 2 }?.let { arguments ->
                        val allowed = arguments.first().split(',').toSet()
                        arguments.drop(1).flatMap { path ->
                            BackupRules.validate(readFile(path), allowed).map { "$path: $it" }
                        }
                    }
                }

                else -> {
                    null
                }
            }
        if (errors == null) {
            out(USAGE)
            return 2
        }
        errors.forEach(out)
        return if (errors.isEmpty()) 0 else 1
    }

    private fun nonBlankLines(text: String) = text.lines().map(String::trim).filter(String::isNotEmpty)
}

internal var terminate: (Int) -> Unit = System::exit

fun main(args: Array<String>) {
    terminate(Cli.run(args.toList(), { File(it).readText() }, ::println))
}
