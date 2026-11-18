#!/usr/bin/env bash
set -euo pipefail

apk="${1:?usage: release-smoke.sh <apk>}"
package="${PACKAGE:-}"
if [ -z "$package" ]; then
  aapt2="${AAPT2:-${ANDROID_HOME:?ANDROID_HOME is not set}/build-tools/37.0.0/aapt2}"
  package="$("$aapt2" dump badging "$apk" 2>/dev/null | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)" || package=""
  [ -n "$package" ] || { echo "smoke failed: cannot read the package name from $apk" >&2; exit 1; }
fi
timeout_seconds="${SMOKE_TIMEOUT_SECONDS:-120}"
settle_seconds="${SMOKE_SETTLE_SECONDS:-2}"
replay_after="${SMOKE_REPLAY_DUMPS:-5}"
out_dir="${OUT_DIR:-build/release-smoke}"

mkdir -p "$out_dir"
: > "$out_dir/ui-dump.xml"
: > "$out_dir/logcat.txt"

collect_evidence() {
  adb logcat -d > "$out_dir/logcat.txt" 2>/dev/null || true
  adb exec-out screencap -p > "$out_dir/game-over.png" 2>/dev/null || true
}
trap collect_evidence EXIT

dump_ui() {
  adb shell uiautomator dump /sdcard/ui-dump.xml > /dev/null 2>&1 || return 1
  adb shell cat /sdcard/ui-dump.xml > "$out_dir/ui-dump.xml.next" 2>/dev/null || return 1
  mv "$out_dir/ui-dump.xml.next" "$out_dir/ui-dump.xml"
}

node_bounds() {
  { grep -oE "$1" "$out_dir/ui-dump.xml" || true; } |
    head -n 1 |
    sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p'
}

play_bounds() {
  node_bounds '<node [^>]* text="Play"[^>]*>'
}

got_it_bounds() {
  node_bounds '<node [^>]* text="Got it"[^>]* package="(android|com\.android\.systemui)"[^>]*>'
}

resume_bounds() {
  node_bounds "<node [^>]* text=\"Resume\"[^>]* package=\"${package//./\\.}\"[^>]*>"
}

tap_centre() {
  local x1 y1 x2 y2
  read -r x1 y1 x2 y2 <<< "$1"
  adb shell input tap $(((x1 + x2) / 2)) $(((y1 + y2) / 2))
}

last_dump_texts() {
  { grep -o ' text="[^"]*"' "$out_dir/ui-dump.xml" || true; } |
    sed 's/^ text="//; s/"$//' |
    { grep -v '^$' || true; } |
    paste -sd'|' - |
    sed 's/|/, /g'
}

adb wait-for-device
adb uninstall "$package" > /dev/null 2>&1 || true
adb install "$apk" > /dev/null
adb logcat -c
adb shell am start -W -n "$package/.MainActivity" > /dev/null

taps=0
menu_dumps=0
reached=0
deadline=$((SECONDS + timeout_seconds))
while [ "$SECONDS" -lt "$deadline" ]; do
  if dump_ui; then
    bounds="$(got_it_bounds)"
    if [ -n "$bounds" ]; then
      tap_centre "$bounds"
    elif [ "$taps" -eq 0 ]; then
      bounds="$(play_bounds)"
      if [ -n "$bounds" ]; then
        tap_centre "$bounds"
        taps=1
      fi
    elif grep -qF 'Game over. Score' "$out_dir/ui-dump.xml"; then
      reached=1
      break
    else
      bounds="$(resume_bounds)"
      if [ -n "$bounds" ]; then
        tap_centre "$bounds"
        menu_dumps=0
      else
        bounds="$(play_bounds)"
        if [ -z "$bounds" ]; then
          menu_dumps=0
        else
          menu_dumps=$((menu_dumps + 1))
          if [ "$menu_dumps" -ge "$replay_after" ] && [ "$taps" -lt 3 ]; then
            tap_centre "$bounds"
            taps=$((taps + 1))
            menu_dumps=0
          fi
        fi
      fi
    fi
  fi
  sleep 1
done

if [ "$reached" -eq 1 ]; then
  sleep "$settle_seconds"
fi
adb logcat -d > "$out_dir/logcat.txt"

if [ "$taps" -eq 0 ]; then
  echo "smoke failed: no Play node found, zero interactions; last dump texts: $(last_dump_texts)" >&2
  exit 1
fi
if [ "$reached" -eq 0 ]; then
  echo "smoke failed: no game over within ${timeout_seconds}s; last dump texts: $(last_dump_texts)" >&2
  exit 1
fi
if grep -qF 'FATAL EXCEPTION' "$out_dir/logcat.txt"; then
  echo "smoke failed: FATAL EXCEPTION in logcat" >&2
  exit 1
fi
echo "smoke passed: game over reached, no FATAL EXCEPTION"
