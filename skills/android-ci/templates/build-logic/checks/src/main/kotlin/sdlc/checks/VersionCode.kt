package sdlc.checks

object VersionCode {
    private val format = Regex("""(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)""")
    private const val MAX_MAJOR = 2099L
    private const val MAX_MINOR_OR_PATCH = 999L

    fun of(semver: String): Int {
        val version = semver.trim()
        val parts =
            requireNotNull(format.matchEntire(version)) {
                "Version '$version' has the wrong format: expected MAJOR.MINOR.PATCH of digits without leading zeros"
            }.groupValues
        val major = field(version, "major", parts[1], MAX_MAJOR)
        val minor = field(version, "minor", parts[2], MAX_MINOR_OR_PATCH)
        val patch = field(version, "patch", parts[3], MAX_MINOR_OR_PATCH)
        val code = major * 1_000_000 + minor * 1_000 + patch
        return if (code == 0L) 1 else code.toInt()
    }

    private fun field(
        version: String,
        name: String,
        digits: String,
        max: Long,
    ): Long {
        val value = digits.toLongOrNull() ?: Long.MAX_VALUE
        require(value <= max) { "Version '$version' has a $name above the limit of $max" }
        return value
    }
}
