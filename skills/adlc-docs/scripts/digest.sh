#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

ADLC_DIGEST_MESSAGE_CAP=1500
ADLC_DIGEST_TOTAL_CAP=150000

usage() {
  printf 'usage: digest.sh --format claude <transcript.jsonl> <out.md>\n' >&2
  exit 2
}

if [ "$#" -ne 4 ] || [ "$1" != "--format" ]; then
  usage
fi
format=$2
transcript=$3
out=$4
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
[inputs | fromjson? | select(type == "object")] as $ev
| ([$ev[] | .timestamp? | strings]) as $ts
| (([$ev[] | .sessionId? | strings] | first) // $id) as $sid
| (if $kind == "Session" then $sid else $id end) as $label
| {
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
jq -Rn --arg kind Session --arg id "$base" --argjson mcap "$ADLC_DIGEST_MESSAGE_CAP" "$DIGEST_PROGRAM" <"$transcript" >"$tmp"

subdir="$(dirname "$transcript")/$base/subagents"
for sub in "$subdir"/agent-*.jsonl; do
  [ -f "$sub" ] || continue
  agent=$(basename "$sub" .jsonl)
  agent=${agent#agent-}
  jq -Rn --arg kind Subagent --arg id "$agent" --argjson mcap "$ADLC_DIGEST_MESSAGE_CAP" "$DIGEST_PROGRAM" <"$sub" >>"$tmp"
done

jq -rs --argjson cap "$ADLC_DIGEST_TOTAL_CAP" "$COMBINE_PROGRAM" <"$tmp" >"$out"
