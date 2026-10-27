# ADLC documentation in the plugin: design

Date: 2026-10-27. Owner: EastwoodNo1. Source template: `generic_adlc_documentation_template` (a `CLAUDE.md` policy, an `adlc-documenter` agent, seven `docs/adlc/` files).

## Intent

The owner wants a portable way of working that does not live in one project. Any project that uses this plugin gets the same lifecycle documentation: what was built, how, why, what failed and what was learned, including the human and AI contributions. The first user is SuperSnake. At the end of SuperSnake the owner wants to build a full presentation of how the project was run (process, ways of working, reasoning, pros and cons, lessons learned) from these documents, without going back to old sessions.

The owner must never have to think about it. Capture is automatic, per session.

## Goals

1. A new skill, `android-sdlc:adlc-docs`, that adopts ADLC documentation in a project: copies the `docs/adlc/` templates, adds the policy to the project's agent instruction file, and explains the flow.
2. A plugin agent, `android-sdlc:adlc-documenter`, carrying the template's procedure plus two modes: **capture** (one session to one staged note) and **fold-in** (staged notes into `docs/adlc/` inside a PR).
3. Automatic capture: a plugin `SessionEnd` hook starts capture for the session that just ended, detached, on Sonnet, with no action from the owner.
4. A privacy filter, because SuperSnake and this plugin are public repos.
5. Durable "always do X because Y" lessons are also saved as Claude memories during fold-in.
6. A harness-neutral core so Codex and Copilot adapters can be added later without redesign. Only the Claude Code adapter is built now.
7. A backfill command so existing sessions are captured before Claude Code's 30-day transcript cleanup deletes them.

## Non-goals

- Building the final presentation. The docs only need to make it possible (`PRESENTATION_SOURCE_GUIDE.md`).
- Codex, Copilot or Gemini adapters (designed for, not built).
- Renaming the plugin away from "android".
- Changing SuperSnake's own decisions or spec.

## Anti-goals (failure even if it technically works)

- Private data in a public repo: email addresses, people's names, employer or internal system names, home paths, tokens.
- Invented history. Every statement carries Observed, Reconstructed, Unknown or Prospective.
- The owner has to remember a step, or the hook slows down or breaks quitting Claude Code.
- A capture run triggers another capture run (hook loop).
- Claude's memory index bloats with per-session history.
- Separate documentation PRs the owner has to manage.

## Constraints

- Plugin repo rules (`CONTRIBUTING.md`): issue first, worktree branch, Conventional Commits with `Why:`/`What:`, no comments in `*.sh`, `*.yml`, `*.yaml`, `*.toml` and similar (Markdown and JSON are allowed to have none either; JSON cannot), PR with `Closes #N` and `## Evidence`, squash merge on green `verify`.
- `verify-templates.sh` only covers `skills/git-hooks/templates` and `skills/android-ci/templates`. The ADLC templates originate in this plugin, not SuperSnake, so they live outside those folders and are not drift-checked.
- Subagents and headless runs use Sonnet (owner's rule).
- Minimal dependencies: `bash`, `git`, `jq` (present on macOS at `/usr/bin/jq` and on the Ubuntu runner) and the harness CLI. No Python, no Node.
- Claude Code facts this rests on (code.claude.com/docs, checked 2026-10-27, Claude Code 2.1.304):
  - Plugin agents live in `agents/*.md`, invoked as `android-sdlc:adlc-documenter`. Plugin agents ignore `permissionMode` and `hooks`.
  - Plugin hooks live in `hooks/hooks.json` with a top-level `"hooks"` wrapper. `${CLAUDE_PLUGIN_ROOT}` is substituted and exported. They fire in every session that loads the plugin.
  - `SessionEnd` stdin: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `reason`. It cannot block. The budget is 1.5 s and plugin hook timeouts do not raise it. Work that outlives it must be a fully detached process.
  - Headless: `claude -p --agent <plugin:agent> --model sonnet --permission-mode dontAsk --allowedTools ... --settings '{"disableAllHooks":true}' --no-session-persistence`.
  - Transcripts: `~/.claude/projects/<slug>/<session>.jsonl`, deleted after `cleanupPeriodDays` (default 30). Subagent transcripts: `<session>/subagents/agent-*.jsonl`.

## Design

### Layout in the plugin

```
agents/adlc-documenter.md                  Claude adapter: the agent (canonical procedure)
hooks/hooks.json                           Claude adapter: SessionEnd -> session-end.sh claude
skills/adlc-docs/SKILL.md                  adopt, fold-in, backfill, troubleshooting
skills/adlc-docs/templates/docs/adlc/*.md  7 template docs + sessions/README.md
skills/adlc-docs/reference/policy.md       policy block to add to CLAUDE.md / AGENTS.md
skills/adlc-docs/reference/privacy.md      the privacy filter rules
skills/adlc-docs/reference/harnesses.md    adapter contract + researched facts for Codex, Copilot, Gemini
skills/adlc-docs/scripts/session-end.sh    harness-neutral SessionEnd entry
skills/adlc-docs/scripts/session-start.sh  harness-neutral SessionStart entry: catch-up sweep + reminder
skills/adlc-docs/scripts/capture.sh        detached worker: digest + headless documenter
skills/adlc-docs/scripts/digest.sh         transcript JSONL -> compact Markdown digest
skills/adlc-docs/scripts/scan.sh           read-only privacy scan of a directory, run before the fold-in commit
skills/adlc-docs/scripts/backfill.sh       run capture over existing transcripts
skills/adlc-docs/tests/*                   shell tests with fixture transcripts
```

### Harness-neutral core and adapters

The core does not know which agent tool produced a session. It works on:

- **A digest**: a Markdown file of the session's human prompts and the AI's visible replies, with tool output dropped. Tool calls are reduced to one line each (tool name plus a short target, such as a file path or the first words of a command).
- **A staged note**: one Markdown file per session in the project's staging folder.
- **The procedure**: plain Markdown in `agents/adlc-documenter.md`. Other harnesses get the same body in their own wrapper format.

An adapter supplies three things, written down in `reference/harnesses.md`:

1. A session-end trigger that calls `session-end.sh <harness>` with the session's JSON on stdin.
2. A digest reader for its transcript format (`digest.sh --format <harness>`).
3. A headless runner command for capture (`capture.sh` switches on the harness name).

Only `claude` is implemented. For `codex` and `copilot`, `session-end.sh` exits 0 with a stderr note "adapter not implemented". The researched facts go into `harnesses.md` so the next builder starts from them:

- Codex: `SessionEnd` with `transcript_path`, `.codex/hooks.json`, `codex exec`, AGENTS.md, `.agents/skills`, rollouts at `~/.codex/sessions/...jsonl`.
- Copilot: `sessionEnd` without a transcript path (use `agentStop`, or derive it from `sessionId`), `.github/hooks/*.json`, `copilot -p`, AGENTS.md and `.github/copilot-instructions.md`.
- Gemini: `SessionEnd` with `transcript_path`, best effort.

The policy text is the same for every harness. It goes into `CLAUDE.md` for Claude Code and `AGENTS.md` for the others.

### Opt-in and off switch

The hooks are active wherever the plugin is enabled. They do nothing unless the repo has opted in, in one of two ways:

- The file `<git-common-dir>/adlc/enabled` exists. The adopt step writes it, so sessions in any worktree or the main checkout count from the moment of adoption, before the adoption PR merges.
- `docs/adlc/ADLC_PROCESS.md` exists in the git top-level of `cwd`. This covers a fresh clone of an adopted repo. The hook then writes `enabled` itself.

The file `<git-common-dir>/adlc/disabled` turns everything off for that repo. `ADLC_DISABLE=1` does the same for one session.

### Staging folder

`$(git -C "$cwd" rev-parse --git-common-dir)/adlc/`, which is inside `.git`:

- Never committed, so it is safe for unfiltered intermediate files.
- Shared by every worktree of the repo, and one per repo.

Contents:

- `staged/<YYYY-MM-DD>-<session-id-8>.md`: finished, privacy-filtered notes waiting for fold-in.
- `failed`: one session id per line for every failed capture. Backfill and `SessionStart` skip an id that has two lines.
- `trivial`: session ids with fewer than 3 human prompts, recorded by backfill and skipped afterwards.
- `log/redactions.log`: one line per redaction class hit (time, session id, class), never the matched text.
- `log/<session-id>.log`: capture output, kept for troubleshooting, the last 50 kept.
- `captured`: one session id per line. Makes capture idempotent (backfill and re-runs skip ids already captured).
- `lock`: a directory used as a mutex (`mkdir`) so two captures don't run at once. Stale after 30 minutes.

### Two triggers: SessionEnd, with SessionStart as the safety net

`SessionEnd` is best effort: it has 1.5 s, and a detached child might not survive every way Claude Code exits. So `hooks/hooks.json` also registers `SessionStart`, which runs `session-start.sh claude`. While the new session is alive it:

1. Starts a detached sweep (`backfill.sh --limit 3`) that captures any finished, uncaptured sessions of this repo, skipping the current session id.
2. Prints a one-line context note when `staged/` has notes, such as "ADLC: 2 session notes are waiting for fold-in at the next PR". `SessionStart` stdout goes into the agent's context, which reminds the main agent of the fold-in policy without the owner doing anything.

A session missed at its end is therefore captured at the start of the next session in that repo.

The first implementation task is a spike that proves, on this machine (Claude Code 2.1.304, macOS), that:

- a detached child started from `SessionEnd` survives quitting Claude Code
- `claude -p --agent android-sdlc:adlc-documenter` resolves the plugin agent with `--settings '{"disableAllHooks":true}'`

If the agent does not resolve that way, the runner passes the agent body through `--agents` JSON or `--append-system-prompt` instead. Capture runs with the repo top-level as its working directory.

### Capture flow (automatic)

1. Claude Code fires `SessionEnd`. `hooks/hooks.json` runs `"${CLAUDE_PLUGIN_ROOT}/skills/adlc-docs/scripts/session-end.sh" claude`.
2. `session-end.sh` reads stdin with `jq` and exits 0 straight away when any of these hold:
   - `ADLC_CAPTURE=1` is set (loop guard: capture runs set it)
   - the repo has not opted in
   - the transcript is missing
   - the session id is already in `captured`
   - the session is trivial (fewer than 3 human prompts)

   Otherwise it starts `capture.sh` fully detached and returns. The detach uses `nohup` with stdin from `/dev/null`, output to the log, `&`, then `disown`; macOS has no `setsid`. It must return well inside 1.5 s, and does no heavy work itself.
3. `capture.sh` takes the lock, then:
   - creates a private work directory with `mktemp -d` outside `.git` (Claude Code refuses writes inside `.git`) and runs `digest.sh` on the main transcript plus its subagent transcripts into `<workdir>/digest.md`. The digest is regenerated on every run and is not kept in the state folder
   - runs `claude -p` with:
     - env `ADLC_CAPTURE=1`
     - `--agent android-sdlc:adlc-documenter --model sonnet`
     - `--settings '{"disableAllHooks":true}'`
     - `--no-session-persistence`
     - `--permission-mode dontAsk`
     - `--allowedTools` limited to path-scoped `Read`, `Grep` and `Glob` rules for the work directory and the repository top level, and `Edit(//<workdir>/**)`. There is no Bash rule and no unscoped rule. `Write(path)` rules are ignored by Claude Code, so the agent writes with `Edit`
     - a prompt naming capture mode, the digest path, the raw note path in the work directory and the repo path
   - redacts the raw note mechanically, then moves it to `staged/`
   - on success, appends the id to `captured`, deletes the work directory and releases the lock
   - on failure, appends the id to `failed` and logs. `backfill.sh`, also run by `SessionStart`, retries it until the id has two lines in `failed`; deleting those lines resets it.
4. The documenter, in capture mode, writes one staged note (format below), applying `privacy.md`. It writes nothing else.

### Staged note format

Front matter: `session`, `date`, `harness`, `branch(es)`, `evidence_status` summary. Sections:

- Goal
- What happened (short chronology)
- Key prompts:
  - verbatim only when they pass the filter, else `Reconstructed prompt intent - not verbatim`
  - with refinements in the form `Initial -> Output -> Problem -> Refinement -> Result`
- Decisions (with alternatives and observable rationale)
- Failures and rework
- Human contribution
- AI contribution
- Concepts and principles learned
- Durable lessons (candidates for Claude memory)
- Presentation candidates (headline, key message, example)
- Evidence (commits, PRs, files)
- Gaps and uncertainty

IDs: staged notes carry no stable IDs. Fold-in allocates `PROMPT-`, `DEC-`, `REQ-` and similar IDs, continuing from the highest ID already in each log.

### Fold-in flow (automatic through policy)

The policy in the project's `CLAUDE.md` says: before opening or updating a PR, if `<git-common-dir>/adlc/staged/` has notes, invoke `android-sdlc:adlc-documenter` in fold-in mode in the PR's worktree. The documenter:

1. Copies each staged note to `docs/adlc/sessions/<date>-<topic>.md`, the committed session record. The staged original stays in place.
2. Updates the logs, appending rather than rewriting:
   - `PROJECT_EVOLUTION_TIMELINE.md`
   - `PROMPT_AND_INTERACTION_LOG.md`
   - `DECISION_LOG.md`
   - `REQUIREMENTS_TRACEABILITY.md`
   - `SOURCE_AND_UNCERTAINTY_REGISTER.md`
   - `PRESENTATION_SOURCE_GUIDE.md`
3. Revises `ADLC_PROCESS.md`, including its "Documentation status" with the last folded session.
4. Re-applies the privacy filter to everything it wrote. Before the fold-in commit the main agent runs `scan.sh docs/adlc "<state>"`, which exits 1 on any hit, and fixes the hits first.
5. Returns the list of durable lessons. The main agent saves those as Claude memories (type `feedback` or `project`), after checking for duplicates. Only the main session has the memory system, so the documenter does not write memory itself.
6. The main agent, not the documenter, deletes the folded notes from `staged/`, only after committing the docs.

The documentation commit is `docs(adlc): ...` in the same PR. The policy text and the `SessionStart` reminder are the enforcement. There is no CI check in this version.

The last sessions of a project are captured after its last PR. The skill therefore has a "fold in now" step for the end of a project, or before building the presentation. It opens one `docs(adlc)` PR. That is the only documentation-only PR, and the owner asks for it only when they want the material. Trivial PRs (Dependabot, version bumps) still carry pending notes, because it is the next PR. A Dependabot PR is created by a bot without an agent, so notes simply wait for the next agent-made PR.

### Privacy filter (`reference/privacy.md`)

Applied in capture and again in fold-in.

- Remove: email addresses, people's names other than the GitHub owner handle, employer and internal tool, plugin or connector names unrelated to the project, absolute home paths (rewrite to `~/` or repo-relative), tokens, keys and anything secret-shaped, Jira keys and internal URLs.
- Quote prompts verbatim only when they are about the project and contain nothing above. Otherwise paraphrase as `Reconstructed prompt intent - not verbatim`.
- Never quote tool output that could contain environment data.
- `capture.sh` redacts the raw note mechanically before it is staged: an email regex, `/Users/` and `/home/` paths, GitHub, API, AWS, Slack, Bearer and JWT tokens, PEM private key blocks, Jira-style keys (except the documentation ID prefixes `REQ`, `AC`, `DEC`, `DES`, `IMP`, `TEST`, `PROMPT` and `CYCLE`), and a deny-list file at `<git-common-dir>/adlc/deny-list` (one term per line, owner-maintained, never committed). A hit redacts the match to `[redacted]` and appends the hit class to `log/redactions.log`.
- `scan.sh <dir> [<state-dir>]` runs the same patterns read-only and prints `file:line: class`, never the matched text. It exits 1 on any hit. It is the second layer, run on `docs/adlc` before the fold-in commit.

### Backfill

`backfill.sh [--harness claude] [--project-dir <repo>]` finds the repo's transcripts under `~/.claude/projects/<slug>/`, where the slug is the repo path with every non-alphanumeric character turned into `-`. It includes worktree slugs (`<slug>-*` folders whose session `cwd` sits inside the repo or its worktrees). For each session not yet in `captured`, oldest first, it runs `capture.sh` in the foreground, one at a time. It skips ids with two lines in `failed` and ids in `trivial`, and records new trivial ids. `--limit N` caps the count: no limit when run by hand, 3 when run from `SessionStart`. It skips sessions whose transcript changed in the last 10 minutes, because those may still be live. Reconstruction of everything before the first session (git, PRs, plans, ADRs) is a fold-in task: on the first fold-in with an unpopulated `ADLC_PROCESS.md`, the documenter runs the template's historical reconstruction.

The skill also tells adopters to raise `cleanupPeriodDays` (suggested 365, in user settings) so raw evidence survives until the project ends. It tells them, and does not change settings itself.

### Adopting in a project (skill steps)

1. Copy `templates/docs/adlc/` into the project.
2. Add `reference/policy.md` to `CLAUDE.md` (and `AGENTS.md` when present).
3. Suggest the `cleanupPeriodDays` change.
4. Run `backfill.sh`.
5. Commit through the project's normal PR flow.

### Testing

`skills/adlc-docs/tests/run.sh`, run in CI next to shellcheck:

- `digest.sh` against a small fixture Claude transcript: the expected Markdown, tool output dropped, subagents included.
- `session-end.sh` guards:
  - exits 0 fast and starts nothing for: not opted in, `ADLC_CAPTURE=1`, already captured, trivial session
  - starts capture when opted in, tested with a stub `claude` on `PATH` that writes a note
  - returns in under 1 s
- `capture.sh` with the stub `claude`:
  - writes the note, updates `captured`, applies the mechanical redaction (the fixture contains an email and a `/Users/` path), leaves no work directory behind
  - on stub failure, appends the id to `failed`
- `backfill.sh` skips captured ids.
- `claude plugin validate .` passes, run locally and recorded as evidence.

Real-world check, recorded as PR evidence:

- one real `SessionEnd` capture in SuperSnake after adoption
- a backfill of its existing sessions
- one fold-in PR

### Release and adoption

1. Plugin PR (this design): issue, `feat/adlc-docs`, the plugin changes, a README row for the new skill and the agent, and `plugin.json` version `0.2.0`.
2. After merge, tag `v0.2.0` the same way as `v0.1.1`.
3. SuperSnake PR, separate:
   - bump the plugin ref to `v0.2.0` in `.claude/settings.json` and `CLAUDE.md`
   - adopt through the skill
   - backfill
   - the first fold-in

## Left to the builder

- Exact `jq` filters for the digest, and the digest size cap. Suggested: truncate each assistant message to about 1,500 characters and the whole digest to about 150 KB, keeping all human prompts.
- The agent file `agents/adlc-documenter.md` is the canonical procedure. Future adapters copy its body into their own wrapper. The body uses neutral wording ("the AI assistant", not "Claude Code").
- Template edits:
  - `ADLC_PROCESS.md` section 2 gains `Last folded session:`.
  - The new `sessions/README.md` explains the session records.
  - Otherwise the source template's wording stays.
- CI: add the new scripts to the shellcheck list, and run `skills/adlc-docs/tests/run.sh` with the stub `claude` on `PATH`.
- Exact wording of the agent body. It must keep everything in the template's procedure and add the two modes, the staged note format and privacy references.
- Test harness style (plain bash with assertions; no bats dependency).

## Calls made by Claude, not the owner

- Staging inside `.git` (`<git-common-dir>/adlc/`), with fold-in at the next PR.
- Opt-in by the presence of `docs/adlc/ADLC_PROCESS.md`.
- Loop guard through `ADLC_CAPTURE=1` plus `disableAllHooks`.
- The "trivial session" threshold: fewer than 3 human prompts.
- The memory write is done by the main agent at fold-in, not by the headless capture.
- The mechanical redaction pass and the private deny-list file.
- Version `0.2.0`.
- The `SessionStart` safety net and reminder, the `enabled` and `disabled` marker files, `ADLC_DISABLE`, and backfill `--limit`.
- Staged notes carry no IDs. Fold-in allocates them.
- One on-demand "fold in now" PR at the end of a project, as the only exception to "no separate documentation PRs".
- Cost: one Sonnet run per non-trivial session, on the owner's normal Claude Code account. There is no cap besides the off switch.

## Changes during implementation

- Raw note in a private `mktemp -d` work directory outside `.git`, then redacted and moved to `staged/`. Reason: Claude Code refuses writes inside `.git`, even with a matching allow rule.
- `Edit(//<workdir>/**)` instead of `Write(<path>)`. Reason: Claude Code ignores `Write(path)` allow rules.
- Fold-in copies the staged notes and the main agent deletes them after the commit. Reason: the documenter must not delete anything, and a failed commit must not lose notes.
- Backfill slug: every non-alphanumeric character becomes `-`, not only `/`. Reason: that is how Claude Code names the folders, for example for dots in a repo name.
- Retries happen through backfill and `SessionStart`, bounded by two lines in `failed`, not through a later `SessionEnd`. Reason: no endless retry loop, and an owner-visible reset.
- Digests are no longer kept in the state folder. They live in the work directory and are regenerated on every run. Reason: the agent then reads only the work directory and the repository.
- Capture permissions are path-scoped, with no Bash rule. Reason: unrestricted `Read`, `Grep`, `Glob` and `git log`/`git show` (which accept `--output`) are wider than capture needs.
- New `scan.sh`, `failed` and `trivial` files and `log/redactions.log`. Reasons: a second privacy check before the public commit, bounded retries, skipping trivial sessions without parsing them again, and making "a hit is logged" true.
- More redaction classes: GitHub, API, AWS, Slack, Bearer and JWT tokens, PEM private keys and Jira-style keys. Reason: the first filter caught only emails, home paths and the deny-list.
