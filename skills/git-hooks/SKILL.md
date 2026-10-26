---
name: git-hooks
description: Installs plain-shell git hooks (worktree-only commits, no commits or pushes on main, Conventional Commit messages, no-comments and ktlint on commit, zizmor and strict check on push) plus bootstrap.sh and test-hooks.sh into an Android/Kotlin Gradle project. Use when asked to set up git hooks, local checks, commit rules or a bootstrap script for such a project, or when the hooks are missing, drifting or failing.
---

# git-hooks

The hooks call Gradle tasks (`:checkNoComments`, `:ktlintCheck`, `:checkCommitMessage`) that come from the `android-sdlc:android-ci` skill. If the project's root build does not define them yet, run that skill's wiring steps first (its steps 2 and 3). Templates sit in `${CLAUDE_SKILL_DIR}/templates/` and are byte copies of the SuperSnake files they came from.

Show the evidence named in each step. Never say a step worked without it.

## Steps

1. Check the project. Run `git rev-parse --show-toplevel`, `git log --oneline | head -3` (test-hooks needs one commit) and `ls settings.gradle.kts gradlew`. Evidence: the output. The project needs a root `:checkNoComments`, `:ktlintCheck` and `:checkCommitMessage`, plus a `:domain` module with `kotlin.test` for the push test. Otherwise stop and do the android-ci wiring.
2. Copy the templates, keeping the executable bit:
   `cp -R ${CLAUDE_SKILL_DIR}/templates/.githooks .` and `cp ${CLAUDE_SKILL_DIR}/templates/scripts/*.sh scripts/`.
   Evidence: `ls -l .githooks scripts` showing `-rwxr-xr-x`.
3. Adapt only what is project-specific, then show `git diff` of those lines:
   - `scripts/bootstrap.sh`: the Android SDK package checks (`platforms/android-<compileSdk>`, `build-tools/<version>`, `cmdline-tools/latest`) and the `JDK_TOOL` name must match `mise.toml`. Keep the Adoptium checksum cross-check.
   - `scripts/test-hooks.sh`: replace the `io/github/eastwoodno1/supersnake/domain` paths and the `package` line with the project's domain package.
   - `scripts/gradle-strict.sh`: it allowlists one AGP 9.4.1 deprecation message. Run `./gradlew help --warning-mode=all`. If the project's AGP prints a different deprecation, report it rather than widening the allowlist. If it prints none, remove the allowlist line.
   - No comments in any file (`#` lines in `*.sh` are not allowed, a shebang is). Evidence: `./gradlew :checkNoComments` output.
4. Create `local.properties` with `sdk.dir=<Android SDK path>` (it is git-ignored and `test-hooks.sh` copies it). Evidence: `grep -c '^local.properties' .gitignore`.
5. Run `scripts/bootstrap.sh`. Evidence: its output, ending with the Android SDK package lines and `hooks installed`, and `git config core.hooksPath` printing `.githooks`.
6. Commit the hooks (in a linked worktree, since the hooks refuse commits in the main checkout; the first bootstrap commit on a brand new repo may use `git -c core.hooksPath=/dev/null commit`). Use a Conventional message with Why: and What:.
7. Run `scripts/test-hooks.sh`. Required evidence: the nine `PASS` lines and the final line `9/9 passed`. A `FAIL` line is a real defect: fix it, do not edit the test to pass.

## What the hooks enforce

- pre-commit: refuses commits in the main checkout (`git rev-parse --git-dir` equals `--git-common-dir`) and on `main`, then runs `:checkNoComments` and `:ktlintCheck`.
- commit-msg: `:checkCommitMessage` (Conventional Commits, body with Why: and What: for feat, fix, refactor, perf).
- pre-push: refuses `main`, runs `zizmor --offline .github/workflows/`, then `scripts/gradle-strict.sh check`.
- CI re-runs everything, so `--no-verify` changes nothing about what can merge. Merges are squash only.

## Keeping in sync

Run `${CLAUDE_PLUGIN_ROOT}/scripts/verify-templates.sh .` from a checkout of the plugin to list drift between the project and the templates.
