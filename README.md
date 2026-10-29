# android-sdlc-skills

A Claude Code plugin, `android-sdlc`, with the SDLC tooling of [SuperSnake](https://github.com/EastwoodNo1/SuperSnake) as four skills:

| Skill | Use it to |
|-------|-----------|
| `android-sdlc:git-hooks` | install `.githooks/`, `scripts/bootstrap.sh`, `scripts/test-hooks.sh` and the strict Gradle wrapper |
| `android-sdlc:android-ci` | set up GitHub Actions, pinned tools, Dependabot, the `build-logic/checks` build, ktlint and the repo settings script |
| `android-sdlc:sdlc-rules` | learn the workflow: rules versus practices, flow, evidence, dependencies, versions, Dependabot |
| `android-sdlc:adlc-docs` | adopt automatic lifecycle documentation: copy `docs/adlc/` templates, add the policy, backfill, fold in staged notes |

The `templates/` directories under each skill are byte copies of SuperSnake files. `scripts/verify-templates.sh <consumer-repo>` lists every file that differs and exits 1 on drift.

## ADLC documentation agent and hooks

The plugin registers two hooks in `hooks/hooks.json`. `SessionEnd` starts a detached capture: a headless run of the `android-sdlc:adlc-documenter` agent on Sonnet turns the session into a privacy-filtered note in `<git-common-dir>/adlc/staged/`. `SessionStart` backfills older sessions and reminds about waiting notes. Both do nothing in a repository without `docs/adlc/ADLC_PROCESS.md`. Before a pull request the same agent folds the notes into `docs/adlc/`. Details and the off switch are in the `adlc-docs` skill. Tests: `bash skills/adlc-docs/tests/run.sh`.

## Install

In a project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "android-sdlc-skills": {
      "source": { "source": "github", "repo": "EastwoodNo1/android-sdlc-skills", "ref": "v0.3.0" }
    }
  },
  "enabledPlugins": { "android-sdlc@android-sdlc-skills": true }
}
```

Or by hand, pinned to the tag: `claude plugin marketplace add EastwoodNo1/android-sdlc-skills#v0.3.0 --scope project` and `claude plugin install android-sdlc@android-sdlc-skills`. Try it without installing: `claude --plugin-dir <path to this repo>`.

Docs used: https://code.claude.com/docs/en/plugins-reference, https://code.claude.com/docs/en/plugin-marketplaces, https://code.claude.com/docs/en/settings-reference, https://code.claude.com/docs/en/skills.

## Versions

SemVer tags. Consumers pin a tag. A skill counts as done only when it has been applied to a real project and the result was verified with evidence.
