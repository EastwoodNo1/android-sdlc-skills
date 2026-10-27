#!/usr/bin/env bash
set -u

dir=${1:-}
state=${2:-}

if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  printf 'usage: scan.sh <dir> [<state-dir>]\n' >&2
  exit 2
fi

here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

found=0
while IFS= read -r file; do
  hits=$(adlc_scan_file "$file" "$state" | LC_ALL=C sort -t: -k1,1n -k2,2 -u)
  [ -n "$hits" ] || continue
  found=1
  printf '%s\n' "$hits" | while IFS=: read -r line class; do
    printf '%s:%s: %s\n' "$file" "$line" "$class"
  done
done <<EOF2
$(find "$dir" -type f | LC_ALL=C sort)
EOF2

[ "$found" -eq 0 ]
