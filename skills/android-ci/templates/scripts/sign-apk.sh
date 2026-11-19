#!/usr/bin/env bash
set -euo pipefail

in_apk="${1:?usage: sign-apk.sh <in.apk> <out.apk>}"
out_apk="${2:?usage: sign-apk.sh <in.apk> <out.apk>}"
: "${KS_FILE:?KS_FILE is not set}"
: "${KS_PASS:?KS_PASS is not set}"
: "${KEY_ALIAS:?KEY_ALIAS is not set}"
: "${KEY_PASS:?KEY_PASS is not set}"
apksigner="${APKSIGNER:-${ANDROID_HOME:?ANDROID_HOME is not set}/build-tools/37.0.0/apksigner}"

if [ ! -f "$KS_FILE" ]; then
  echo "keystore file not found" >&2
  exit 1
fi
if [ ! -f "$in_apk" ]; then
  echo "input apk not found: $in_apk" >&2
  exit 1
fi

mkdir -p "$(dirname "$out_apk")"
rm -f "$out_apk"
partial="$out_apk.partial"
trap 'rm -f "$partial" "$partial.idsig"' EXIT

"$apksigner" -J-enable-native-access=ALL-UNNAMED sign \
  --ks "$KS_FILE" \
  --ks-key-alias "$KEY_ALIAS" \
  --ks-pass env:KS_PASS \
  --key-pass env:KEY_PASS \
  --out "$partial" \
  "$in_apk"
"$apksigner" -J-enable-native-access=ALL-UNNAMED verify -v "$partial"
mv "$partial" "$out_apk"
