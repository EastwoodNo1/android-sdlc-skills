# Privacy filter

These docs live in public repositories. The filter is applied twice: when a session is captured into a staged note, and again when fold-in writes into `docs/adlc/`.

## Remove or rewrite

- Email addresses.
- People's names, except the GitHub owner handle of the repository.
- Employer names and internal tool, plugin or connector names that are unrelated to the project.
- Absolute home paths. Rewrite to `~/` or a repo-relative path.
- Tokens, keys and anything secret-shaped.
- Jira keys and internal URLs.

## Prompts

- Quote a prompt verbatim only when it is about the project and contains nothing from the list above.
- Otherwise paraphrase it and label it `Reconstructed prompt intent - not verbatim`.

## Tool output

- Never quote tool output that could contain environment data.

## Mechanical scan

After capture, `capture.sh` scans the staged note with:

- an email regular expression
- `/Users/` and `/home/` paths
- the deny-list file at `<git-common-dir>/adlc/deny-list`: one term per line, maintained by the owner, never committed

A hit is replaced with `[redacted]` and logged. The scan is a safety net. The documenter must not rely on it.

## Staging is private, docs are public

Digests and staged notes live inside `.git` and are never committed. Only filtered text reaches `docs/adlc/`.
