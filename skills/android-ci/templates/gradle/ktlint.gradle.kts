import org.gradle.api.attributes.Bundling

val ktlint =
    configurations.create("ktlint") {
        attributes {
            attribute(Bundling.BUNDLING_ATTRIBUTE, objects.named(Bundling.SHADOWED))
        }
    }

val ktlintCli =
    project.extensions
        .getByType<VersionCatalogsExtension>()
        .named("libs")
        .findLibrary("ktlint-cli")
        .get()

dependencies {
    ktlint(ktlintCli)
}

class KtlintArguments(
    @get:Input val flags: List<String>,
    @get:Input val files: Provider<List<String>>,
) : CommandLineArgumentProvider {
    override fun asArguments(): Iterable<String> = flags + files.get()
}

class HasFiles(
    @get:Input val files: Provider<List<String>>,
) : Spec<Task> {
    override fun isSatisfiedBy(task: Task) = files.get().isNotEmpty()
}

@Suppress("UNCHECKED_CAST")
val trackedFiles = rootProject.extra["trackedFiles"] as Provider<String>

fun kotlinFiles(
    listing: Provider<String>,
    root: Directory,
): Provider<List<String>> =
    listing.map { text ->
        text
            .split('\u0000')
            .filter { it.isNotEmpty() }
            .filter { it.substringAfterLast('.', "") in setOf("kt", "kts") }
            .filter { root.file(it).asFile.isFile }
    }

val ktlintFiles = kotlinFiles(trackedFiles, layout.projectDirectory)

val unsafeMemoryAccess = "--sun-misc-unsafe-memory-access=allow"

fun registerKtlint(
    name: String,
    taskGroup: String,
    summary: String,
    flags: List<String>,
) = tasks.register<JavaExec>(name) {
    group = taskGroup
    description = summary
    classpath = ktlint
    mainClass = "com.pinterest.ktlint.Main"
    jvmArgs(unsafeMemoryAccess)
    argumentProviders.add(KtlintArguments(flags, ktlintFiles))
    onlyIf("Kotlin files are tracked", HasFiles(ktlintFiles))
}

val ktlintCheck =
    registerKtlint(
        "ktlintCheck",
        "verification",
        "Lints all Kotlin sources and scripts with the ktlint CLI.",
        emptyList(),
    )

registerKtlint(
    "ktlintFormat",
    "formatting",
    "Formats all Kotlin sources and scripts with the ktlint CLI.",
    listOf("-F"),
)

tasks.named("check") {
    dependsOn(ktlintCheck)
}
