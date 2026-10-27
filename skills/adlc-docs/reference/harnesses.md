# Harness adapters

The core does not know which agent tool produced a session. It works on three things:

- a digest: a Markdown file of the session's human prompts and the AI's visible replies, tool output dropped, each tool call reduced to one line
- a staged note: one Markdown file per session in `$(git rev-parse --path-format=absolute --git-common-dir)/adlc/staged/`
- the procedure: plain Markdown in `agents/adlc-documenter.md`, copied into each harness's own wrapper format

## Adapter contract

An adapter supplies three parts:

1. A session-end trigger that calls `session-end.sh <harness>` with the session's JSON on stdin.
2. A digest reader for the harness's transcript format: `digest.sh --format <harness>`.
3. A headless runner command for capture: `capture.sh` switches on the harness name.

Only `claude` is implemented. For `codex` and `copilot`, `session-end.sh` exits 0 with the stderr note "adapter not implemented".

The state folder holds `staged/`, `log/` (including `redactions.log`), `captured`, `failed`, `trivial`, `lock`, and the owner's `enabled`, `disabled` and `deny-list` files, all under `<git-common-dir>/adlc/`. Capture writes the digest and the agent writes its raw note in a private temporary directory outside `.git`, because Claude Code refuses writes inside `.git`; `capture.sh` redacts the note and moves it to `staged/`. The digest is regenerated on every run and is never kept in the state folder.

## Claude Code (implemented)

- Trigger: plugin `hooks/hooks.json` with a top-level `"hooks"` wrapper, `SessionEnd` and `SessionStart`.
- `SessionEnd` stdin: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `reason`. The hook cannot block and has a 1.5 s budget, so capture runs as a fully detached process.
- Transcripts: `~/.claude/projects/<slug>/<session>.jsonl`, deleted after `cleanupPeriodDays` (default 30). Subagent transcripts: `<session>/subagents/agent-*.jsonl`.
- Headless, run from the repository top level with `ADLC_CAPTURE=1` set:

```sh
claude -p --agent android-sdlc:adlc-documenter --model sonnet \
  --settings '{"disableAllHooks":true}' --no-session-persistence \
  --permission-mode dontAsk \
  --allowedTools "Read(/<workdir>/**)" "Read(/<toplevel>/**)" \
  "Grep(/<workdir>/**)" "Grep(/<toplevel>/**)" "Glob(/<workdir>/**)" "Glob(/<toplevel>/**)" \
  "Edit(/<workdir>/**)" --disallowedTools "Read(/<toplevel>/.git/**)" \
  -- "<prompt>"
```

  `<workdir>` is a fresh `mktemp -d` directory outside `.git`, resolved with `pwd -P`, and `<toplevel>` is the repository top level. Both start with `/`, so the rules begin with `//`, which Claude Code reads as an absolute path. Every rule is path-scoped: the agent reads only the work directory and the repository, and has no Bash rule. Checked with the real CLI: path-scoped `Grep(...)` and `Glob(...)` rules are accepted without a warning and deny paths outside them; a bare `Read` rule does not enable `Grep` or `Glob`. A `Write(path)` rule is ignored, so the agent uses `Edit`. The prompt's `DIGEST:` is `<workdir>/digest.md` and `NOTE:` is `<workdir>/<session_id>.md`. The agent writes only `NOTE`; `capture.sh` redacts it, moves it to `staged/` and deletes the directory.
  - Failure: `capture.sh` appends the session id to `failed`, one line per failure. Backfill and session start skip an id with two lines in `failed`. Backfill also records sessions with fewer than three prompts in `trivial` and skips them.
- Instructions file: `CLAUDE.md`.
- Source: https://code.claude.com/docs/en/hooks

## Codex CLI (not implemented)

Checked 2026-10-27.

- Instructions: `AGENTS.md`.
- Hooks: `~/.codex/hooks.json`, `<repo>/.codex/hooks.json`, or a `[hooks]` table in `config.toml`. A hook must be trusted through `/hooks` before it runs.
- `SessionEnd` stdin includes `transcript_path`, `session_id`, `cwd` and `reason`.
- Transcripts: `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<id>.jsonl`. The format is not a stable interface, so the digest reader needs fixtures and a version check.
- Skills: `.agents/skills`. Agents: TOML files in `.codex/agents/`.
- Headless: `codex exec "<task>"`, with `--json` and `-o`.
- Sources:
  - https://learn.chatgpt.com/docs/hooks
  - https://learn.chatgpt.com/docs/agent-configuration/agents-md
  - https://learn.chatgpt.com/docs/non-interactive-mode
  - https://learn.chatgpt.com/docs/agent-configuration/subagents

## GitHub Copilot CLI and VS Code agent (not implemented)

Checked 2026-10-27.

- Instructions: `.github/copilot-instructions.md` and `AGENTS.md`.
- Hooks: `.github/hooks/*.json`, shaped `{"version":1,"hooks":{...}}`.
- `sessionEnd` stdin has `sessionId`, `timestamp`, `cwd` and `reason`, and no transcript path. `transcriptPath` appears only on `agentStop`, `preCompact` and the subagent events. An adapter either captures on `agentStop` or derives the path from `sessionId`.
- Transcripts: `~/.copilot/session-state/<session>/events.jsonl`. This naming is unverified and the schema is undocumented.
- Skills: `.github/skills` and `.agents/skills`. Agents: `.github/agents/*.agent.md`.
- Headless: `copilot -p "<prompt>"` with `--allow-tool`, `--no-ask-user` and `--share=<file>`.
- Sources:
  - https://docs.github.com/en/copilot/reference/hooks-configuration
  - https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/run-cli-programmatically
  - https://code.visualstudio.com/docs/copilot/customization/hooks
  - https://code.visualstudio.com/docs/copilot/customization/custom-agents

## Gemini CLI (not implemented)

Checked 2026-10-27.

- Instructions: `GEMINI.md`. `AGENTS.md` is read only when `context.fileName` is set to include it.
- Hooks: `SessionEnd` with `transcript_path`, best effort.
- Sessions: `~/.gemini/tmp/<project_hash>/chats/`, 30-day default retention.
- Headless: `gemini -p`.
- Sources:
  - https://geminicli.com/docs/hooks/reference/
  - https://geminicli.com/docs/cli/session-management/
