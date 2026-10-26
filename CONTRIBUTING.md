# Contributing

This repo follows the SuperSnake workflow where it applies to a repo that is not an Android app. The `sdlc-rules` skill describes it.

1. Open an issue that says why.
2. Work on a branch `<type>/<name>` in a git worktree: `git worktree add ../android-sdlc-skills-<name> -b <type>/<name>`.
3. Conventional Commits with `Why:` and `What:` in the body. A commit written by an agent ends with the `Co-Authored-By:` line of the model that wrote it.
4. No comments in `*.kt`, `*.kts`, `*.xml`, `*.toml`, `*.yml`, `*.yaml`, `*.sh`, `*.pro`, `*.properties`.
5. Open a PR. The title is a Conventional header of at most 64 characters. The body has `Closes #<issue>` and an `## Evidence` section with real command output or a CI link.
6. Squash merge only, once the required check `verify` is green and the branch is up to date with `main`.

Templates are copies. Change a file in SuperSnake first, then copy it here and run `scripts/verify-templates.sh <SuperSnake checkout>`: it must print `0 drift`.

Local checks: `scripts/verify-templates.sh ../SuperSnake`, `shellcheck`, `zizmor .github/`, and in `skills/android-ci/templates`: `mise exec -- ../../../gradlew -p build-logic/checks test koverVerify`.

Repo settings are applied with `scripts/github/apply-repo-settings.sh EastwoodNo1/android-sdlc-skills`.

Plugin format: https://code.claude.com/docs/en/plugins-reference. Validate with `claude plugin validate .`.
