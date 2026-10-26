package sdlc.checks

object TestsChanged {
    fun validate(
        changedPaths: List<String>,
        gatedModules: Set<String>,
    ): List<String> =
        gatedModules.mapNotNull { module ->
            val production = changedPaths.any { it.startsWith("$module/src/main/") }
            val tests = changedPaths.any { it.startsWith("$module/src/test/") }
            if (production && !tests) "module $module changes src/main without changing src/test" else null
        }
}
