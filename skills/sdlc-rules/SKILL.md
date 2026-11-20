---
name: sdlc-rules
description: The SDLC for Android/Kotlin projects. Rules (machine-enforced) versus practices (taught), the per-change flow with issue, worktree, test first, small Conventional commits and squash-merged PRs, the evidence rule, flaky UI tests, the third-party dependency rule, version verification with the CodeQL Kotlin cap, Dependabot handling, and releases through release-please, approval-gated signing and immutable GitHub releases. Use before starting or reviewing any change, writing a commit or PR, adding a dependency, bumping a version, cutting or recovering a release, investigating a flaky or timed-out UI test, or when asked how work is done in the project.
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
8. Merge. Squash only, once the required checks (`checks`, `pr-rules`, `analyze (java-kotlin)`, `analyze (actions)`, `ui-tests (phone-31)`, `ui-tests (phone-37)`, `ui-tests (tablet-37)`, `release-smoke`, or the project's list) are green and the branch is up to date with `main`: `gh pr merge <n> --squash`. Then pull `--ff-only` on `main`, remove the worktree, delete the branch, `git fetch --prune`. Review comment threads must be resolved. AI reviews run locally and are optional.
   - The live ruleset decides what blocks a merge, not `scripts/github/expected-settings.json`. The two match only after the owner has run `apply-repo-settings.sh`. Before relying on auto-merge, or before calling a PR done, compare them (read-only; the procedure is in the `android-sdlc:android-ci` skill, "Live required checks"). Until they match, wait for every check on the PR, not only the required ones, and report every check by name with its result. A check that is in `expected-settings.json` but missing from the live ruleset does not block the merge button, so a red or pending one there is still a blocker for you. Only the owner runs `apply-repo-settings.sh`, in any mode.

## Rules and practices

- Rules are machine-enforced locally and in CI: no direct commits or pushes to `main`, worktree-only commits, a linked issue, tests with production changes in `:domain` or `:data`, Conventional Commits, no comments, ktlint and Lint at zero issues, tests and 100% line and branch coverage on gated modules, dependency verification, CodeQL, manifest hardening, a non-empty Evidence section, squash-only linear history, safe workflows. `--no-verify` changes nothing about what can merge.
- Practices are taught and not gated: test first, stacking, small one-concern PRs, one worktree per branch. Say plainly that they are practices.
- No comments in `*.kt`, `*.kts`, `*.xml`, `*.toml`, `*.yml`, `*.yaml`, `*.sh`, `*.pro`, `*.properties` (a shebang is allowed). This includes generated files: strip comments tools write, then run `:checkNoComments`. Markdown is not checked.

## Flaky UI tests (practice)

A UI test leg that goes red and then passes on a rerun is a bug until shown otherwise, usually in the test, not in the emulator. Typical causes: a sample that runs past a timed state (a countdown) into the next screen, a coroutine cancelled without being joined before the same resource (a DataStore file) is opened again, and a multi-pass test that resets its state only once.

1. Find the test that failed in the run's test-result artifact (the JUnit XML) and read its failure and stack trace. Do not guess from the job log.
2. Get a deterministic RED: force the state or timing that broke it, for example by seeding the data or asserting the time window the test relies on. Then fix it and show it green. Reproduce on a local AVD.
3. If an intermittent failure cannot be forced, use a statistical RED. Loop the single test N times on the base commit, then on the fix, and report both counts and the chance of the clean run being luck. Example: 4 of 20 runs hung before the fix and 30 of 30 passed after; with a failure rate of 0.2, a clean 30 has odds of 0.8^30 ≈ 0.0012.
4. Use a dedicated test AVD. Never boot the owner's own (playtest) AVD for test runs, and never uninstall or wipe an app the owner installed on any AVD. A test run can replace an installed build or fail with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, and the AVD may not come back as the owner left it.
5. Reruns: at most two, then investigate. A one-off red on a required leg (during a release PR, say) gets at most two reruns plus a local loop of the failing test before the merge; record the test, the failure and the loop counts in the PR so a pattern shows if it recurs. Two job timeouts on one PR mean a hang that the PR caused.
6. Run instrumented tests under the AndroidX Test Orchestrator (setup in the `android-sdlc:android-ci` skill), so one wedged test fails alone instead of timing out the rest of the leg. It costs about 3 to 6 minutes per leg; say so when you add it.
7. When a UI leg hits its job timeout, find the wedged test from the result artifact: compute each test's duration from the per-test logcat files. A run of tests that each took about the per-test timeout means a wedged process, and the first of them is the culprit. For the stacks, use the runner's `THREAD_STATE` dump (Java) and, while it hangs on a local AVD, `adb root` then `adb shell debuggerd -b <pid>` (native).

## Evidence rule

Nobody says works, passes, fixed or done without the command and its actual output, a CI run link, or a screenshot or recording for UI. A dependency change needs the version source. Never infer a result. Subagents run on the model the project names, and their commits carry that model's `Co-Authored-By:` line.

## Dependency rule (spec §6)

Prefer the Kotlin standard library, the Android platform, AndroidX and Jetpack, JetBrains and Google. A third-party dependency needs a large, very active community and the PR must show: star count, last commit date, last stable release date, open and closed issue activity. A runtime dependency also needs a short ADR in `docs/adr/`.

## Verify a version before using it

1. Latest stable only, from a primary source on the day (`maven-metadata.xml` without alpha, beta, rc, dev, EAP, or the project's release page).
2. Check compatibility with the toolchain (AGP's Gradle and JDK needs).
3. Record version, release date, source URL and date in `docs/versions.md`.
4. Kotlin cap: Kotlin goes no higher than the newest version on https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/. A Dependabot Kotlin bump beyond it stays open until CodeQL lists it, and `.github/dependabot.yml` ignores `org.jetbrains.kotlin*` versions above the cap.
5. Tools come from `mise.toml` and `mise.lock`: `mise install --locked`.

## A new stable release blocks every branch

Lint's `AndroidGradlePluginVersion` (AGP) and `GradleDependency` checks fail `:app:lintDebug` the day a newer stable is published. With warnings as errors, that blocks the pre-push gate and every PR's `checks` at once, even PRs that touch nothing related. Do not suppress or baseline the check, and do not bump inside the blocked PR. Open a separate bump PR first, merge it, then rebase the blocked work on `main`.

The bump PR:

1. Bump the version after the "Verify a version before using it" steps above.
2. Regenerate `gradle/verification-metadata.xml` with a fresh `GRADLE_USER_HOME` and `--refresh-dependencies` over `check :app:assembleRelease :checks:check`, plus one real `:app:connectedDebugAndroidTest` run, so the test platform (UTP) artifacts that only a device run resolves are covered.
3. Remove every old companion entry and check that each removed component has a new counterpart. For AGP that is the old `gradle` version, the matching `32.x.y` tools components (lint, sdk-common and the rest) and the `<version>-<build>` artifacts such as `aapt2`.
4. Add the Linux-only `aapt2` jar by hand (a macOS run does not resolve it), after comparing its SHA-1 with Google's published `.sha1` file.
5. Update the `docs/versions.md` row with the version, the `last-modified` header of the new POM as the release date, the source URL and the date verified.

The CI `checks` of the bump PR is the evidence that the block is gone; then rebase and re-run the blocked PRs.

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
