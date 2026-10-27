# ADLC/SDLC documentation policy

Add this block to the project's agent instruction file: `CLAUDE.md` for Claude Code, `AGENTS.md` for Codex and Copilot, `GEMINI.md` for Gemini CLI. The text is the same for every harness.

---

## ADLC/SDLC documentation

### Purpose

Maintain a living, evidence-based record of the project's actual Software Development Lifecycle (SDLC) and AI-assisted/agentic development lifecycle (ADLC).

The documentation covers historical and ongoing work and stays understandable without undocumented conversation context. It is a self-contained source for later educational material and presentations.

### Documentation agent

Delegate lifecycle documentation to the plugin agent:

`android-sdlc:adlc-documenter`

### Capture is automatic

A session-end hook captures each non-trivial session into a staged note, without any action from the person or the agent. Staged notes are filtered for private data and wait in `$(git rev-parse --path-format=absolute --git-common-dir)/adlc/staged/`. Do not write them by hand.

### Fold-in before a pull request

Before opening or updating a pull request, check `$(git rev-parse --path-format=absolute --git-common-dir)/adlc/staged/`. If it has notes:

1. Run `android-sdlc:adlc-documenter` in fold-in mode in the PR's worktree. The prompt starts with `MODE: fold-in`, then `STAGED: <dir>` and `REPO: <worktree path>`.
2. Run `scan.sh docs/adlc "$(git rev-parse --path-format=absolute --git-common-dir)/adlc"`. It prints `file:line: class` for each privacy hit and exits 1. Fix every hit before committing.
3. Commit the result as `docs(adlc): fold in session notes`.
4. Save the returned durable lessons as memories (type `feedback` or `project`), after checking for duplicates. Only the main session has the memory system, so the documenter does not write memory.
5. Delete the folded files from `staged/`, only after the commit.

The documenter copies the staged notes and never deletes them. Pending notes from a trivial PR carry to the next one. At the end of a project, or before building a presentation, run one fold-in now and open a single `docs(adlc)` pull request.

### Historical reconstruction

On the first fold-in, if `docs/adlc/ADLC_PROCESS.md` is unpopulated, the documenter reconstructs history from git, pull requests, plans, specs and ADRs. It determines first what evidence is accessible and never fabricates missing history. A completed reconstruction is not repeated unless gaps remain or new evidence appears.

### Documentation location

Lifecycle documentation lives under `docs/adlc/`. Reuse equivalent existing documentation instead of creating duplicates.

- `ADLC_PROCESS.md` (the human-readable entry point)
- `PROJECT_EVOLUTION_TIMELINE.md`
- `PROMPT_AND_INTERACTION_LOG.md`
- `DECISION_LOG.md`
- `REQUIREMENTS_TRACEABILITY.md`
- `SOURCE_AND_UNCERTAINTY_REGISTER.md`
- `PRESENTATION_SOURCE_GUIDE.md`
- `sessions/` (one record per folded session)

### Integrity

Never fabricate historical information. Classify information as:

- **Observed**: directly supported by evidence
- **Reconstructed**: reasonably inferred from evidence
- **Unknown**: cannot be determined reliably
- **Prospective**: introduced from the current point onward

Preserve failures, iterations, rejected approaches, reversed decisions and feedback loops. Document observable rationale, not hidden reasoning. Never delete superseded decisions.

### Privacy

The repository is public. No email addresses, people's names other than the owner handle, employer or internal system names, absolute home paths, tokens or Jira keys in `docs/adlc/`. The documenter applies the privacy filter, and `scan.sh` checks the result before the fold-in commit.

### Educational purpose

Keep the documentation self-contained enough to explain the actual SDLC/ADLC, requirement evolution, meaningful prompts and refinements, planning and design, implementation progression, testing and validation, decisions and trade-offs, failures and feedback loops, human contribution, AI contribution and lessons learned. A later presentation must be derivable from the documentation without the original sessions.

### Definition of Done

A meaningful development cycle is not complete until:

- staged session notes have been folded into `docs/adlc/` in the pull request
- durable lessons have been saved as memories
- `android-sdlc:adlc-documenter` has reported unresolved gaps, if any

### Off switch

Create `$(git rev-parse --path-format=absolute --git-common-dir)/adlc/disabled` to turn capture off for this repository. Set `ADLC_DISABLE=1` to turn it off for one session.
