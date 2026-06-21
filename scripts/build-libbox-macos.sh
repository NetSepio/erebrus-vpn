#!/usr/bin/env bash
#
# Build sing-box libbox for macOS (Apple Silicon + Intel) into
# macos/Frameworks/Libbox.xcframework.
#
# Prereqs: Go ≥1.23, Xcode CLT, gomobile.
# Usage: ./scripts/build-libbox-macos.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=libbox-common.sh
source "${SCRIPT_DIR}/libbox-common.sh"

OUT_DIR="${ROOT_DIR}/macos/Frameworks"
WORK="$(mktemp -d)"
JAVA_PKG="io.nekohasekai.libbox"

echo "▸ sing-box ${SING_BOX_VERSION} (${SING_BOX_COMMIT}) → ${OUT_DIR}/Libbox.xcframework"
echo "▸ gomobile ${GOMOBILE_VERSION} · targets macos/arm64 + macos/amd64"

ensure_gomobile
prepare_singbox_source "${WORK}"

mkdir -p "${OUT_DIR}"
gomobile bind -v \
  -target=macos,macos/arm64,macos/amd64 \
  -javapkg="${JAVA_PKG}" \
  -tags="${LIBBOX_TAGS}" \
  -trimpath -ldflags="-s -w" \
  -o "${OUT_DIR}/Libbox.xcframework" \
  ./experimental/libbox

echo "✓ wrote ${OUT_DIR}/Libbox.xcframework (from sing-box ${SING_BOX_COMMIT})"
rm -rf "${WORK}"