package sdlc.checks

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class VersionCodeTest {
    private fun rejection(version: String) = assertFailsWith<IllegalArgumentException> { VersionCode.of(version) }.message.orEmpty()

    @Test
    fun oneZeroZero() = assertEquals(1_000_000, VersionCode.of("1.0.0"))

    @Test
    fun twoThreeFour() = assertEquals(2_003_004, VersionCode.of("2.3.4"))

    @Test
    fun trailingNewlineAccepted() = assertEquals(1_002_003, VersionCode.of("1.2.3\n"))

    @Test
    fun middleOfRange() = assertEquals(999_999_999, VersionCode.of("999.999.999"))

    @Test
    fun highestAccepted() = assertEquals(2_099_999_999, VersionCode.of("2099.999.999"))

    @Test
    fun placeholderKeepsCodeOne() = assertEquals(1, VersionCode.of("0.0.0"))

    @Test
    fun minorOverLimitRejected() {
        val message = rejection("1.1000.0")
        assertTrue("minor" in message && "1.1000.0" in message, message)
    }

    @Test
    fun patchOverLimitRejected() {
        val message = rejection("1.0.1000")
        assertTrue("patch" in message && "1.0.1000" in message, message)
    }

    @Test
    fun majorOverLimitRejected() {
        val message = rejection("2100.0.0")
        assertTrue("major" in message && "2100.0.0" in message, message)
    }

    @Test
    fun hugeNumberRejected() {
        val message = rejection("99999999999.0.0")
        assertTrue("major" in message, message)
    }

    @Test
    fun beyondLongRejected() {
        val message = rejection("99999999999999999999.0.0")
        assertTrue("major" in message, message)
    }

    @Test
    fun malformedRejected() {
        listOf("", "1.0", "1.0.0.0", "v1.0.0", "1.0.0-rc.1", "1.a.0", "01.0.0", "-1.0.0", "1. 0.0").forEach {
            assertTrue("format" in rejection(it), it)
        }
    }

    @Test
    fun monotonicAcrossBumps() {
        val codes = listOf("1.0.0", "1.0.1", "1.1.0", "1.999.999", "2.0.0").map(VersionCode::of)
        assertEquals(codes.sorted().distinct(), codes)
    }
}
