#!/usr/bin/env bash
set -u

harness=claude
project_dir=$PWD
limit=
exclude=

while [ $# -gt 0 ]; do
  case "$1" in
    --harness)
      harness=${2:-}
      shift 2 || break
      ;;
    --project-dir)
      project_dir=${2:-}
      shift 2 || break
      ;;
    --limit)
      limit=${2:-}
      shift 2 || break
      ;;
    --exclude)
      exclude=${2:-}
      shift 2 || break
      ;;
    *)
      printf 'adlc-docs backfill: unknown argument %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

if [ "$harness" != "claude" ]; then
  printf 'adlc-docs backfill: adapter not implemented for harness %s\n' "$harness" >&2
  exit 0
fi
case "$limit" in
  '' | *[!0-9]*) [ -z "$limit" ] || exit 1 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

adlc_opted_in "$project_dir" || exit 0
adlc_disabled "$project_dir" && exit 0
state=$(adlc_state_dir "$project_dir") || exit 0

main=$(git -C "$project_dir" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
[ -n "$main" ] || exit 0

slug=$(printf '%s' "$main" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
projects=${ADLC_PROJECTS_DIR:-$HOME/.claude/projects}
capture_cmd=${ADLC_CAPTURE_CMD:-$here/capture.sh}

list="$state/work.backfill.$$"
mkdir -p "$state" || exit 0
: >"$list" || exit 0
trap 'rm -f "$list"' EXIT

skipped=0
for dir in "$projects"/"$slug"*/; do
  [ -d "$dir" ] || continue
  for file in "$dir"*.jsonl; do
    [ -f "$file" ] || continue
    id=$(basename "$file" .jsonl)
    case "$id" in
      '' | *[!A-Za-z0-9-]*)
        skipped=$((skipped + 1))
        continue
        ;;
    esac
    if [ "$id" = "$exclude" ] ||
      { [ -f "$state/captured" ] && grep -qxF -- "$id" "$state/captured"; } ||
      [ -n "$(find "$file" -maxdepth 0 -mmin -10 2>/dev/null)" ]; then
      skipped=$((skipped + 1))
      continue
    fi
    meta=$(head -n 50 "$file" | jq -Rr 'fromjson? | objects | [(.cwd? // "" | strings), (.timestamp? // "" | strings)] | @tsv' 2>/dev/null)
    scwd=$(printf '%s\n' "$meta" | awk -F'\t' '$1 != "" {print $1; exit}')
    case "$scwd" in
      "$main" | "$main"/* | "$main"-*) ;;
      *) continue ;;
    esac
    count=$(adlc_human_prompt_count "$harness" "$file" 2>/dev/null) || count=0
    if ! [ "${count:-0}" -ge 3 ] 2>/dev/null; then
      skipped=$((skipped + 1))
      continue
    fi
    start=$(printf '%s\n' "$meta" | awk -F'\t' '$2 != "" {print $2; exit}')
    printf '%s\t%s\n' "${start:-9999}" "$file" >>"$list"
  done
done

captured=0
while IFS="$(printf '\t')" read -r _ file; do
  [ -n "$file" ] || continue
  if [ -n "$limit" ] && [ "$captured" -ge "$limit" ]; then
    break
  fi
  id=$(basename "$file" .jsonl)
  ADLC_CAPTURE=1 "$capture_cmd" "$harness" "$id" "$file" "$main" </dev/null || true
  if [ -f "$state/captured" ] && grep -qxF -- "$id" "$state/captured"; then
    captured=$((captured + 1))
  else
    skipped=$((skipped + 1))
  fi
done <<EOF2
$(LC_ALL=C sort "$list")
EOF2

printf 'captured %s, skipped %s\n' "$captured" "$skipped"
exit 0
