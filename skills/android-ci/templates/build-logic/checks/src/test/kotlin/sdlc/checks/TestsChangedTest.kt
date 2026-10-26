package sdlc.checks

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TestsChangedTest {
    private val gated = setOf("domain", "data")

    @Test
    fun productionChangeWithoutTestChangeNamesTheModule() {
        val errors = TestsChanged.validate(listOf("domain/src/main/kotlin/A.kt"), gated)
        assertEquals(1, errors.size)
        assertTrue("domain" in errors.single())
    }

    @Test
    fun productionChangeWithTestChangeIsAccepted() {
        val paths = listOf("domain/src/main/kotlin/A.kt", "domain/src/test/kotlin/ATest.kt")
        assertEquals(emptyList(), TestsChanged.validate(paths, gated))
    }

    @Test
    fun testChangeInAnotherModuleDoesNotCount() {
        val paths = listOf("domain/src/main/kotlin/A.kt", "data/src/test/kotlin/BTest.kt")
        assertEquals(1, TestsChanged.validate(paths, gated).size)
    }

    @Test
    fun everyModuleMissingTestsIsReported() {
        val paths = listOf("domain/src/main/kotlin/A.kt", "data/src/main/kotlin/B.kt")
        assertEquals(2, TestsChanged.validate(paths, gated).size)
    }

    @Test
    fun ungatedModuleIsAccepted() {
        assertEquals(emptyList(), TestsChanged.validate(listOf("app/src/main/kotlin/X.kt"), gated))
    }

    @Test
    fun docsOnlyChangeIsAccepted() {
        assertEquals(emptyList(), TestsChanged.validate(listOf("docs/x.md"), gated))
    }

    @Test
    fun testOnlyChangeIsAccepted() {
        assertEquals(emptyList(), TestsChanged.validate(listOf("domain/src/test/kotlin/ATest.kt"), gated))
    }

    @Test
    fun moduleNameIsMatchedAsAWholeDirectory() {
        assertEquals(emptyList(), TestsChanged.validate(listOf("domain2/src/main/kotlin/A.kt"), gated))
    }
}
