#!/bin/sh
cd "$(dirname "$0")/.." || exit 1
. .githooks/lib.sh

MIN_MISE=2026.10.18
JDK_TOOL='github:adoptium/temurin25-binaries'
GH_STACK_VERSION=v0.2.1

fail() {
  echo "bootstrap: $1" >&2
  exit 1
}

version_at_least() {
  awk -v have="$1" -v want="$2" 'BEGIN {
    n = split(have, h, ".")
    split(want, w, ".")
    for (i = 1; i <= n; i++) {
      if (h[i] + 0 > w[i] + 0) exit 0
      if (h[i] + 0 < w[i] + 0) exit 1
    }
    exit 0
  }'
}

git config core.hooksPath .githooks || fail "could not set core.hooksPath"
echo "core.hooksPath=$(git config core.hooksPath)"
echo "hooks installed"

find_mise || exit 1
mise_version=$("$MISE" --version 2>/dev/null | awk '{print $1; exit}')
version_at_least "$mise_version" "$MIN_MISE" || fail "mise $mise_version is older than $MIN_MISE"
echo "mise $mise_version"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) platform=macos-arm64 api_os=mac api_arch=aarch64 ;;
  Linux-x86_64) platform=linux-x64 api_os=linux api_arch=x64 ;;
  Linux-aarch64 | Linux-arm64) platform=linux-arm64 api_os=linux api_arch=aarch64 ;;
  *) fail "unsupported platform $(uname -s)-$(uname -m)" ;;
esac

release=$(awk -v header="[tools.\"$JDK_TOOL\"]" '$0 == header { inside = 1; next } /^\[/ { inside = 0 } inside && /^version = / { gsub(/version = "|"$/, ""); print; exit }' mise.toml)
[ -n "$release" ] || fail "no Temurin version in mise.toml"
section="[tools.\"$JDK_TOOL\".\"platforms.$platform\"]"
locked=$(grep -F -A2 -- "$section" mise.lock | sed -n 's/^checksum = "sha256:\(.*\)"/\1/p')
asset=$(grep -F -A3 -- "$section" mise.lock | sed -n 's/^url = ".*\/\([^/"]*\)"/\1/p')
[ -n "$locked" ] && [ -n "$asset" ] || fail "mise.lock has no Temurin entry for $platform"
encoded=$(printf '%s' "$release" | sed 's/+/%2B/g')
api="https://api.adoptium.net/v3/assets/release_name/eclipse/$encoded?image_type=jdk&jvm_impl=hotspot&project=jdk&os=$api_os&architecture=$api_arch"
listing=$(curl -fsS --max-time 30 --retry 2 "$api") || fail "could not query the Adoptium API"
published=$(printf '%s\n' "$listing" | grep -F -B1 -- "/$asset.sha256.txt\"" | sed -n 's/^ *"checksum": "\(.*\)",$/\1/p' | head -n 1)
[ -n "$published" ] || fail "the Adoptium API does not list $asset"
[ "$locked" = "$published" ] || fail "Temurin checksum mismatch for $asset: mise.lock $locked, Adoptium $published"
echo "Temurin $asset sha256 $locked matches Adoptium"

"$MISE" install --locked || fail "mise install --locked failed"

sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
if [ -z "$sdk" ] && [ -f local.properties ]; then
  sdk=$(sed -n 's/^sdk\.dir=//p' local.properties | head -n 1)
fi
[ -n "$sdk" ] || sdk="$HOME/Library/Android/sdk"
[ -d "$sdk" ] || fail "Android SDK not found at $sdk"

package_revision() {
  sed -n 's/^Pkg\.Revision=//p' "$sdk/$1/source.properties" 2>/dev/null | head -n 1
}

require_package() {
  revision=$(package_revision "$1")
  [ -n "$revision" ] || fail "missing Android SDK package $1 under $sdk"
  case "$revision" in
    $2) echo "Android SDK $1 revision $revision" ;;
    *) fail "Android SDK package $1 is revision $revision under $sdk, expected $2" ;;
  esac
}

require_package platforms/android-37.0 2
require_package build-tools/37.0.0 37.0.0
require_package cmdline-tools/latest '23.0*'

if "$MISE" exec -- gh extension list | grep -q 'github/gh-stack'; then
  installed=$("$MISE" exec -- gh extension list | awk -F '\t' '$2 == "github/gh-stack" { print $3 }')
  [ "$installed" = "$GH_STACK_VERSION" ] || fail "gh-stack is $installed, expected $GH_STACK_VERSION: run gh extension remove gh-stack and rerun"
  echo "gh-stack $installed already installed"
else
  "$MISE" exec -- gh extension install github/gh-stack --pin "$GH_STACK_VERSION" || fail "could not install gh-stack"
fi
