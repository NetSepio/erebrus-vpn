#!/usr/bin/env bash
#
# Build the sing-box mobile core (libbox) into android/app/libs/libbox.aar.
#
# Prereqs: Go ≥1.23, Android NDK (matching app build.gradle ndkVersion),
# gomobile. Run from the repo root:  ./scripts/build-libbox.sh
#
set -euo pipefail

SING_BOX_VERSION="${SING_BOX_VERSION:-v1.11.15}"   # pin to match the node's sing-box
JAVA_PKG="io.nekohasekai.libbox"                    # must match Kotlin imports
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/android/app/libs"
WORK="$(mktemp -d)"

# Build tags: REALITY client + QUIC (Hysteria2) + uTLS + gvisor tun + wireguard
# endpoint. These mirror the carriers the node serves.
TAGS="with_gvisor,with_quic,with_utls,with_wireguard,with_clash_api"

echo "▸ sing-box $SING_BOX_VERSION → $OUT_DIR/libbox.aar"
command -v gomobile >/dev/null 2>&1 || {
  echo "installing gomobile…"
  go install golang.org/x/mobile/cmd/gomobile@latest
  go install golang.org/x/mobile/cmd/gobind@latest
}

git clone --depth 1 -b "$SING_BOX_VERSION" https://github.com/SagerNet/sing-box "$WORK/sing-box"
cd "$WORK/sing-box"

export PATH="$PATH:$(go env GOPATH)/bin"
gomobile init

mkdir -p "$OUT_DIR"
gomobile bind -v \
  -target=android/arm64 \
  -javapkg="$JAVA_PKG" \
  -tags="$TAGS" \
  -trimpath -ldflags="-s -w" \
  -o "$OUT_DIR/libbox.aar" \
  ./experimental/libbox

echo "✓ wrote $OUT_DIR/libbox.aar"
rm -rf "$WORK"
