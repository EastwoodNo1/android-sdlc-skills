package sdlc.checks

object NoComments {
    const val MESSAGE = "comment not allowed (why/what belong in the commit message)"

    fun scan(
        path: String,
        content: String,
    ): List<Finding> {
        val scan = Scan(path, content)
        when (path.substringAfterLast('.', "")) {
            "kt", "kts" -> scanKotlin(scan, nested = false)
            "xml" -> scanXml(scan)
            "toml", "yml", "yaml", "sh", "pro" -> scanHash(scan)
            "properties" -> scanProperties(scan)
        }
        return scan.findings
    }
}

private class Scan(
    private val path: String,
    val text: String,
) {
    var pos = 0
    var line = 1
    val findings = mutableListOf<Finding>()

    val atEnd get() = pos >= text.length

    fun startsWith(prefix: String) = text.startsWith(prefix, pos)

    fun advance() {
        if (text.getOrNull(pos) == '\n') line++
        pos++
    }

    fun advance(count: Int) = repeat(count) { advance() }

    fun flag() {
        findings += Finding(path, line, NoComments.MESSAGE)
    }

    fun skipLine() {
        while (!atEnd && text[pos] != '\n') advance()
    }

    fun skipPast(terminator: String) {
        while (!atEnd && !startsWith(terminator)) advance()
        advance(terminator.length)
    }
}

private fun scanKotlin(
    scan: Scan,
    nested: Boolean,
) {
    var depth = 0
    while (!scan.atEnd) {
        val c = scan.text[scan.pos]
        when {
            scan.startsWith("//") -> {
                scan.flag()
                scan.skipLine()
            }

            scan.startsWith("/*") -> {
                skipKotlinBlockComment(scan)
            }

            scan.startsWith("\"\"\"") -> {
                skipKotlinString(scan, raw = true)
            }

            c == '"' -> {
                skipKotlinString(scan, raw = false)
            }

            c == '\'' -> {
                skipKotlinChar(scan)
            }

            c == '`' -> {
                skipKotlinBacktick(scan)
            }

            c == '{' -> {
                depth++
                scan.advance()
            }

            c == '}' && nested && depth == 0 -> {
                scan.advance()
                return
            }

            c == '}' -> {
                depth--
                scan.advance()
            }

            else -> {
                scan.advance()
            }
        }
    }
}

private fun skipKotlinBlockComment(scan: Scan) {
    scan.flag()
    scan.advance(2)
    var depth = 1
    while (!scan.atEnd && depth > 0) {
        when {
            scan.startsWith("/*") -> {
                depth++
                scan.advance(2)
            }

            scan.startsWith("*/") -> {
                depth--
                scan.advance(2)
            }

            else -> {
                scan.advance()
            }
        }
    }
}

private fun skipKotlinString(
    scan: Scan,
    raw: Boolean,
) {
    val terminator = if (raw) "\"\"\"" else "\""
    scan.advance(terminator.length)
    while (!scan.atEnd && !scan.startsWith(terminator)) {
        when {
            !raw && scan.startsWith("\\") -> {
                scan.advance(2)
            }

            scan.startsWith("\${") -> {
                scan.advance(2)
                scanKotlin(scan, nested = true)
            }

            else -> {
                scan.advance()
            }
        }
    }
    scan.advance(terminator.length)
}

private fun skipKotlinBacktick(scan: Scan) {
    scan.advance()
    while (!scan.atEnd && scan.text[scan.pos] != '`' && scan.text[scan.pos] != '\n') scan.advance()
    if (!scan.atEnd && scan.text[scan.pos] == '`') scan.advance()
}

private fun skipKotlinChar(scan: Scan) {
    scan.advance()
    while (!scan.atEnd && !scan.startsWith("'")) {
        scan.advance(if (scan.startsWith("\\")) 2 else 1)
    }
    scan.advance()
}

private fun scanXml(scan: Scan) {
    var inTag = false
    var quote: Char? = null
    while (!scan.atEnd) {
        val c = scan.text[scan.pos]
        when {
            quote != null -> {
                if (c == quote) quote = null
                scan.advance()
            }

            scan.startsWith("<!--") -> {
                scan.flag()
                scan.skipPast("-->")
            }

            scan.startsWith("<![CDATA[") -> {
                scan.skipPast("]]>")
            }

            inTag && (c == '"' || c == '\'') -> {
                quote = c
                scan.advance()
            }

            else -> {
                if (c == '<') inTag = true
                if (c == '>') inTag = false
                scan.advance()
            }
        }
    }
}

private fun scanHash(scan: Scan) {
    var quote: Char? = null
    while (!scan.atEnd) {
        val c = scan.text[scan.pos]
        when {
            c == '\n' -> {
                quote = null
                scan.advance()
            }

            quote != null -> {
                if (quote == '"' && c == '\\') scan.advance()
                if (c == quote) quote = null
                scan.advance()
            }

            c == '"' || c == '\'' -> {
                quote = c
                scan.advance()
            }

            c == '#' && scan.pos == 0 && scan.startsWith("#!") -> {
                scan.skipLine()
            }

            c == '#' && (scan.pos == 0 || scan.text[scan.pos - 1].isWhitespace()) -> {
                scan.flag()
                scan.skipLine()
            }

            else -> {
                scan.advance()
            }
        }
    }
}

private fun scanProperties(scan: Scan) {
    scan.text.lineSequence().forEachIndexed { index, text ->
        if (text.trimStart().firstOrNull() in setOf('#', '!')) {
            scan.line = index + 1
            scan.flag()
        }
    }
}
