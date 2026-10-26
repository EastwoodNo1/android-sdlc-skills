package sdlc.checks

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class NoCommentsTest {
    private fun lines(
        path: String,
        content: String,
    ) = NoComments.scan(path, content).map { it.line }

    private fun kotlin(content: String) = lines("A.kt", content)

    private fun xml(content: String) = lines("a.xml", content)

    private fun hash(content: String) = lines("a.yml", content)

    private fun properties(content: String) = lines("a.properties", content)

    @Test
    fun findingIsReportedWithPathLineAndMessage() {
        val findings = NoComments.scan("src/A.kt", "val a = 1\nval b = 2 // x")
        assertEquals(
            listOf(
                Finding(
                    "src/A.kt",
                    2,
                    "comment not allowed (why/what belong in the commit message)",
                ),
            ),
            findings,
        )
        assertEquals(
            "src/A.kt:2: comment not allowed (why/what belong in the commit message)",
            findings.single().toString(),
        )
    }

    @Test
    fun kotlinLineCommentFlagged() = assertEquals(listOf(1), kotlin("val a = 1 // x"))

    @Test
    fun kotlinBlockCommentFlagged() = assertEquals(listOf(1), kotlin("/* x */"))

    @Test
    fun kotlinKdocFlagged() = assertEquals(listOf(1), kotlin("/** x */"))

    @Test
    fun kotlinNestedBlockIsOneFindingAndCodeAfterIsClean() {
        assertEquals(listOf(1), kotlin("/* a /* b */ c */ val x = 1"))
        assertEquals(listOf(1), kotlin("/* a /* b */ c */ val s = \"//\""))
    }

    @Test
    fun kotlinStringsIgnored() = assertEquals(emptyList<Int>(), kotlin("val u = \"https://x/*y*/\""))

    @Test
    fun kotlinRawStringIgnored() = assertEquals(emptyList<Int>(), kotlin("val r = \"\"\" // not \"\"\""))

    @Test
    fun kotlinTemplateIgnored() = assertEquals(emptyList<Int>(), kotlin("val t = \"\${ \"a//b\" }\""))

    @Test
    fun kotlinCharLiteralIgnored() = assertEquals(emptyList<Int>(), kotlin("val c = '/'"))

    @Test
    fun kotlinEscapedQuoteDoesNotEndString() {
        assertEquals(emptyList<Int>(), kotlin("val s = \"a\\\"//b\""))
        assertEquals(emptyList<Int>(), kotlin("val c = '\\''"))
    }

    @Test
    fun kotlinCharQuoteDoesNotStartString() = assertEquals(listOf(1), kotlin("val c = '\"' // x"))

    @Test
    fun kotlinCommentAfterStringsIsFlagged() {
        assertEquals(listOf(1), kotlin("val r = \"\"\"a\"\"\" // x"))
        assertEquals(listOf(1), kotlin("val s = \"a\" // x"))
    }

    @Test
    fun kotlinTemplateWithBracesInsideKeepsScanning() {
        assertEquals(emptyList<Int>(), kotlin("val t = \"\${ f { 1 } }//x\""))
        assertEquals(listOf(1), kotlin("val t = \"\${ f { 1 } /* c */ }\""))
    }

    @Test
    fun kotlinTemplateInRawStringIgnored() {
        assertEquals(emptyList<Int>(), kotlin("val r = \"\"\"\${ \"//\" } //\"\"\""))
    }

    @Test
    fun kotlinDollarWithoutBraceIsPlainText() = assertEquals(emptyList<Int>(), kotlin("val s = \"\$a // \$\""))

    @Test
    fun kotlinBracesInCodeAreBalanced() {
        assertEquals(listOf(2), kotlin("fun f() {\n} // x"))
        assertEquals(listOf(1), kotlin("} // x"))
    }

    @Test
    fun kotlinUnterminatedConstructsEndAtEndOfInput() {
        assertEquals(emptyList<Int>(), kotlin("val s = \"abc"))
        assertEquals(emptyList<Int>(), kotlin("val s = \"abc\\"))
        assertEquals(emptyList<Int>(), kotlin("val c = '"))
        assertEquals(listOf(1), kotlin("/* open"))
        assertEquals(emptyList<Int>(), kotlin("val r = \"\"\"abc"))
    }

    @Test
    fun kotlinScriptsAreScannedToo() {
        assertEquals(listOf(1), lines("build.gradle.kts", "x // y"))
    }

    @Test
    fun kotlinLineNumberIsWhereCommentStarts() {
        assertEquals(listOf(2), kotlin("a\n/* x\ny\nz */"))
        assertEquals(listOf(1, 3), kotlin("// a\nb\n// c"))
        assertEquals(listOf(3), kotlin("val r = \"\"\"a\nb\n\"\"\" // x"))
    }

    @Test
    fun xmlCommentFlagged() = assertEquals(listOf(1), xml("<a/><!-- x -->"))

    @Test
    fun xmlCdataIgnored() = assertEquals(emptyList<Int>(), xml("<a><![CDATA[<!-- -->]]></a>"))

    @Test
    fun xmlAttributeIgnored() {
        assertEquals(emptyList<Int>(), xml("<a b=\"<!--\"/>"))
        assertEquals(emptyList<Int>(), xml("<a b='<!--'/>"))
    }

    @Test
    fun xmlQuotesInTextAreNotAttributes() {
        assertEquals(listOf(1), xml("<a>it's \"x\"</a><!-- x -->"))
    }

    @Test
    fun xmlCommentAfterTagWithAttributesFlagged() {
        assertEquals(listOf(2), xml("<a b=\"c\" d='e'>\n<!-- x\ny -->\n</a>"))
        assertEquals(listOf(1, 2), xml("<!-- a --><b/>\n<!-- c -->"))
    }

    @Test
    fun xmlUnterminatedCommentEndsAtEndOfInput() {
        assertEquals(listOf(1), xml("<!-- x"))
        assertEquals(emptyList<Int>(), xml("<![CDATA[ x"))
    }

    @Test
    fun hashLineStartFlagged() = assertEquals(listOf(1), hash("# x"))

    @Test
    fun hashAfterWhitespaceFlagged() = assertEquals(listOf(1), hash("a = 1 # x"))

    @Test
    fun hashInsideWordIgnored() = assertEquals(emptyList<Int>(), hash("url: a#b"))

    @Test
    fun hashSingleQuotesIgnored() = assertEquals(emptyList<Int>(), hash("c: '#fff'"))

    @Test
    fun hashDoubleQuotesIgnored() = assertEquals(emptyList<Int>(), hash("c: \"#fff\""))

    @Test
    fun hashEscapedQuoteDoesNotEndDoubleQuotes() = assertEquals(emptyList<Int>(), hash("c: \"a\\\" #b\""))

    @Test
    fun hashBackslashInSingleQuotesIsLiteral() = assertEquals(listOf(1), hash("c: 'a\\' # x"))

    @Test
    fun hashOtherQuoteInsideQuotesIsText() {
        assertEquals(emptyList<Int>(), hash("c: \"it's #x\""))
        assertEquals(emptyList<Int>(), hash("c: 'say \"#x\"'"))
    }

    @Test
    fun hashQuoteEndsAtNewline() = assertEquals(listOf(2), hash("it's\n# x"))

    @Test
    fun hashShellDollarHashIgnored() = assertEquals(emptyList<Int>(), lines("a.sh", "echo \$#"))

    @Test
    fun hashShellLengthExpansionIgnored() = assertEquals(emptyList<Int>(), lines("a.sh", "echo \${#v}"))

    @Test
    fun hashShebangOnLineOneAllowed() {
        assertEquals(emptyList<Int>(), lines("a.sh", "#!/bin/sh"))
        assertEquals(listOf(2), lines("a.sh", "#!/bin/sh\n# x"))
    }

    @Test
    fun hashShebangOnLineTwoFlagged() = assertEquals(listOf(2), lines("a.sh", "echo\n#!/bin/sh"))

    @Test
    fun hashHashBangThatIsNotShebangFlagged() = assertEquals(listOf(1), hash("# !x"))

    @Test
    fun hashEveryExtensionIsScanned() {
        listOf("a.toml", "a.yml", "a.yaml", "a.sh", "a.pro").forEach {
            assertEquals(listOf(1), lines(it, "# x"), it)
        }
    }

    @Test
    fun hashMultipleCommentsFlaggedOnEachLine() = assertEquals(listOf(1, 3), hash("# a\nb: 1\nc: 2 # d"))

    @Test
    fun propertiesHashAtLineStartFlagged() = assertEquals(listOf(1), properties("#Tue Oct 20"))

    @Test
    fun propertiesBangAtLineStartFlagged() = assertEquals(listOf(1), properties("! x"))

    @Test
    fun propertiesHashInsideValueIgnored() = assertEquals(emptyList<Int>(), properties("k=v#1"))

    @Test
    fun propertiesIndentedCommentFlaggedAndBlankLinesSkipped() {
        assertEquals(listOf(3), properties("a=1\n\n   # x"))
        assertEquals(emptyList<Int>(), properties("a=1\n\n   b=2"))
    }

    @Test
    fun propertiesBangInsideValueIgnored() = assertEquals(emptyList<Int>(), properties("k=v!1"))

    @Test
    fun outOfScopeFilesAreIgnored() {
        assertEquals(emptyList<Int>(), lines("README.md", "<!-- x -->"))
        assertEquals(emptyList<Int>(), lines("Makefile", "# x"))
        assertEquals(emptyList<Int>(), lines("dir.kt/Makefile", "# x"))
    }

    @Test
    fun backtickIdentifierWithApostropheDoesNotHideALaterComment() {
        assertEquals(listOf(1), kotlin("fun `doesn't throw`() {} // x"))
    }

    @Test
    fun commentMarkerInsideBacktickIdentifierIsNotAComment() {
        assertEquals(emptyList(), kotlin("fun `a // b`() {}"))
    }

    @Test
    fun unterminatedBacktickEndsAtTheLine() {
        assertEquals(listOf(2), kotlin("val a = `b\nval c = 1 // x"))
    }

    @Test
    fun unterminatedBacktickEndsAtEndOfFile() {
        assertEquals(emptyList(), kotlin("val a = `b"))
    }
}
