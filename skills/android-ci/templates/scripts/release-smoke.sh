#!/usr/bin/env bash
set -euo pipefail

apk="${1:?usage: release-smoke.sh <apk>}"
config="${SMOKE_CONFIG:-scripts/release-smoke.conf}"

if [ -f "$config" ]; then
  while IFS='=' read -r key value || [ -n "$key" ]; do
    case "$key" in
      '') ;;
      SMOKE_ACTIVITY | SMOKE_START_TEXT | SMOKE_RESUME_TEXT | SMOKE_DONE_TEXT | SMOKE_TIMEOUT_SECONDS | SMOKE_RUN_SECONDS)
        if [ -z "${!key:-}" ]; then
          printf -v "$key" '%s' "$value"
        fi
        ;;
      *)
        echo "smoke failed: unknown key in $config: $key" >&2
        exit 1
        ;;
    esac
  done < "$config"
fi

start_text="${SMOKE_START_TEXT:-}"
resume_text="${SMOKE_RESUME_TEXT:-}"
done_text="${SMOKE_DONE_TEXT:-}"
if [ -z "$done_text" ] && { [ -n "$start_text" ] || [ -n "$resume_text" ]; }; then
  echo "smoke failed: SMOKE_START_TEXT and SMOKE_RESUME_TEXT need SMOKE_DONE_TEXT" >&2
  exit 1
fi

badging=""
read_badging() {
  if [ -z "$badging" ]; then
    local aapt2="${AAPT2:-${ANDROID_HOME:?ANDROID_HOME is not set}/build-tools/37.0.0/aapt2}"
    badging="$("$aapt2" dump badging "$apk" 2>/dev/null)" || badging=""
  fi
  printf '%s\n' "$badging"
}

package="${PACKAGE:-}"
if [ -z "$package" ]; then
  read_badging > /dev/null
  package="$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)"
  [ -n "$package" ] || { echo "smoke failed: cannot read the package name from $apk" >&2; exit 1; }
fi
activity="${SMOKE_ACTIVITY:-}"
if [ -z "$activity" ]; then
  read_badging > /dev/null
  activity="$(printf '%s\n' "$badging" | sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" | head -n 1)"
  [ -n "$activity" ] || { echo "smoke failed: cannot read the launchable activity from $apk; set SMOKE_ACTIVITY" >&2; exit 1; }
fi
timeout_seconds="${SMOKE_TIMEOUT_SECONDS:-120}"
run_seconds="${SMOKE_RUN_SECONDS:-5}"
settle_seconds="${SMOKE_SETTLE_SECONDS:-2}"
replay_after="${SMOKE_REPLAY_DUMPS:-5}"
out_dir="${OUT_DIR:-build/release-smoke}"

mkdir -p "$out_dir"
: > "$out_dir/ui-dump.xml"
: > "$out_dir/logcat.txt"

collect_evidence() {
  adb logcat -d > "$out_dir/logcat.txt" 2>/dev/null || true
  adb exec-out screencap -p > "$out_dir/smoke-end.png" 2>/dev/null || true
}
trap collect_evidence EXIT

dump_ui() {
  adb shell uiautomator dump /sdcard/ui-dump.xml > /dev/null 2>&1 || return 1
  adb shell cat /sdcard/ui-dump.xml > "$out_dir/ui-dump.xml.next" 2>/dev/null || return 1
  mv "$out_dir/ui-dump.xml.next" "$out_dir/ui-dump.xml"
}

regex_escape() {
  printf '%s' "$1" | sed 's/[][\.*^$+?(){}|/]/\\&/g'
}

node_bounds() {
  { grep -oE "$1" "$out_dir/ui-dump.xml" || true; } |
    head -n 1 |
    sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p'
}

start_bounds() {
  node_bounds "<node [^>]* text=\"$(regex_escape "$start_text")\"[^>]*>"
}

got_it_bounds() {
  node_bounds '<node [^>]* text="Got it"[^>]* package="(android|com\.android\.systemui)"[^>]*>'
}

resume_bounds() {
  node_bounds "<node [^>]* text=\"$(regex_escape "$resume_text")\"[^>]* package=\"$(regex_escape "$package")\"[^>]*>"
}

app_drawn() {
  grep -qF "package=\"$package\"" "$out_dir/ui-dump.xml"
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

fail_on_crash() {
  if grep -qF 'FATAL EXCEPTION' "$out_dir/logcat.txt"; then
    echo "smoke failed: FATAL EXCEPTION in logcat" >&2
    exit 1
  fi
  if grep -qF "ANR in $package" "$out_dir/logcat.txt"; then
    echo "smoke failed: ANR in $package" >&2
    exit 1
  fi
}

adb wait-for-device
adb uninstall "$package" > /dev/null 2>&1 || true
adb install "$apk" > /dev/null
adb logcat -c
adb shell am start -W -n "$package/$activity" > /dev/null

deadline=$((SECONDS + timeout_seconds))

if [ -z "$done_text" ]; then
  drawn=0
  while [ "$SECONDS" -lt "$deadline" ]; do
    if dump_ui; then
      bounds="$(got_it_bounds)"
      if [ -n "$bounds" ]; then
        tap_centre "$bounds"
      elif app_drawn; then
        drawn=1
        break
      fi
    fi
    sleep 1
  done
  if [ "$drawn" -eq 0 ]; then
    adb logcat -d > "$out_dir/logcat.txt"
    echo "smoke failed: $package drew no window within ${timeout_seconds}s; last dump texts: $(last_dump_texts)" >&2
    exit 1
  fi
  sleep "$run_seconds"
  adb logcat -d > "$out_dir/logcat.txt"
  fail_on_crash
  if [ -z "$(adb shell pidof "$package" 2>/dev/null | tr -d '[:space:]')" ]; then
    echo "smoke failed: $package is not running ${run_seconds}s after it drew its window" >&2
    exit 1
  fi
  echo "smoke passed: $package drew its window and kept running for ${run_seconds}s, no FATAL EXCEPTION or ANR"
  exit 0
fi

taps=0
menu_dumps=0
reached=0
while [ "$SECONDS" -lt "$deadline" ]; do
  if dump_ui; then
    bounds="$(got_it_bounds)"
    if [ -n "$bounds" ]; then
      tap_centre "$bounds"
    elif [ -n "$start_text" ] && [ "$taps" -eq 0 ]; then
      bounds="$(start_bounds)"
      if [ -n "$bounds" ]; then
        tap_centre "$bounds"
        taps=1
      fi
    elif grep -qF "$done_text" "$out_dir/ui-dump.xml"; then
      reached=1
      break
    else
      bounds=""
      if [ -n "$resume_text" ]; then
        bounds="$(resume_bounds)"
      fi
      if [ -n "$bounds" ]; then
        tap_centre "$bounds"
        menu_dumps=0
      elif [ -n "$start_text" ]; then
        bounds="$(start_bounds)"
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

if [ -n "$start_text" ] && [ "$taps" -eq 0 ]; then
  echo "smoke failed: no \"$start_text\" node found, zero interactions; last dump texts: $(last_dump_texts)" >&2
  exit 1
fi
if [ "$reached" -eq 0 ]; then
  echo "smoke failed: \"$done_text\" not reached within ${timeout_seconds}s; last dump texts: $(last_dump_texts)" >&2
  exit 1
fi
fail_on_crash
echo "smoke passed: \"$done_text\" reached, no FATAL EXCEPTION or ANR"
