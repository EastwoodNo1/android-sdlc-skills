---
name: sdlc-rules
description: The SDLC for Android/Kotlin projects. Rules (machine-enforced) versus practices (taught), the per-change flow with issue, worktree, test first, small Conventional commits and squash-merged PRs, the evidence rule, the third-party dependency rule, version verification with the CodeQL Kotlin cap, Dependabot handling, and releases through release-please, approval-gated signing and immutable GitHub releases. Use before starting or reviewing any change, writing a commit or PR, adding a dependency, bumping a version, cutting or recovering a release, or when asked how work is done in the project.
---

# sdlc-rules

Source of truth: the project's `CONTRIBUTING.md`, `CLAUDE.md` and the design spec §6, §7, §13.12 and §13.13. If the project's copy disagrees with this skill, the project wins and you report the difference.

## Flow for every change

Show the evidence named for each step.

1. Issue. `gh issue create` stating why. Evidence: the issue URL.
2. Worktree. `git worktree add ../<repo>-<name> -b <type>/<name>`. Copy `local.properties` into it. The main checkout stays on `main` and is only for syncing; the hooks refuse commits there. Evidence: `git worktree list`.
3. Test first (practice). Write a failing test, run it, see it fail, then write the code. Evidence: the failing output, then the passing output.
4. Small commits. Conventional Commits, `type(scope): subject`. The body states `Why:` and `What:` and is required for `feat`, `fix`, `refactor`, `perf`. A commit written by an agent ends with the `Co-Authored-By:` line of the model that wrote it. Never put the why or what in code comments.
5. Stack large work (practice) as small PRs with `gh stack` (pinned version in `scripts/bootstrap.sh`).
6. Checks. Run `scripts/gradle-strict.sh check` before pushing, plus `:checkNoComments`, `:checkWorkflows` when relevant. Root tasks take a leading colon. Evidence: the command and its output.
7. Pull request. Title is a Conventional header of at most 64 characters. Body: `Why`, `What`, `Closes #<issue>`, `## Evidence`. Run `:checkPullRequest` on the title and body first.
8. Merge. Squash only, once the required checks (`checks`, `pr-rules`, `analyze (java-kotlin)`, `analyze (actions)`, `ui-tests (phone-31)`, `release-smoke`, or the project's list) are green and the branch is up to date with `main`: `gh pr merge <n> --squash`. Then pull `--ff-only` on `main`, remove the worktree, delete the branch, `git fetch --prune`. Review comment threads must be resolved. AI reviews run locally and are optional.

## Rules and practices

- Rules are machine-enforced locally and in CI: no direct commits or pushes to `main`, worktree-only commits, a linked issue, tests with production changes in `:domain` or `:data`, Conventional Commits, no comments, ktlint and Lint at zero issues, tests and 100% line and branch coverage on gated modules, dependency verification, CodeQL, manifest hardening, a non-empty Evidence section, squash-only linear history, safe workflows. `--no-verify` changes nothing about what can merge.
- Practices are taught and not gated: test first, stacking, small one-concern PRs, one worktree per branch. Say plainly that they are practices.
- No comments in `*.kt`, `*.kts`, `*.xml`, `*.toml`, `*.yml`, `*.yaml`, `*.sh`, `*.pro`, `*.properties` (a shebang is allowed). This includes generated files: strip comments tools write, then run `:checkNoComments`. Markdown is not checked.

## Evidence rule

Nobody says works, passes, fixed or done without the command and its actual output, a CI run link, or a screenshot or recording for UI. A dependency change needs the version source. Never infer a result. Subagents run on the model the project names, and their commits carry that model's `Co-Authored-By:` line.

## Dependency rule (spec §6)

Prefer the Kotlin standard library, the Android platform, AndroidX and Jetpack, JetBrains and Google. A third-party dependency needs a large, very active community and the PR must show: star count, last commit date, last stable release date, open and closed issue activity. A runtime dependency also needs a short ADR in `docs/adr/`.

## Verify a version before using it

1. Latest stable only, from a primary source on the day (`maven-metadata.xml` without alpha, beta, rc, dev, EAP, or the project's release page).
2. Check compatibility with the toolchain (AGP's Gradle and JDK needs).
3. Record version, release date, source URL and date in `docs/versions.md`.
4. Kotlin cap: Kotlin goes no higher than the newest version on https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/. A Dependabot Kotlin bump beyond it stays open until CodeQL lists it.
5. Tools come from `mise.toml` and `mise.lock`: `mise install --locked`.

## Dependabot pull requests (spec §13.13)

Version updates and security alerts are on, grouped, with prefix `build` or `ci` and the `dependencies` label (which satisfies the issue-link check). A Dependabot PR only starts the work and cannot merge until someone adds commits that regenerate `gradle/verification-metadata.xml`, update `docs/versions.md` and fill in Evidence. There are no bot exceptions. Procedure: the `android-sdlc:android-ci` skill.

## Process steps a machine cannot fully check (spec §13.12)

Enforced: the issue link and tests with production changes. Taught, not enforced: one worktree per branch (partly enforced by the commit hook), test first (the coverage gate still catches a missing test), splitting large work into stacks.

## Release

Releases come only from `main`, through `.github/workflows/release.yml`, and are immutable once published. The project's release runbook and spec win over this summary; the full pipeline is in the `android-sdlc:android-ci` skill.

1. Merge PRs with Conventional titles. release-please (run with a GitHub App token, because PRs and tags made with `GITHUB_TOKEN` start no workflows) keeps one release PR open, labelled `autorelease: pending`, that bumps `version.txt` and the changelog. `pr-rules` exempts the `autorelease: pending` and `autorelease: tagged` labels from the issue-link and Evidence rules.
2. Merging the release PR makes release-please create the tag `vX.Y.Z` and a draft release. The same run builds and smoke-tests the unsigned release APK, then waits.
3. The owner approves the pending `release` environment deployment. Only then is the APK signed, its certificate checked fail-closed against `RELEASE_CERT_SHA256` (`apksigner -J-enable-native-access=ALL-UNNAMED verify -v --print-certs`: `Verifies`, one signer, matching SHA-256), checksummed, attested with `actions/attest`, uploaded to the draft and published. A last job verifies the published release.
4. `versionCode = major*1_000_000 + minor*1_000 + patch` from `version.txt`; `0.0.0` maps to 1.
5. Failures: while the draft is unpublished, re-run only the failed jobs, `gh run rerun <id> --failed`. Never re-run the whole run (release-please then reports no release and every later job is skipped silently). A burned version (the release-please job failed after tagging, an approval timed out, or anything failed after publish) is never reused: set `release-as` to the next patch in `release-please-config.json` in the fixing PR. Tags are never moved or deleted by hand; the `release-tags` ruleset lets only the release App touch `v*` tags.
6. An agent never handles the signing key, its passwords or the App private key, and never runs the repo settings script; the owner does.
