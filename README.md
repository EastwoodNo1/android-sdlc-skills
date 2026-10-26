# android-sdlc-skills

A Claude Code plugin, `android-sdlc`, with the SDLC tooling of [SuperSnake](https://github.com/EastwoodNo1/SuperSnake) as three skills:

| Skill | Use it to |
|-------|-----------|
| `android-sdlc:git-hooks` | install `.githooks/`, `scripts/bootstrap.sh`, `scripts/test-hooks.sh` and the strict Gradle wrapper |
| `android-sdlc:android-ci` | set up GitHub Actions, pinned tools, Dependabot, the `build-logic/checks` build, ktlint and the repo settings script |
| `android-sdlc:sdlc-rules` | learn the workflow: rules versus practices, flow, evidence, dependencies, versions, Dependabot |

The `templates/` directories under each skill are byte copies of SuperSnake files. `scripts/verify-templates.sh <consumer-repo>` lists every file that differs and exits 1 on drift.

## Install

In a project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "android-sdlc-skills": {
      "source": { "source": "github", "repo": "EastwoodNo1/android-sdlc-skills", "ref": "v0.1.0" }
    }
  },
  "enabledPlugins": { "android-sdlc@android-sdlc-skills": true }
}
```

Or by hand: `claude plugin marketplace add EastwoodNo1/android-sdlc-skills` and `claude plugin install android-sdlc@android-sdlc-skills`. Try it without installing: `claude --plugin-dir <path to this repo>`.

Docs used: https://code.claude.com/docs/en/plugins-reference, https://code.claude.com/docs/en/plugin-marketplaces, https://code.claude.com/docs/en/settings-reference, https://code.claude.com/docs/en/skills.

## Versions

SemVer tags. Consumers pin a tag. A skill counts as done only when it has been applied to a real project and the result was verified with evidence.
