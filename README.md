# android-sdlc-skills

A Claude Code plugin, `android-sdlc`, with SDLC tooling for Android/Kotlin Gradle projects as four skills:

| Skill | Use it to |
|-------|-----------|
| `android-sdlc:git-hooks` | install `.githooks/`, `scripts/bootstrap.sh`, `scripts/test-hooks.sh` and the strict Gradle wrapper |
| `android-sdlc:android-ci` | set up GitHub Actions, pinned tools, Dependabot, the `build-logic/checks` build, ktlint and the repo settings script |
| `android-sdlc:sdlc-rules` | learn the workflow: rules versus practices, flow, evidence, dependencies, versions, Dependabot |
| `android-sdlc:adlc-docs` | adopt automatic lifecycle documentation: copy `docs/adlc/` templates, add the policy, backfill, fold in staged notes |

The `templates/` directories under each skill are the source of truth. `scripts/verify-templates.sh <consumer-repo>` lists every template file that a project is missing or has changed and exits 1 on drift.

## ADLC documentation agent and hooks

The plugin registers two hooks in `hooks/hooks.json`. `SessionEnd` starts a detached capture: a headless run of the `android-sdlc:adlc-documenter` agent on Sonnet turns the session into a privacy-filtered note in `<git-common-dir>/adlc/staged/`. `SessionStart` backfills older sessions and reminds about waiting notes. Both do nothing in a repository without `docs/adlc/ADLC_PROCESS.md`. Before a pull request the same agent folds the notes into `docs/adlc/`. Details and the off switch are in the `adlc-docs` skill. Tests: `bash skills/adlc-docs/tests/run.sh`.

## Install

Claude Code installs plugins from a marketplace in two steps: add the marketplace, then install the plugin from it. This repo is both. Requires Claude Code with plugin support, `git` and access to GitHub.

### Option 1: inside Claude Code (recommended)

Start `claude` in your project and run:

```
/plugin marketplace add EastwoodNo1/android-sdlc-skills
/plugin install android-sdlc@android-sdlc-skills
```

Pick the scope when prompted (or use `--scope`): `user` for all your projects, `project` to share it with the team through `.claude/settings.json`, `local` for just you in this repo. Then run `/reload-plugins` (or restart Claude Code) and check with `/plugin` that `android-sdlc` is enabled. The skills show up as `/android-sdlc:git-hooks`, `/android-sdlc:android-ci`, `/android-sdlc:sdlc-rules` and `/android-sdlc:adlc-docs`.

To pin a release instead of the default branch, add the marketplace with a tag: `/plugin marketplace add EastwoodNo1/android-sdlc-skills#v0.3.0`.

### Option 2: from the terminal

The same steps as commands, which also work in scripts:

```bash
claude plugin marketplace add EastwoodNo1/android-sdlc-skills#v0.3.0 --scope project
claude plugin install android-sdlc@android-sdlc-skills --scope project
```

### Option 3: for a whole team, through settings

Commit this to a project's `.claude/settings.json`. Teammates are prompted to install the marketplace and plugin when they trust the folder:

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

### Try it without installing

```bash
git clone https://github.com/EastwoodNo1/android-sdlc-skills
claude --plugin-dir ./android-sdlc-skills
```

### Update or remove

```
/plugin marketplace update android-sdlc-skills
/plugin uninstall android-sdlc@android-sdlc-skills
```

When pinned to a tag, change `ref` (or re-add the marketplace with the new tag) to move to a newer release.

Docs used: https://code.claude.com/docs/en/plugins-reference, https://code.claude.com/docs/en/plugin-marketplaces, https://code.claude.com/docs/en/settings-reference, https://code.claude.com/docs/en/skills.

## Versions

SemVer tags. Consumers pin a tag. A skill counts as done only when it has been applied to a real project and the result was verified with evidence.
