---
name: adlc-docs
description: Adopts and runs automatic ADLC/SDLC lifecycle documentation: a session-end hook captures each non-trivial AI coding session into a privacy-filtered staged note, and a documenter agent folds the notes into docs/adlc/ in the next pull request. Use when asked to adopt lifecycle documentation, set up docs/adlc, fold in staged session notes, backfill past sessions, do an end-of-project fold-in, gather presentation material from the project history, or when a session-start message says session notes are waiting.
---

# adlc-docs

Capture is automatic and per repository. A `SessionEnd` hook starts a detached headless run of `android-sdlc:adlc-documenter` for every session with at least three human prompts. The result is a redacted note in the staged folder. A session that is resumed and gains at least three more human prompts is captured again when it ends: the new note, `<date>-<id>-<n>.md`, covers only the turns after the previous capture, and fold-in appends it to that session's existing record. A repository takes part only when `docs/adlc/ADLC_PROCESS.md` exists.

State folder, used below as `<state>`: `$(git rev-parse --path-format=absolute --git-common-dir)/adlc`. It is shared by all worktrees and is never committed. Templates, the policy text, the privacy rules and the harness notes are in `${CLAUDE_SKILL_DIR}/templates/`, `${CLAUDE_SKILL_DIR}/reference/policy.md`, `${CLAUDE_SKILL_DIR}/reference/privacy.md` and `${CLAUDE_SKILL_DIR}/reference/harnesses.md`.

Show real command output for every step. Never say a step worked without it.

## Adopt

1. Copy `${CLAUDE_SKILL_DIR}/templates/docs/adlc/` to `docs/adlc/` in the project. Do not overwrite files that already exist.
2. Add the policy block from `${CLAUDE_SKILL_DIR}/reference/policy.md` (the text after the `---`) to `CLAUDE.md`, or to `AGENTS.md` or `GEMINI.md` for other harnesses.
3. Create the owner switch: `mkdir -p <state> && touch <state>/enabled`.
4. Tell the owner to consider `"cleanupPeriodDays": 365` in their user settings. Claude Code deletes transcripts after 30 days by default, and backfill and late capture need them. Do not edit user settings.
5. Run backfill (below) to capture sessions that already exist.
6. Commit the templates and the policy through the project's normal PR flow.

Optional: write one term per line into `<state>/deny-list`. Capture removes every listed term from notes. Optionally list internal issue tracker project keys, one per line such as `ABC`, in `<state>/issue-keys`: capture and `scan.sh` then redact and flag `ABC-<number>`. Never commit these files.

## Fold-in

Before opening or updating a pull request, check `<state>/staged/`. If it holds notes, follow the "Fold-in before a pull request" steps in `${CLAUDE_SKILL_DIR}/reference/policy.md`:

1. Run `android-sdlc:adlc-documenter` with a prompt that starts `MODE: fold-in`, then `STAGED: <state>/staged` and `REPO: <worktree path>`.
2. Run `bash ${CLAUDE_SKILL_DIR}/scripts/scan.sh docs/adlc "$(git rev-parse --path-format=absolute --git-common-dir)/adlc"`. It prints `file:line: class` for each privacy hit and exits 1. Fix every hit first, then run it again until it exits 0.
3. Commit the result as `docs(adlc): fold in session notes`.
4. Save the lessons the agent returns as memories, after checking for duplicates.
5. Delete the folded files from `staged/`, only after the commit. The agent copies the notes and never deletes them.

## Fold in now

At the end of a project, or before building a presentation, fold in everything at once: run the fold-in above on a branch `docs/adlc-final` in a worktree and open one pull request titled `docs(adlc): fold in session notes`. Then use `docs/adlc/PRESENTATION_SOURCE_GUIDE.md` as the entry point for the presentation.

## Backfill

`bash ${CLAUDE_SKILL_DIR}/scripts/backfill.sh [--harness claude] [--project-dir <dir>] [--limit N] [--exclude <session id>]`

It captures stored sessions of the project that are not yet in `<state>/captured`, and sessions that grew by at least three human prompts since their last capture. Run it from the repository, or pass `--project-dir`. `session-start.sh` also runs it in the background for up to three sessions each time a session starts.

## Off switch

- This repository: `touch <state>/disabled`.
- One session: start it with `ADLC_DISABLE=1`.
- Remove `<state>/disabled` to turn capture on again.

## Troubleshooting

Each capture writes `<state>/log/<session id>.log`, and backfill writes `<state>/log/backfill.log`. Read the log of the session that has no note. Common causes: `claude` is not on the PATH of the hook, a lock in `<state>/lock` held by a running capture (a lock older than 30 minutes is broken automatically), or a session with fewer than three prompts, which is skipped on purpose. A note is staged only after mechanical redaction (emails, home paths, secret-shaped tokens, listed issue keys and deny-list terms) has succeeded. Model-side filtering by the documenter and `scan.sh` at fold-in are the other layers. Redactions are logged by class in `<state>/log/redactions.log`.

A failed capture appends the session id to `<state>/failed`, one line per failure. Backfill and session start skip an id that has two lines there. To retry it, delete that id's lines from `failed` and run backfill. Sessions with fewer than three prompts are listed in `<state>/trivial` and skipped.

`<state>/captured` has one line per capture: `<session id>`, the human-prompt count the capture covered up to (the watermark), and the part number, separated by tabs. The next capture of that session starts after the watermark. A line with a bare id, written before version 0.5.0, is read as captured up to the transcript's current end: the first time it is seen, a watermark line for the current count is added and nothing is captured, so an upgrade never re-captures old sessions. Work done in a resumed session between its old capture and the upgrade is not captured; run that session's capture by hand if it matters. To capture a whole session again, delete its lines from `captured` and run backfill.

## Other harnesses

Only Claude Code is implemented. Codex, Copilot and Gemini CLI findings and the adapter contract are in `${CLAUDE_SKILL_DIR}/reference/harnesses.md`.
