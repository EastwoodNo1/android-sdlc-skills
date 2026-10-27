# Privacy filter

These docs live in public repositories. The filter is applied twice: when a session is captured into a staged note, and again when fold-in writes into `docs/adlc/`.

## Remove or rewrite

- Email addresses.
- People's names, except the GitHub owner handle of the repository.
- Employer names and internal tool, plugin or connector names that are unrelated to the project.
- Absolute home paths. Rewrite to `~/` or a repo-relative path.
- Tokens, keys and anything secret-shaped.
- Jira keys and internal URLs. Engineering identifiers such as `ADR-0006`, `SHA-256`, `UTF-8` and `REQ-001` are not issue keys and stay. Remove the internal issue keys you recognise; the mechanical filter only knows the keys the owner lists in `<git-common-dir>/adlc/issue-keys`.

## Prompts

- Quote a prompt verbatim only when it is about the project and contains nothing from the list above.
- Otherwise paraphrase it and label it `Reconstructed prompt intent - not verbatim`.

## Tool output

- Never quote tool output that could contain environment data.

## Mechanical redaction

`capture.sh` redacts the raw note before it is staged. The note is staged only after this succeeds. The patterns:

- email addresses
- `/Users/` and `/home/` paths
- GitHub tokens (`ghp_...`, `github_pat_...`), API keys (`sk-...`), AWS access key ids (`AKIA...`), Slack tokens (`xox[abprs]-...`), `Bearer` tokens and JWTs
- PEM private key blocks
- issue keys (`ABC-123`) for the project keys the owner lists in `<git-common-dir>/adlc/issue-keys`: one key per line such as `ABC`, matching `^[A-Z][A-Z0-9]{1,9}$`, other lines ignored, never committed. Without the file this class does nothing
- the deny-list file at `<git-common-dir>/adlc/deny-list`: one term per line, maintained by the owner, never committed

A hit is replaced with `[redacted]`, and one line per hit class (time, session id, class, never the matched text) is appended to `<git-common-dir>/adlc/log/redactions.log`. The redaction is a safety net. The documenter must not rely on it.

## Scan before fold-in

`scripts/scan.sh <dir> [<state-dir>]` runs the same patterns read-only over every file in `<dir>`, and the deny-list and issue keys when a state folder is given. It prints `file:line: class` for each hit, never the matched text, and exits 1 on any hit. The main agent runs it on `docs/adlc` before the fold-in commit and fixes every hit first.

## Staging is private, docs are public

Staged notes live inside `.git` and are never committed. Only filtered text reaches `docs/adlc/`.
