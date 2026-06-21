#!/usr/bin/env bash
#
# Build the sing-box mobile core (libbox) into android/app/libs/libbox.aar.
#
# Prereqs: Go ≥1.23, Android NDK (matching app build.gradle ndkVersion),
# gomobile. Run from the repo root:  ./scripts/build-libbox.sh
#
set -euo pipefail

# Pin sing-box SOURCE by commit (reproducible input — not the AAR hash).
SING_BOX_VERSION="${SING_BOX_VERSION:-v1.11.15}"   # human-readable label
SING_BOX_COMMIT="${SING_BOX_COMMIT:-bc35aca01704497c179da1a03e45ad8e32f1a51b}"

# Pin gomobile toolchain (avoid @latest drift between machines).
GOMOBILE_VERSION="${GOMOBILE_VERSION:-v0.0.0-20260611195102-4dd8f1dbf5d2}"

JAVA_PKG="io.nekohasekai.libbox"                    # must match Kotlin imports
NDK_VERSION="${NDK_VERSION:-28.2.13676358}"         # match Flutter's default ndkVersion
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/android/app/libs"
WORK="$(mktemp -d)"

ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_SDK/ndk/$NDK_VERSION}"
if [[ ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "Android NDK not found at $ANDROID_NDK_HOME — install NDK $NDK_VERSION in Android Studio SDK Manager."
  exit 1
fi

# Build tags: REALITY client + QUIC (Hysteria2) + uTLS + gvisor tun + wireguard
# endpoint. These mirror the carriers the node serves.
TAGS="with_gvisor,with_quic,with_utls,with_wireguard,with_clash_api"

echo "▸ sing-box $SING_BOX_VERSION ($SING_BOX_COMMIT) → $OUT_DIR/libbox.aar"
echo "▸ gomobile $GOMOBILE_VERSION"

command -v gomobile >/dev/null 2>&1 || {
  echo "installing gomobile $GOMOBILE_VERSION…"
  go install "golang.org/x/mobile/cmd/gomobile@${GOMOBILE_VERSION}"
  go install "golang.org/x/mobile/cmd/gobind@${GOMOBILE_VERSION}"
}

git clone https://github.com/SagerNet/sing-box "$WORK/sing-box"
cd "$WORK/sing-box"
git checkout --quiet "$SING_BOX_COMMIT"
actual="$(git rev-parse HEAD)"
if [[ "$actual" != "$SING_BOX_COMMIT" ]]; then
  echo "✗ sing-box commit mismatch: expected $SING_BOX_COMMIT got $actual"
  exit 1
fi

export PATH="$PATH:$(go env GOPATH)/bin"
# Go 1.24+ requires x/mobile in the module graph before gomobile bind.
go get "golang.org/x/mobile/cmd/gomobile@${GOMOBILE_VERSION}" \
       "golang.org/x/mobile/cmd/gobind@${GOMOBILE_VERSION}"
gomobile init

mkdir -p "$OUT_DIR"
gomobile bind -v \
  -target=android/arm64 \
  -androidapi=21 \
  -javapkg="$JAVA_PKG" \
  -tags="$TAGS" \
  -trimpath -ldflags="-s -w" \
  -o "$OUT_DIR/libbox.aar" \
  ./experimental/libbox

echo "✓ wrote $OUT_DIR/libbox.aar (from sing-box $SING_BOX_COMMIT)"
rm -rf "$WORK"