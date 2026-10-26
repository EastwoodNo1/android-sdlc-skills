package sdlc.checks

data class Finding(
    val path: String,
    val line: Int,
    val message: String,
) {
    override fun toString() = "$path:$line: $message"
}
