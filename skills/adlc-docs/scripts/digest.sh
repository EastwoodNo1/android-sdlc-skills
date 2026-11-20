#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

ADLC_DIGEST_MESSAGE_CAP=1500
ADLC_DIGEST_TOTAL_CAP=150000

usage() {
  printf 'usage: digest.sh --format claude [--prompts <after>:<through>] <transcript.jsonl> <out.md>\n' >&2
  exit 2
}

if [ "$#" -lt 4 ] || [ "$1" != "--format" ]; then
  usage
fi
format=$2
shift 2
after=0
through=-1
ranged=0
if [ "${1:-}" = "--prompts" ]; then
  [ "$#" -ge 2 ] || usage
  case "$2" in
    [0-9]*:[0-9]*) ;;
    *) usage ;;
  esac
  after=${2%%:*}
  through=${2#*:}
  case "$after$through" in
    *[!0-9]*) usage ;;
  esac
  ranged=1
  shift 2
fi
[ "$#" -eq 2 ] || usage
transcript=$1
out=$2
[ "$format" = "claude" ] || usage
[ -f "$transcript" ] || {
  printf 'digest.sh: no such transcript: %s\n' "$transcript" >&2
  exit 1
}

DIGEST_PROGRAM="$ADLC_JQ_DEFS"'
def tool_line:
  (.input // {}) as $i
  | ([
      $i.file_path,
      $i.path,
      $i.pattern,
      ($i.command | strings | gsub("\\s+"; " ") | .[0:80]),
      $i.description
    ] | map(select(type == "string" and length > 0)) | first // "") as $target
  | if $target == "" then "- tool: " + .name else "- tool: " + .name + " " + $target end;
def ai_items:
  select(.type == "assistant")
  | (.message.content // [])
  | (if type == "array" then . else [] end)
  | .[]
  | if .type == "text" then
      (.text // "" | trim)
      | select(length > 0)
      | (if length > $mcap then .[0:$mcap] + "…[truncated]" else . end)
      | {t: "a", k: "x", s: .}
    elif .type == "tool_use" then {t: "a", k: "t", s: tool_line}
    else empty end;
[inputs | fromjson? | select(type == "object")] as $all
| ($all | length) as $n
| (if $kind == "Session" then
    [$all | to_entries[] | select([.value | human_text] | length > 0) | .key] as $hidx
    | [ (if $after == 0 then 0 elif ($hidx | length) > $after then $hidx[$after] else $n end),
        (if $through < 0 or ($hidx | length) <= $through then $n else $hidx[$through] end) ]
  else [0, $n] end) as [$lo, $hi]
| (if $kind == "Session" or $ranged == "0" then $all[$lo:$hi]
   elif $since == "" then []
   else [$all[] | select((.timestamp? | strings) as $t | $t >= $since and ($until == "" or $t < $until))]
   end) as $ev
| select($kind == "Session" or $ranged == "0" or ($ev | length) > 0)
| ([$ev[] | .timestamp? | strings]) as $ts
| (([$all[] | .sessionId? | strings] | first) // $id) as $sid
| (if $kind == "Session" then $sid else $id end) as $label
| {
    since: (($ts | first) // ""),
    until: (([$all[$hi:][] | .timestamp? | strings] | first) // ""),
    head: ("# " + $kind + " " + $label + "\n\nStart: " + (($ts | first) // "unknown") + "\nEnd: " + (($ts | last) // "unknown")),
    turns: (
      reduce (
        $ev[]
        | (human_text | {t: "h", k: "h", s: .}), ai_items
      ) as $it ([];
        if $it.t == "h" then . + [{t: "h", lines: [$it]}]
        elif (length > 0 and .[-1].t == "a") then .[-1].lines += [$it]
        else . + [{t: "a", lines: [$it]}] end)
    )
  }'

COMBINE_PROGRAM='
def render_turn: (if .t == "h" then "## Human\n" else "## AI\n" end) + (.lines | map(.s) | join("\n"));
def render_doc: ([.head] + (.turns | map(render_turn))) | join("\n\n");
def size: (map(render_doc) | join("\n\n") | utf8bytelength) + 1;
. as $docs
| [ range(0; $docs | length) as $d
    | range(0; $docs[$d].turns | length) as $t
    | range(0; $docs[$d].turns[$t].lines | length) as $l
    | select($docs[$d].turns[$t].lines[$l].k == "x")
    | ["turns", $t, "lines", $l] | [$d] + .
  ] as $paths
| ($paths | length) as $n
| ([range(0; $n)] | sort_by((. - ($n / 2)) | fabs)) as $order
| "…[omitted to fit size cap]" as $r
| ($r | utf8bytelength) as $rb
| reduce $order[] as $i ({docs: $docs, total: ($docs | size)};
    $paths[$i] as $p
    | (.docs | getpath($p + ["s"])) as $old
    | if .total > $cap and $rb < ($old | utf8bytelength) then
        .total -= (($old | utf8bytelength) - $rb)
        | .docs |= setpath($p + ["s"]; $r)
      else . end)
| .docs | map(render_doc) | join("\n\n")'

tmp=$(mktemp "${TMPDIR:-/tmp}/adlc-digest.XXXXXX")
trap 'rm -f "$tmp"' EXIT

base=$(basename "$transcript" .jsonl)
run_digest() {
  jq -Rn --arg kind "$1" --arg id "$2" --argjson after "$after" --argjson through "$through" \
    --arg ranged "$ranged" --arg since "${since:-}" --arg until "${until:-}" \
    --argjson mcap "$ADLC_DIGEST_MESSAGE_CAP" "$DIGEST_PROGRAM"
}

run_digest Session "$base" <"$transcript" >"$tmp"
since=$(jq -r '.since' "$tmp")
until=$(jq -r '.until' "$tmp")

subdir="$(dirname "$transcript")/$base/subagents"
for sub in "$subdir"/agent-*.jsonl; do
  [ -f "$sub" ] || continue
  agent=$(basename "$sub" .jsonl)
  agent=${agent#agent-}
  run_digest Subagent "$agent" <"$sub" >>"$tmp"
done

jq -rs --argjson cap "$ADLC_DIGEST_TOTAL_CAP" "$COMBINE_PROGRAM" <"$tmp" >"$out"
