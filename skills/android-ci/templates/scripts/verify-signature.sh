#!/usr/bin/env bash
set -euo pipefail

apk="${1:?usage: verify-signature.sh <apk> <expected-sha256>}"
expected="${2-}"

expected="$(printf '%s' "$expected" | tr 'A-F' 'a-f')"
case "$expected" in
  *[!0-9a-f]*) expected="" ;;
esac
if [ "${#expected}" -ne 64 ]; then
  echo "expected fingerprint must be 64 hex characters" >&2
  exit 1
fi

apksigner="${APKSIGNER:-${ANDROID_HOME:?ANDROID_HOME is not set}/build-tools/37.0.0/apksigner}"

out="$("$apksigner" -J-enable-native-access=ALL-UNNAMED verify -v --print-certs "$apk")"
first="$(printf '%s\n' "$out" | sed -n 1p)"
if [ "$first" != "Verifies" ]; then
  echo "apk does not verify" >&2
  exit 1
fi

signers="$(printf '%s\n' "$out" | sed -n 's/^Number of signers: //p')"
if [ "$signers" != "1" ]; then
  echo "expected exactly one signer, found: ${signers:-none}" >&2
  exit 1
fi

digests="$(printf '%s\n' "$out" | sed -n 's/^.*Signer: certificate SHA-256 digest: //p' | tr 'A-F' 'a-f' | sort -u)"
if [ "$digests" != "$expected" ]; then
  echo "signer fingerprint does not match the expected value" >&2
  exit 1
fi

echo "signature verified: $expected"
