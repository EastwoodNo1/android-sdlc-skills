plugins {
    base
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kover)
}

evaluationDependsOn(":app")

dependencies {
    kover(project(":domain"))
    kover(project(":data"))
}

val checks = configurations.create("checks")

dependencies {
    checks("sdlc:checks")
}

val noCommentsExtensions = setOf("kt", "kts", "xml", "toml", "yml", "yaml", "sh", "pro", "properties")

val trackedFiles =
    providers
        .exec {
            commandLine("git", "ls-files", "-z", "-co", "--exclude-standard")
        }.standardOutput.asText

extra["trackedFiles"] = trackedFiles

fun workflowFilesOf(
    listing: Provider<String>,
    root: Directory,
): Provider<List<String>> =
    listing.map { text ->
        text
            .split('\u0000')
            .filter { it.isNotEmpty() }
            .filter { Regex("""\.github/workflows/[^/]+\.ya?ml""").matches(it) }
            .filter { root.file(it).asFile.isFile }
    }

val workflowFiles = workflowFilesOf(trackedFiles, layout.projectDirectory)

val checkNoComments =
    tasks.register<JavaExec>("checkNoComments") {
        group = "verification"
        description = "Fails when a file in scope contains a comment."
        classpath = checks
        mainClass = "sdlc.checks.CliKt"
        val root = layout.projectDirectory
        args(
            listOf("no-comments") +
                trackedFiles
                    .get()
                    .split('\u0000')
                    .filter { it.isNotEmpty() }
                    .filter { it.substringAfterLast('.', "") in noCommentsExtensions }
                    .filter { root.file(it).asFile.isFile },
        )
    }

class ProvidedArguments(
    @get:Input val arguments: Provider<List<String>>,
) : CommandLineArgumentProvider {
    override fun asArguments(): Iterable<String> = arguments.get()
}

class NonEmpty(
    @get:Input val files: Provider<List<String>>,
) : Spec<Task> {
    override fun isSatisfiedBy(task: Task) = files.get().isNotEmpty()
}

fun registerCheck(
    name: String,
    summary: String,
    arguments: Provider<List<String>>,
) = tasks.register<JavaExec>(name) {
    group = "verification"
    description = summary
    classpath = checks
    mainClass = "sdlc.checks.CliKt"
    argumentProviders.add(ProvidedArguments(arguments))
}

fun gradleProp(name: String) = providers.gradleProperty(name)

registerCheck(
    "checkCommitMessage",
    "Validates one commit message file (-PmessageFile).",
    gradleProp("messageFile").map { listOf("commit-message", it) },
)

registerCheck(
    "checkCommitMessages",
    "Validates NUL-separated commit messages (-PmessagesFile).",
    gradleProp("messagesFile").map { listOf("commit-messages", it) },
)

val checkPullRequestTitle =
    registerCheck(
        "checkPullRequestTitle",
        "Validates the PR title (-PtitleFile).",
        gradleProp("titleFile").map { listOf("pr-title", it) },
    )

val checkPullRequestBody =
    registerCheck(
        "checkPullRequestBody",
        "Validates the PR body (-PbodyFile, -PlabelsFile).",
        gradleProp("bodyFile").zip(gradleProp("labelsFile")) { body, labels -> listOf("pr-body", body, labels) },
    )

val checkTestsChanged =
    registerCheck(
        "checkTestsChanged",
        "Requires test changes beside production changes (-PpathsFile).",
        gradleProp("pathsFile").map { listOf("tests-changed", it, "domain", "data") },
    )

registerCheck(
    "checkWorkflows",
    "Fails when a tracked GitHub workflow breaks the safety rules.",
    workflowFiles.map { listOf("workflows") + it },
).configure {
    onlyIf("workflow files are tracked", NonEmpty(workflowFiles))
}

val processReleaseMainManifest = project(":app").tasks.named("processReleaseMainManifest")

val releaseManifest =
    processReleaseMainManifest.map { task ->
        task.outputs.files.files
            .single { it.name == "AndroidManifest.xml" }
            .path
    }

registerCheck(
    "checkReleaseManifest",
    "Fails when the merged release manifest is not hardened.",
    releaseManifest.map { listOf("manifest", it) },
).configure {
    dependsOn(processReleaseMainManifest)
}

val backupRuleFiles = listOf("app/src/main/res/xml/backup_rules.xml", "app/src/main/res/xml/data_extraction_rules.xml")
val backupAllowedPaths = listOf("datastore/settings.txt", "datastore/high_scores.txt")

registerCheck(
    "checkBackupRules",
    "Fails when the backup rules include anything but the two DataStore files.",
    provider { listOf("backup-rules", backupAllowedPaths.joinToString(",")) + backupRuleFiles },
).configure {
    inputs.files(backupRuleFiles)
}

tasks.register("checkPullRequest") {
    group = "verification"
    description = "Runs the PR title, body and tests-changed checks."
    dependsOn(checkPullRequestTitle, checkPullRequestBody, checkTestsChanged)
}

tasks.named("check") {
    dependsOn(checkNoComments, "checkBackupRules")
}

apply(from = "gradle/ktlint.gradle.kts")
