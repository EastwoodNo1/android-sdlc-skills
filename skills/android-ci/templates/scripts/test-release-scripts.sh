#!/usr/bin/env bash
set -uo pipefail

unsigned_apk="${1:?usage: test-release-scripts.sh <unsigned.apk>}"
here="$(cd "$(dirname "$0")" && pwd)"
[ -f "$unsigned_apk" ] || { echo "apk not found: $unsigned_apk" >&2; exit 1; }
unsigned_apk="$(cd "$(dirname "$unsigned_apk")" && pwd)/$(basename "$unsigned_apk")"
work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/release-script-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT
[ -n "${ANDROID_HOME:-}" ] || { echo "ANDROID_HOME is not set" >&2; exit 1; }
apksigner="${APKSIGNER:-$ANDROID_HOME/build-tools/37.0.0/apksigner}"
[ -x "$apksigner" ] || { echo "apksigner not found: $apksigner" >&2; exit 1; }

fail() {
  echo "assertion failed: $*" >&2
  exit 1
}

need() {
  for script in "$@"; do
    [ -x "$here/$script" ] || fail "missing or not executable: scripts/$script"
  done
}

expect_status() {
  local want="$1" got="$2" what="$3"
  [ "$got" -eq "$want" ] || fail "$what: exit $got, wanted $want"
}

expect_nonzero() {
  [ "$1" -ne 0 ] || fail "$2: exit 0, wanted non-zero"
}

expect_in() {
  grep -qF -- "$2" "$1" || fail "$1 lacks: $2"
}

expect_not_in() {
  if grep -qF -- "$2" "$1"; then
    fail "$1 contains: $2"
  fi
}

expect_reached_launch() {
  local calls="$1/calls.log"
  expect_in "$calls" "install "
  expect_in "$calls" "logcat -c"
  expect_in "$calls" "shell am start"
  expect_in "$calls" "logcat -d"
}

make_keystore() {
  local dir="$1" pass="$2" alias="$3"
  KT_PASS="$pass" keytool -genkeypair -keystore "$dir/ks.p12" -storetype PKCS12 \
    -alias "$alias" -keyalg RSA -keysize 2048 -validity 2 -dname "CN=test" \
    -storepass:env KT_PASS -keypass:env KT_PASS > /dev/null 2>&1 || fail "keytool could not make a keystore"
}

fake_adb() {
  local dir="$1"
  mkdir -p "$dir/bin"
  : > "$dir/taps.log"
  : > "$dir/calls.log"
  printf '#!%s\n' "/usr/bin/env bash" > "$dir/bin/adb"
  cat >> "$dir/bin/adb" <<'FAKE'
dir="$FAKE_DIR"
echo "$*" >> "$dir/calls.log"
case "$*" in
  install*|uninstall*|wait-for-device|"logcat -c"|"shell am start"*|"shell uiautomator dump"*) exit 0 ;;
  "logcat -d")
    cat "$dir/logcat.txt"
    if [ -s "$dir/over.shown" ] && [ -f "$dir/late-logcat.txt" ] && [ $(($(date +%s) - $(cat "$dir/over.shown"))) -ge 2 ]; then
      cat "$dir/late-logcat.txt"
    fi
    ;;
  "shell cat "*)
    taps_done=$(($(wc -l < "$dir/taps.log")))
    if [ -f "$dir/dump-$taps_done.xml" ]; then
      cat "$dir/dump-$taps_done.xml"
    elif [ -s "$dir/taps.log" ] && [ -f "$dir/dump-after.xml" ]; then
      [ -s "$dir/over.shown" ] || date +%s > "$dir/over.shown"
      cat "$dir/dump-after.xml"
    else
      cat "$dir/dump.xml"
    fi
    ;;
  "shell input tap "*) echo "$*" >> "$dir/taps.log" ;;
  "exec-out screencap"*) printf 'png' ;;
  *) echo "unexpected adb call: $*" >&2; exit 99 ;;
esac
FAKE
  chmod +x "$dir/bin/adb"
  : > "$dir/logcat.txt"
  printf '<hierarchy><node index="0" text="Home" bounds="[0,0][10,10]" /></hierarchy>' > "$dir/dump.xml"
}

play_dump='<hierarchy><node index="0" text="Play" bounds="[100,200][300,400]" /></hierarchy>'
over_dump='<hierarchy><node index="0" text="Game over. Score 3" bounds="[0,0][10,10]" /></hierarchy>'

run_smoke() {
  local dir="$1"
  FAKE_DIR="$dir" PATH="$dir/bin:$PATH" PACKAGE="${PACKAGE_UNDER_TEST-com.example.app}" OUT_DIR="$dir/out" SMOKE_TIMEOUT_SECONDS="${SMOKE_TIMEOUT_SECONDS:-2}" SMOKE_SETTLE_SECONDS="${SMOKE_SETTLE_SECONDS:-0}" \
    "$here/release-smoke.sh" "$unsigned_apk" > "$dir/stdout.txt" 2> "$dir/stderr.txt"
}

fake_aapt2() {
  local dir="$1" body="$2"
  mkdir -p "$dir/bin"
  printf '#!%s\n%s\n' "/usr/bin/env bash" "$body" > "$dir/bin/aapt2"
  chmod +x "$dir/bin/aapt2"
}

smokeDerivesThePackageFromTheApk() {
  need release-smoke.sh
  local d="$work/derive"
  fake_adb "$d"
  fake_aapt2 "$d" "echo \"package: name='com.example.derived' versionCode='1' versionName='1.0'\""
  printf '%s' "$play_dump" > "$d/dump.xml"
  printf '%s' "$over_dump" > "$d/dump-after.xml"
  local rc=0
  AAPT2="$d/bin/aapt2" PACKAGE_UNDER_TEST='' SMOKE_TIMEOUT_SECONDS=10 run_smoke "$d" || rc=$?
  expect_status 0 "$rc" "smoke with a derived package"
  expect_in "$d/calls.log" "uninstall com.example.derived"
  expect_in "$d/calls.log" "shell am start -W -n com.example.derived/.MainActivity"
}

smokeFailsWhenThePackageCannotBeRead() {
  need release-smoke.sh
  local d="$work/underive"
  fake_adb "$d"
  fake_aapt2 "$d" "exit 1"
  local rc=0
  AAPT2="$d/bin/aapt2" PACKAGE_UNDER_TEST='' run_smoke "$d" || rc=$?
  expect_nonzero "$rc" "smoke with an unreadable package"
  expect_in "$d/stderr.txt" "cannot read the package name"
  [ ! -s "$d/calls.log" ] || fail "adb was called before the package was known"
}

smokeKeepsAnExplicitPackage() {
  need release-smoke.sh
  local d="$work/explicit"
  fake_adb "$d"
  fake_aapt2 "$d" "echo should-not-run >&2; exit 1"
  printf '%s' "$play_dump" > "$d/dump.xml"
  printf '%s' "$over_dump" > "$d/dump-after.xml"
  local rc=0
  AAPT2="$d/bin/aapt2" SMOKE_TIMEOUT_SECONDS=10 run_smoke "$d" || rc=$?
  expect_status 0 "$rc" "smoke with an explicit package"
  expect_in "$d/calls.log" "uninstall com.example.app"
}

settings_script="$here/github/apply-repo-settings.sh"
settings_template="$here/github/expected-settings.json"

settingsTemplateCarriesNoProjectIds() {
  jq -e '.environments.release.reviewers[0].id == 0 and .release_tags.bypass_actors[0].actor_id == 0' "$settings_template" > /dev/null || fail "template ids are not the 0 marker"
}

settingsMergeFillsTheProjectIds() {
  local d="$work/merge"
  mkdir -p "$d"
  printf '{"release_reviewer_user_id": 11, "release_app_id": 22}' > "$d/project.json"
  PROJECT_SETTINGS="$d/project.json" "$settings_script" --print-expected > "$d/merged.json" 2> "$d/stderr.txt" || fail "print-expected failed: $(cat "$d/stderr.txt")"
  [ "$(jq '.environments.release.reviewers[0].id' "$d/merged.json")" = "11" ] || fail "reviewer id not filled"
  [ "$(jq '.release_tags.bypass_actors[0].actor_id' "$d/merged.json")" = "22" ] || fail "app id not filled"
  [ "$(jq -S 'del(.environments.release.reviewers[0].id, .release_tags.bypass_actors[0].actor_id)' "$d/merged.json")" = "$(jq -S 'del(.environments.release.reviewers[0].id, .release_tags.bypass_actors[0].actor_id)' "$settings_template")" ] || fail "merge changed other keys"
}

settingsMergeRejectsBadProjectValues() {
  local d="$work/badmerge" rc=0
  mkdir -p "$d"
  printf '{"release_reviewer_user_id": 11}' > "$d/missing.json"
  PROJECT_SETTINGS="$d/missing.json" "$settings_script" --print-expected > /dev/null 2> "$d/missing.err" || rc=$?
  expect_nonzero "$rc" "missing app id"
  expect_in "$d/missing.err" "release_app_id"
  printf '{"release_reviewer_user_id": 0, "release_app_id": 22}' > "$d/zero.json"
  rc=0
  PROJECT_SETTINGS="$d/zero.json" "$settings_script" --print-expected > /dev/null 2> "$d/zero.err" || rc=$?
  expect_nonzero "$rc" "zero reviewer id"
  expect_in "$d/zero.err" "release_reviewer_user_id"
  rc=0
  PROJECT_SETTINGS="$d/absent.json" "$settings_script" --print-expected > /dev/null 2> "$d/absent.err" || rc=$?
  expect_nonzero "$rc" "absent project file"
  expect_in "$d/absent.err" "project-settings"
}

signedApkVerifies() {
  need sign-throwaway.sh
  local rc=0
  "$here/sign-throwaway.sh" "$unsigned_apk" "$work/signed.apk" > /dev/null 2>&1 || rc=$?
  expect_status 0 "$rc" "sign-throwaway"
  rc=0
  local out
  out="$("$apksigner" verify -v "$work/signed.apk" 2>&1)" || rc=$?
  expect_status 0 "$rc" "apksigner verify"
  case "$out" in *Verifies*) ;; *) fail "verify output lacks Verifies: $out" ;; esac
}

wrongAliasFails() {
  need sign-apk.sh
  local d="$work/wrongalias"
  mkdir -p "$d"
  make_keystore "$d" pw-wrong-alias right
  local rc=0
  KS_FILE="$d/ks.p12" KS_PASS=pw-wrong-alias KEY_ALIAS=other KEY_PASS=pw-wrong-alias \
    "$here/sign-apk.sh" "$unsigned_apk" "$d/out.apk" > /dev/null 2> "$d/err.txt" || rc=$?
  expect_nonzero "$rc" "wrong alias"
  expect_in "$d/err.txt" 'entry "other" does not contain a key'
  expect_not_in "$d/err.txt" ANDROID_HOME
  [ ! -e "$d/out.apk" ] || fail "an output apk exists after a failed signing"
}

missingKeystoreFails() {
  need sign-apk.sh
  local d="$work/missingks"
  mkdir -p "$d"
  local rc=0
  KS_FILE="$d/none.p12" KS_PASS=pw KEY_ALIAS=a KEY_PASS=pw \
    "$here/sign-apk.sh" "$unsigned_apk" "$d/out.apk" > /dev/null 2> "$d/err.txt" || rc=$?
  expect_nonzero "$rc" "missing keystore"
  expect_in "$d/err.txt" "keystore file not found"
  expect_not_in "$d/err.txt" ANDROID_HOME
  [ ! -e "$d/out.apk" ] || fail "an output apk exists after a failed signing"
}

signApkNeverPrintsSecrets() {
  need sign-apk.sh
  local d="$work/secrets"
  mkdir -p "$d"
  make_keystore "$d" topsecretpass right
  local rc=0
  KS_FILE="$d/ks.p12" KS_PASS=topsecretpass KEY_ALIAS=right KEY_PASS=topsecretpass \
    "$here/sign-apk.sh" "$unsigned_apk" "$d/ok.apk" > "$d/ok.txt" 2>&1 || rc=$?
  expect_status 0 "$rc" "passing sign run"
  rc=0
  KS_FILE="$d/ks.p12" KS_PASS=topsecretpass KEY_ALIAS=other KEY_PASS=topsecretpass \
    "$here/sign-apk.sh" "$unsigned_apk" "$d/bad.apk" > "$d/bad.txt" 2>&1 || rc=$?
  expect_nonzero "$rc" "failing sign run"
  expect_in "$d/bad.txt" 'entry "other" does not contain a key'
  expect_not_in "$d/bad.txt" ANDROID_HOME
  [ -s "$d/ok.txt" ] || fail "the passing run printed nothing, so the check proves nothing"
  [ -s "$d/bad.txt" ] || fail "the failing run printed nothing, so the check proves nothing"
  if grep -q topsecretpass "$d/ok.txt" "$d/bad.txt"; then
    fail "a secret reached the output"
  fi
}

noPlayButtonFailsTheSmoke() {
  need release-smoke.sh
  local d="$work/noplay"
  fake_adb "$d"
  local rc=0
  run_smoke "$d" || rc=$?
  expect_nonzero "$rc" "no Play node"
  expect_in "$d/stderr.txt" "smoke failed: no Play node found"
  expect_reached_launch "$d"
  [ ! -s "$d/taps.log" ] || fail "a tap was recorded without a Play node"
}

missingGameOverFailsTheSmoke() {
  need release-smoke.sh
  local d="$work/nogameover"
  fake_adb "$d"
  printf '%s' "$play_dump" > "$d/dump.xml"
  local rc=0
  run_smoke "$d" || rc=$?
  expect_nonzero "$rc" "no game over"
  expect_in "$d/stderr.txt" "smoke failed: no game over"
  expect_reached_launch "$d"
  [ "$(wc -l < "$d/taps.log")" -eq 1 ] || fail "expected exactly one tap"
}

fatalExceptionFailsTheSmoke() {
  need release-smoke.sh
  local d="$work/fatal"
  fake_adb "$d"
  printf '%s' "$play_dump" > "$d/dump.xml"
  printf '%s' "$over_dump" > "$d/dump-after.xml"
  printf '11-02 10:00:00.000 E AndroidRuntime: FATAL EXCEPTION: main\n' > "$d/logcat.txt"
  local rc=0
  SMOKE_TIMEOUT_SECONDS=10 run_smoke "$d" || rc=$?
  expect_nonzero "$rc" "FATAL EXCEPTION in logcat"
  expect_in "$d/stderr.txt" "smoke failed: FATAL EXCEPTION"
  expect_reached_launch "$d"
}

smokePassesAndKeepsEvidence() {
  need release-smoke.sh
  local d="$work/pass"
  fake_adb "$d"
  printf '%s' "$play_dump" > "$d/dump.xml"
  printf '%s' "$over_dump" > "$d/dump-after.xml"
  local rc=0
  SMOKE_TIMEOUT_SECONDS=10 run_smoke "$d" || rc=$?
  expect_status 0 "$rc" "clean smoke"
  [ "$(wc -l < "$d/taps.log")" -eq 1 ] || fail "expected exactly one tap"
  grep -q 'input tap 200 300' "$d/taps.log" || fail "tap was not at the centre of the Play node"
  for file in ui-dump.xml logcat.txt game-over.png; do
    [ -f "$d/out/$file" ] || fail "missing evidence file $file"
  done
}

crashAfterGameOverFailsTheSmoke() {
  need release-smoke.sh
  local d="$work/lateCrash"
  fake_adb "$d"
  printf '%s' "$play_dump" > "$d/dump.xml"
  printf '%s' "$over_dump" > "$d/dump-after.xml"
  printf '11-02 10:00:05.000 E AndroidRuntime: FATAL EXCEPTION: main\n' > "$d/late-logcat.txt"
  local rc=0
  SMOKE_TIMEOUT_SECONDS=10 SMOKE_SETTLE_SECONDS=2 run_smoke "$d" || rc=$?
  expect_nonzero "$rc" "crash after game over"
  expect_in "$d/stderr.txt" "smoke failed: FATAL EXCEPTION"
  expect_reached_launch "$d"
}

ignoresPlayAgainAndContentDesc() {
  need release-smoke.sh
  local d="$work/lookalikes"
  fake_adb "$d"
  printf '%s' '<hierarchy><node index="0" text="Play again" bounds="[1,2][3,4]" /><node index="1" text="" content-desc="Play" bounds="[5,6][7,8]" /></hierarchy>' > "$d/dump.xml"
  local rc=0
  run_smoke "$d" || rc=$?
  expect_nonzero "$rc" "look-alike nodes"
  expect_in "$d/stderr.txt" "smoke failed: no Play node found"
  [ ! -s "$d/taps.log" ] || fail "a tap was recorded for a look-alike node"
  printf '%s' '<hierarchy><node index="0" text="Play again" bounds="[1,2][3,4]" /><node index="1" text="Play" bounds="[100,200][300,400]" /></hierarchy>' > "$d/dump.xml"
  rc=0
  run_smoke "$d" || rc=$?
  [ "$(wc -l < "$d/taps.log")" -eq 1 ] || fail "expected exactly one tap"
  grep -q 'input tap 200 300' "$d/taps.log" || fail "tapped something other than the Play node"
}

dismissesTheFullScreenConfirmation() {
  need release-smoke.sh
  local d="$work/immersive"
  fake_adb "$d"
  local overlay='<node index="0" text="Viewing full screen" package="android" bounds="[100,50][900,100]" /><node index="1" text="To exit, swipe down from the top." package="android" bounds="[100,100][900,150]" /><node index="2" text="Got it" resource-id="android:id/ok" package="android" bounds="[800,100][1000,200]" />'
  printf '<hierarchy>%s</hierarchy>' "$overlay" > "$d/dump.xml"
  printf '%s' "$play_dump" > "$d/dump-1.xml"
  printf '%s' "$over_dump" > "$d/dump-after.xml"
  local rc=0
  SMOKE_TIMEOUT_SECONDS=10 run_smoke "$d" || rc=$?
  expect_status 0 "$rc" "smoke behind the confirmation"
  [ "$(wc -l < "$d/taps.log")" -eq 2 ] || fail "expected two taps"
  sed -n 1p "$d/taps.log" | grep -q 'input tap 900 150' || fail "first tap was not on Got it"
  sed -n 2p "$d/taps.log" | grep -q 'input tap 200 300' || fail "second tap was not on Play"
}

dismissesTheConfirmationAfterPlay() {
  need release-smoke.sh
  local d="$work/immersiveLate"
  fake_adb "$d"
  printf '%s' "$play_dump" > "$d/dump.xml"
  printf '<hierarchy><node index="0" text="Got it" package="com.android.systemui" bounds="[800,100][1000,200]" /></hierarchy>' > "$d/dump-1.xml"
  printf '%s' "$over_dump" > "$d/dump-after.xml"
  local rc=0
  SMOKE_TIMEOUT_SECONDS=10 run_smoke "$d" || rc=$?
  expect_status 0 "$rc" "smoke with the confirmation after Play"
  [ "$(wc -l < "$d/taps.log")" -eq 2 ] || fail "expected two taps"
}

resumesAfterAnInterruption() {
  need release-smoke.sh
  local d="$work/interrupted"
  fake_adb "$d"
  printf '%s' "$play_dump" > "$d/dump.xml"
  printf '<hierarchy><node index="0" text="Paused" package="com.example.app" bounds="[0,0][10,10]" /><node index="1" text="Resume" package="com.example.app" bounds="[474,1082][608,1135]" /></hierarchy>' > "$d/dump-1.xml"
  printf '%s' "$over_dump" > "$d/dump-after.xml"
  local rc=0
  SMOKE_TIMEOUT_SECONDS=10 run_smoke "$d" || rc=$?
  expect_status 0 "$rc" "smoke after a system dialog paused the game"
  [ "$(wc -l < "$d/taps.log")" -eq 2 ] || fail "expected two taps"
  grep -qF 'shell input tap 541 1108' "$d/taps.log" || fail "did not tap Resume"
}

tapsPlayAgainWhenTheTapWasLost() {
  need release-smoke.sh
  local d="$work/lostPlay"
  fake_adb "$d"
  printf '%s' "$play_dump" > "$d/dump.xml"
  printf '%s' "$play_dump" > "$d/dump-1.xml"
  printf '%s' "$over_dump" > "$d/dump-after.xml"
  local rc=0
  SMOKE_TIMEOUT_SECONDS=20 run_smoke "$d" || rc=$?
  expect_status 0 "$rc" "smoke after a lost Play tap"
  [ "$(wc -l < "$d/taps.log")" -eq 2 ] || fail "expected two taps"
  [ "$(grep -c 'input tap 200 300' "$d/taps.log")" -eq 2 ] || fail "both taps were not on Play"
}

stopsTappingPlayAfterThreeTries() {
  need release-smoke.sh
  local d="$work/deadPlay"
  fake_adb "$d"
  printf '%s' "$play_dump" > "$d/dump.xml"
  local rc=0
  SMOKE_TIMEOUT_SECONDS=30 run_smoke "$d" || rc=$?
  expect_nonzero "$rc" "Play never starts a round"
  expect_in "$d/stderr.txt" "smoke failed: no game over"
  [ "$(wc -l < "$d/taps.log")" -eq 3 ] || fail "expected exactly three Play taps"
}

ignoresResumeFromOtherPackages() {
  need release-smoke.sh
  local d="$work/otherResume"
  fake_adb "$d"
  printf '%s' "$play_dump" > "$d/dump.xml"
  printf '<hierarchy><node index="0" text="Resume" package="some.other.app" bounds="[474,1082][608,1135]" /></hierarchy>' > "$d/dump-1.xml"
  local rc=0
  run_smoke "$d" || rc=$?
  expect_nonzero "$rc" "Resume from another package"
  [ "$(wc -l < "$d/taps.log")" -eq 1 ] || fail "tapped a Resume that is not the app's"
}

ignoresGotItFromOtherPackages() {
  need release-smoke.sh
  local d="$work/otherGotIt"
  fake_adb "$d"
  printf '<hierarchy><node index="0" text="Got it" package="some.other.app" bounds="[800,100][1000,200]" /></hierarchy>' > "$d/dump.xml"
  local rc=0
  run_smoke "$d" || rc=$?
  expect_nonzero "$rc" "Got it from another package"
  [ ! -s "$d/taps.log" ] || fail "tapped a Got it that is not from the system UI"
}

timeoutNamesTheLastDumpTexts() {
  need release-smoke.sh
  local d="$work/lastTexts"
  fake_adb "$d"
  printf '<hierarchy><node index="0" text="Viewing full screen" package="x" bounds="[0,0][1,1]" /><node index="1" text="Other" package="x" bounds="[0,0][1,1]" /></hierarchy>' > "$d/dump.xml"
  local rc=0
  run_smoke "$d" || rc=$?
  expect_nonzero "$rc" "no Play node"
  expect_in "$d/stderr.txt" "last dump texts: Viewing full screen, Other"
}

lastTextsKeepCommasInsideATextTogether() {
  need release-smoke.sh
  local d="$work/commaTexts"
  fake_adb "$d"
  printf '<hierarchy><node index="0" text="To exit, swipe down from the top." package="x" bounds="[0,0][1,1]" /><node index="1" text="Got it" package="x" bounds="[0,0][1,1]" /></hierarchy>' > "$d/dump.xml"
  local rc=0
  run_smoke "$d" || rc=$?
  expect_nonzero "$rc" "no Play node"
  expect_in "$d/stderr.txt" "last dump texts: To exit, swipe down from the top., Got it"
}

signer_digest() {
  "$apksigner" verify -v --print-certs "$1" 2>&1 | sed -n 's/^.*Signer: certificate SHA-256 digest: //p' | sed -n 1p
}

fake_apksigner() {
  local dir="$1"
  mkdir -p "$dir"
  : > "$dir/apksigner.log"
  printf '#!%s\n' "/usr/bin/env bash" > "$dir/apksigner"
  cat >> "$dir/apksigner" <<'FAKE'
echo "$*" >> "$FAKE_DIR/apksigner.log"
exit 99
FAKE
  chmod +x "$dir/apksigner"
}

signed_with_throwaway() {
  local d="$1"
  mkdir -p "$d"
  make_keystore "$d" pw-verify key
  KS_FILE="$d/ks.p12" KS_PASS=pw-verify KEY_ALIAS=key KEY_PASS=pw-verify \
    "$here/sign-apk.sh" "$unsigned_apk" "$d/signed.apk" > /dev/null 2>&1 || fail "could not sign with the throwaway key"
}

fingerprintMatchPasses() {
  need verify-signature.sh
  local d="$work/fpMatch"
  signed_with_throwaway "$d"
  local digest
  digest="$(signer_digest "$d/signed.apk")"
  [ "${#digest}" -eq 64 ] || fail "could not read the digest: $digest"
  local rc=0
  "$here/verify-signature.sh" "$d/signed.apk" "$digest" > /dev/null 2>&1 || rc=$?
  expect_status 0 "$rc" "matching fingerprint"
  rc=0
  "$here/verify-signature.sh" "$d/signed.apk" "$(printf '%s' "$digest" | tr 'a-f' 'A-F')" > /dev/null 2>&1 || rc=$?
  expect_status 0 "$rc" "matching fingerprint in upper case"
}

fingerprintMismatchFailsClosed() {
  need verify-signature.sh
  local d="$work/fpMismatch"
  signed_with_throwaway "$d"
  local rc=0
  "$here/verify-signature.sh" "$d/signed.apk" "$(printf '0%.0s' $(seq 64))" > /dev/null 2>&1 || rc=$?
  expect_nonzero "$rc" "mismatching fingerprint"
}

emptyFingerprintFailsClosed() {
  need verify-signature.sh
  local d="$work/fpEmpty"
  signed_with_throwaway "$d"
  fake_apksigner "$d/fake"
  local digest value rc
  digest="$(signer_digest "$d/signed.apk")"
  local colons
  colons="$(printf '%s' "$digest" | sed 's/\(..\)/\1:/g; s/:$//')"
  for value in "" "abc" "$colons" "${digest}0" "${digest%?}g"; do
    rc=0
    FAKE_DIR="$d/fake" APKSIGNER="$d/fake/apksigner" \
      "$here/verify-signature.sh" "$d/signed.apk" "$value" > /dev/null 2>&1 || rc=$?
    expect_nonzero "$rc" "fingerprint '$value'"
  done
  [ ! -s "$d/fake/apksigner.log" ] || fail "apksigner was called for a malformed fingerprint"
  rc=0
  FAKE_DIR="$d/fake" APKSIGNER="$d/fake/apksigner" \
    "$here/verify-signature.sh" "$d/signed.apk" "$digest" > /dev/null 2>&1 || rc=$?
  expect_nonzero "$rc" "a failing apksigner"
  [ -s "$d/fake/apksigner.log" ] || fail "the fake apksigner was never called, so the check proves nothing"
}

unsignedApkFailsVerification() {
  need verify-signature.sh
  local d="$work/fpUnsigned"
  signed_with_throwaway "$d"
  local digest rc=0
  digest="$(signer_digest "$d/signed.apk")"
  "$here/verify-signature.sh" "$unsigned_apk" "$digest" > /dev/null 2>&1 || rc=$?
  expect_nonzero "$rc" "unsigned apk"
}

make_release_repo() {
  local d="$1" version="$2"
  mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git init -q -b main "$d/repo"
  git -C "$d/repo" config user.email test@example.invalid
  git -C "$d/repo" config user.name test
  git -C "$d/repo" config commit.gpgsign false
  git -C "$d/repo" config tag.gpgsign false
  git -C "$d/repo" remote add origin "$d/origin.git"
  printf '%s\n' "$version" > "$d/repo/version.txt"
  git -C "$d/repo" add version.txt
  git -C "$d/repo" commit -q -m release
  git -C "$d/repo" push -q origin main
  git -C "$d/repo" rev-parse HEAD
}

run_ref_check() {
  local d="$1"
  shift
  (cd "$d/repo" && "$here/check-release-ref.sh" "$@") > /dev/null 2>&1
}

apksignerRunsWithoutJdkWarnings() {
  need sign-apk.sh verify-signature.sh
  local d="$work/quiet"
  mkdir -p "$d"
  make_keystore "$d" pw-quiet key
  KS_FILE="$d/ks.p12" KS_PASS=pw-quiet KEY_ALIAS=key KEY_PASS=pw-quiet \
    "$here/sign-apk.sh" "$unsigned_apk" "$d/signed.apk" > "$d/sign.out" 2> "$d/sign.err" || fail "could not sign with the throwaway key"
  expect_not_in "$d/sign.err" "WARNING"
  local digest
  digest="$(signer_digest "$d/signed.apk")"
  "$here/verify-signature.sh" "$d/signed.apk" "$digest" > "$d/verify.out" 2> "$d/verify.err" || fail "verify-signature failed"
  expect_not_in "$d/verify.err" "WARNING"
}

tagOnMainPasses() {
  need check-release-ref.sh
  local d="$work/tagMain" sha rc=0
  sha="$(make_release_repo "$d" 1.0.0)"
  git -C "$d/repo" tag v1.0.0 "$sha"
  git -C "$d/repo" push -q origin v1.0.0
  run_ref_check "$d" "$sha" v1.0.0 1.0.0 || rc=$?
  expect_status 0 "$rc" "tag on main"
}

tagOffMainFails() {
  need check-release-ref.sh
  local d="$work/tagOff" sha side rc=0
  sha="$(make_release_repo "$d" 1.0.0)"
  git -C "$d/repo" checkout -q -b side
  printf '1.0.0\n' > "$d/repo/other.txt"
  git -C "$d/repo" add other.txt
  git -C "$d/repo" commit -q -m side
  side="$(git -C "$d/repo" rev-parse HEAD)"
  git -C "$d/repo" tag v1.0.0 "$side"
  git -C "$d/repo" push -q origin side v1.0.0
  run_ref_check "$d" "$side" v1.0.0 1.0.0 || rc=$?
  expect_nonzero "$rc" "tag off main"
  rc=0
  run_ref_check "$d" "$sha" v1.0.0 1.0.0 || rc=$?
  expect_nonzero "$rc" "tag pointing at another commit"
}

missingTagFails() {
  need check-release-ref.sh
  local d="$work/tagMissing" sha rc=0
  sha="$(make_release_repo "$d" 1.0.0)"
  git -C "$d/repo" tag v1.0.0 "$sha"
  run_ref_check "$d" "$sha" v1.0.0 1.0.0 || rc=$?
  expect_nonzero "$rc" "tag only local"
}

versionMismatchFails() {
  need check-release-ref.sh
  local d="$work/versionMismatch" sha rc=0
  sha="$(make_release_repo "$d" 1.0.1)"
  git -C "$d/repo" tag v1.0.0 "$sha"
  git -C "$d/repo" push -q origin v1.0.0
  run_ref_check "$d" "$sha" v1.0.0 1.0.0 || rc=$?
  expect_nonzero "$rc" "version mismatch"
}

fake_gh() {
  local dir="$1" is_draft="$2"
  mkdir -p "$dir/bin"
  : > "$dir/gh.log"
  printf '%s' "$is_draft" > "$dir/isdraft"
  printf '#!%s\n' "/usr/bin/env bash" > "$dir/bin/gh"
  cat >> "$dir/bin/gh" <<'FAKE'
echo "$*" >> "$FAKE_DIR/gh.log"
case "$*" in
  "release view "*) cat "$FAKE_DIR/isdraft" ;;
  "release upload "*|"release edit "*) exit 0 ;;
  *) echo "unexpected gh call: $*" >&2; exit 99 ;;
esac
FAKE
  chmod +x "$dir/bin/gh"
  printf 'apk' > "$dir/app.apk"
  printf 'sum' > "$dir/app.apk.sha256"
}

run_publish() {
  local dir="$1"
  FAKE_DIR="$dir" PATH="$dir/bin:$PATH" \
    "$here/publish-release.sh" v1.0.0 "$dir/app.apk" "$dir/app.apk.sha256" > "$dir/stdout.txt" 2> "$dir/stderr.txt"
}

publishUploadsThenPublishesDraft() {
  need publish-release.sh
  local d="$work/publishDraft" rc=0
  fake_gh "$d" true
  run_publish "$d" || rc=$?
  expect_status 0 "$rc" "publish of a draft"
  [ "$(wc -l < "$d/gh.log")" -eq 3 ] || fail "expected exactly three gh calls: $(cat "$d/gh.log")"
  sed -n 1p "$d/gh.log" | grep -qF 'release view v1.0.0 --json isDraft --jq .isDraft' || fail "first call was not the draft check"
  sed -n 2p "$d/gh.log" | grep -qF "release upload v1.0.0 $d/app.apk $d/app.apk.sha256 --clobber" || fail "second call was not the upload"
  sed -n 3p "$d/gh.log" | grep -qF 'release edit v1.0.0 --draft=false' || fail "third call was not the publish"
}

publishSkipsWhenAlreadyPublished() {
  need publish-release.sh
  local d="$work/publishDone" rc=0
  fake_gh "$d" false
  run_publish "$d" || rc=$?
  expect_status 0 "$rc" "publish of a published release"
  expect_in "$d/stdout.txt" "already published"
  expect_not_in "$d/gh.log" "release upload"
  expect_not_in "$d/gh.log" "release edit"
  expect_in "$d/gh.log" "release view"
}

tests=(
  signedApkVerifies
  wrongAliasFails
  missingKeystoreFails
  signApkNeverPrintsSecrets
  noPlayButtonFailsTheSmoke
  missingGameOverFailsTheSmoke
  fatalExceptionFailsTheSmoke
  crashAfterGameOverFailsTheSmoke
  ignoresPlayAgainAndContentDesc
  dismissesTheFullScreenConfirmation
  dismissesTheConfirmationAfterPlay
  resumesAfterAnInterruption
  tapsPlayAgainWhenTheTapWasLost
  stopsTappingPlayAfterThreeTries
  ignoresResumeFromOtherPackages
  ignoresGotItFromOtherPackages
  timeoutNamesTheLastDumpTexts
  lastTextsKeepCommasInsideATextTogether
  smokePassesAndKeepsEvidence
  fingerprintMatchPasses
  fingerprintMismatchFailsClosed
  emptyFingerprintFailsClosed
  apksignerRunsWithoutJdkWarnings
  unsignedApkFailsVerification
  tagOnMainPasses
  tagOffMainFails
  missingTagFails
  versionMismatchFails
  publishUploadsThenPublishesDraft
  publishSkipsWhenAlreadyPublished
  smokeDerivesThePackageFromTheApk
  smokeFailsWhenThePackageCannotBeRead
  smokeKeepsAnExplicitPackage
  settingsTemplateCarriesNoProjectIds
  settingsMergeFillsTheProjectIds
  settingsMergeRejectsBadProjectValues
)

passed=0
failed=0
for name in "${tests[@]}"; do
  ( set -e; "$name" )
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "PASS $name"
    passed=$((passed + 1))
  else
    echo "FAIL $name"
    failed=$((failed + 1))
  fi
done

echo "$passed passed"
if [ "$failed" -ne 0 ]; then
  echo "$failed failed" >&2
  exit 1
fi
