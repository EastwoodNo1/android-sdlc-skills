#!/usr/bin/env bash
set -euo pipefail

in_apk="${1:?usage: sign-throwaway.sh <in.apk> <out.apk>}"
out_apk="${2:?usage: sign-throwaway.sh <in.apk> <out.apk>}"
here="$(cd "$(dirname "$0")" && pwd)"

work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/throwaway-key.XXXXXX")"
trap 'rm -rf "$work"' EXIT

KS_FILE="$work/throwaway.p12"
KS_PASS="$(openssl rand -hex 24)"
KEY_ALIAS=throwaway
KEY_PASS="$KS_PASS"
export KS_FILE KS_PASS KEY_ALIAS KEY_PASS

keytool -genkeypair \
  -keystore "$KS_FILE" \
  -storetype PKCS12 \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 2 \
  -dname "CN=throwaway" \
  -storepass:env KS_PASS \
  -keypass:env KEY_PASS

"$here/sign-apk.sh" "$in_apk" "$out_apk"
