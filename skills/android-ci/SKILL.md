---
name: android-ci
description: Sets up GitHub Actions CI (checks, pr-rules, CodeQL), mise-pinned tools, Dependabot, the no-comments, commit, PR and workflow-safety checks (build-logic/checks), ktlint, and repo security settings for an Android/Kotlin Gradle project, re-verifying every pinned version first. Use when asked to set up CI, workflows, branch protection or repo settings, security scanning, dependency verification or Dependabot for such a project, or to refresh the pins.
---

# android-ci

Templates sit in `${CLAUDE_SKILL_DIR}/templates/` and are byte copies of SuperSnake. They record what was verified on the day they were made. Do not trust them: re-verify every version and SHA below on the day you use them. Show the evidence named in each step.

## Steps

1. Re-verify the pins. For each item, run the command, show its output, and compare with the template. If a newer stable exists, use it and record it in `docs/versions.md` (item, version, release date, source URL, date verified).
   - `actions/checkout`, `gradle/actions` (setup-gradle), `github/codeql-action` (init, analyze): `gh api repos/<owner>/<repo>/releases/latest` (codeql-action: list the `v4.x` releases, since latest returns the bundle tag) and `gh api repos/<owner>/<repo>/git/ref/tags/<tag>`. If the object type is `tag`, dereference it with `git/tags/<sha>` to the commit SHA. Workflows use the full commit SHA.
   - mise: latest release tag, then `curl -fsSL <release>/SHASUMS256.txt`, the linux-x64 archive line, and `gh attestation verify <archive> --repo jdx/mise`. The version and SHA-256 are written in three places (`checks` and `pr-rules` in ci.yml, `java-kotlin` in codeql.yml). Update all three together.
   - zizmor: latest stable from https://github.com/zizmorcore/zizmor/releases (not a pre-release). Also gh, Gradle (`https://services.gradle.org/versions/current`, wrapper SHA-256), Temurin (Adoptium API) and ktlint (Maven metadata). Update `mise.toml`, then run `mise lock` and `mise install --locked`.
   - Kotlin cap: Kotlin may only be as new as CodeQL lists at https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/. Evidence: the supported-version line you read.
2. Copy the templates: `.github/workflows/*`, `.github/dependabot.yml`, `.github/pull_request_template.md`, `SECURITY.md`, `mise.toml`, `mise.lock`, `.editorconfig`, `scripts/github/*`, `gradle/ktlint.gradle.kts`, `build-logic/checks/**`, and `scripts/gradle-strict.sh` (from the git-hooks templates). Evidence: `git status --short`.
3. Wire Gradle. `build.gradle.kts` and `gradle/libs.versions.toml` in the templates are references from SuperSnake: merge them, do not overwrite.
   - `settings.gradle.kts`: `includeBuild("build-logic/checks")`.
   - Root build: the `checks` configuration, `:checkNoComments`, `:checkCommitMessage`, `:checkCommitMessages`, `:checkPullRequest*`, `:checkWorkflows`, `:checkReleaseManifest` (only if there is an app module) and `apply(from = "gradle/ktlint.gradle.kts")`. `:checkTestsChanged` takes the module names whose `src/main` needs `src/test`.
   - Catalog: `kotlin`, `kover`, `junitBom`, `ktlint` versions and the `junit-bom`, `junit-jupiter`, `junit-platform-launcher`, `ktlint-cli` libraries, because `build-logic/checks/settings.gradle.kts` reads `gradle/libs.versions.toml`.
   - Always call root tasks with a leading colon (`:checkNoComments`), because AGP registers same-named tasks in `:app`.
4. Adapt the workflows to the project: SDK platform and build-tools in the `sdkmanager` line, the release build task, and the project's Gradle tasks. Keep: top-level `permissions: {}`, per-job least permissions, `persist-credentials: false`, actions pinned by full SHA, event data passed through `env:` only, no `pull_request_target` or `workflow_run`. Job names `checks`, `pr-rules`, `analyze (java-kotlin)` and `analyze (actions)` are the required checks. No comments in any yml, sh, kts, toml, xml.
5. Verify locally and show output: `mise exec -- zizmor .github/` with zero findings and no suppressions, then `ANDROID_HOME=<sdk> mise exec -- scripts/gradle-strict.sh check :checkNoComments :checkWorkflows`. Both must succeed. Add `gradle/verification-metadata.xml` with `./gradlew --write-verification-metadata sha256 check`, then strip any comments the tool wrote and re-run `:checkNoComments`.
6. Repo settings, only after the owner approves the outward step. Create the repo, push the initial commit to `main` first, then run `scripts/github/apply-repo-settings.sh <owner>/<repo>`. It applies squash-only merge (PR title and commit messages), the ruleset on the default branch (PR required, no bypass, linear history, conversation resolution, strict required checks), secret scanning with push protection, Dependabot alerts, private vulnerability reporting, a read-only default token and fork-PR approval, then compares the result with `expected-settings.json` and prints `all settings match`. Edit the required check names in both files if the workflow job names differ. Evidence: that output. Do not create a remote for a throwaway project.
7. Open the first PR. Its title is a Conventional header of at most 64 characters, its body has `Closes #<issue>` and a filled `## Evidence`. Wait for all required checks, then `gh pr merge <n> --squash`. Evidence: the CI run URL.

## Dependabot pull requests

A Dependabot PR only starts the work. Before it can merge, add commits that regenerate `gradle/verification-metadata.xml` (`./gradlew --write-verification-metadata sha256 check :app:assembleRelease :checks:check` with a fresh `GRADLE_USER_HOME` and `--refresh-dependencies`; add Linux-only artifacts such as the `aapt2` linux jar by hand after comparing SHA-1 with Google's `.sha1`), update `docs/versions.md`, and fill in Evidence. Strip tool-written comments. There are no bot exceptions. A Kotlin bump beyond the CodeQL-supported version stays open.

## Keeping in sync

`${CLAUDE_PLUGIN_ROOT}/scripts/verify-templates.sh <project>` prints one `drift:` line per differing file and `N drift`, exiting 1 on drift.
