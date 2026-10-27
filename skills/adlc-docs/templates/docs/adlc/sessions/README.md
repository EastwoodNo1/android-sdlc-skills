# Session records

One file per working session, named `<YYYY-MM-DD>-<topic>.md`.

Each file is made by fold-in from a staged note that automatic capture wrote when the session ended. Fold-in copies the note here inside a pull request and allocates the stable IDs (`PROMPT-`, `DEC-`, `REQ-` and similar) in the logs. The session record itself carries no IDs.

The front matter and sections are the staged note format:

Front matter: `session`, `date`, `harness`, `branch(es)`, `evidence_status` (a summary).

Sections:

- Goal
- What happened (short chronology)
- Key prompts: verbatim only when they pass the privacy filter, otherwise `Reconstructed prompt intent - not verbatim`. Refinements use the form `Initial -> Output -> Problem -> Refinement -> Result`.
- Decisions (with alternatives and observable rationale)
- Failures and rework
- Human contribution
- AI contribution
- Concepts and principles learned
- Durable lessons (candidates for assistant memory)
- Presentation candidates (headline, key message, example)
- Evidence (commits, PRs, files)
- Gaps and uncertainty

Every statement is classified Observed, Reconstructed, Unknown or Prospective. Session records are history: do not rewrite them after fold-in, add corrections to the logs instead.
