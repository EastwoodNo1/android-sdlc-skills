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

The staging folder holds `staged/`, `digests/`, `log/`, `captured`, `lock`, and the owner's `enabled`, `disabled` and `deny-list` files, all under `<git-common-dir>/adlc/`.

## Claude Code (implemented)

- Trigger: plugin `hooks/hooks.json` with a top-level `"hooks"` wrapper, `SessionEnd` and `SessionStart`.
- `SessionEnd` stdin: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `reason`. The hook cannot block and has a 1.5 s budget, so capture runs as a fully detached process.
- Transcripts: `~/.claude/projects/<slug>/<session>.jsonl`, deleted after `cleanupPeriodDays` (default 30). Subagent transcripts: `<session>/subagents/agent-*.jsonl`.
- Headless: `claude -p --agent android-sdlc:adlc-documenter --model sonnet --permission-mode dontAsk --allowedTools ... --settings '{"disableAllHooks":true}' --no-session-persistence`.
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
