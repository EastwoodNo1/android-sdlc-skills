package sdlc.checks

object WorkflowSafety {
    private val trigger = Regex("""\b(pull_request_target|workflow_run)\b""")
    private val runKey = Regex("""^(\s*)(-\s+)?run:\s*(.*?)\s*$""")
    private val blockIndicator = Regex("""[|>][-+0-9]*""")
    private val eventData = Regex("""\$\{\{\s*github\.event\.""")
    private val usesValue = Regex("""^\s*(?:-\s+)?uses:\s*(\S+)""")
    private val pinned = Regex("""@[0-9a-f]{40}$""")
    private val topLevelPermissions = Regex("""^permissions:\s*\{\}\s*$""")

    fun scan(
        path: String,
        content: String,
    ): List<Finding> {
        val lines = content.lines()
        val findings = mutableListOf<Finding>()
        var blockIndent: Int? = null
        lines.forEachIndexed { index, line ->
            val number = index + 1
            val active = blockIndent
            val inBlock = active != null && (line.isBlank() || indentOf(line) > active)
            if (!inBlock) blockIndent = null
            val run = runKey.find(line)
            if (run != null && blockIndicator.matches(run.groupValues[3])) {
                blockIndent = run.groupValues[1].length + run.groupValues[2].length
            }
            val forbidden = trigger.find(line)
            if (forbidden != null) {
                findings += Finding(path, number, "forbidden trigger: ${forbidden.value}")
            }
            if ((inBlock || run != null) && eventData.containsMatchIn(line)) {
                findings += Finding(path, number, "pass event data through env, never interpolate it in run")
            }
            val action = usesValue.find(line)?.let { it.groupValues[1].trim('"', '\'') }
            if (action != null && !action.startsWith("./") && !pinned.containsMatchIn(action)) {
                findings += Finding(path, number, "pin to a full commit SHA: $action")
            }
        }
        if (lines.none(topLevelPermissions::matches)) {
            findings += Finding(path, 1, "workflow must declare top-level permissions: {}")
        }
        return findings
    }

    private fun indentOf(line: String) = line.length - line.trimStart().length
}
