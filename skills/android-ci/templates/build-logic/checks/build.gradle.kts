import kotlinx.kover.gradle.plugin.dsl.CoverageUnit

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kover)
}

group = "sdlc"

kotlin {
    jvmToolchain(25)
    compilerOptions {
        allWarningsAsErrors = true
    }
}

dependencies {
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
    testImplementation(kotlin("test-junit5"))
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.test {
    useJUnitPlatform()
    systemProperty("repoRoot", projectDir.resolve("../..").canonicalPath)
}

kover {
    reports {
        verify {
            rule {
                minBound(100, CoverageUnit.LINE)
                minBound(100, CoverageUnit.BRANCH)
            }
        }
    }
}
