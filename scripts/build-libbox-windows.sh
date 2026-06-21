#!/usr/bin/env bash
#
# Build sing-box libbox for Windows (amd64 + arm64) into
# windows/native/libbox/.
#
# Prereqs: Go ≥1.23, MinGW-w64 (for cgo on cross-build) or run on Windows.
# Usage: ./scripts/build-libbox-windows.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=libbox-common.sh
source "${SCRIPT_DIR}/libbox-common.sh"

OUT_DIR="${ROOT_DIR}/windows/native/libbox"
WORK="$(mktemp -d)"
JAVA_PKG="io.nekohasekai.libbox"

echo "▸ sing-box ${SING_BOX_VERSION} (${SING_BOX_COMMIT}) → ${OUT_DIR}/"
echo "▸ gomobile ${GOMOBILE_VERSION} · targets windows/amd64 + windows/arm64"

ensure_gomobile
prepare_singbox_source "${WORK}"

mkdir -p "${OUT_DIR}"
gomobile bind -v \
  -target=windows/amd64,windows/arm64 \
  -javapkg="${JAVA_PKG}" \
  -tags="${LIBBOX_TAGS}" \
  -trimpath -ldflags="-s -w" \
  -o "${OUT_DIR}/libbox.dll" \
  ./experimental/libbox

echo "✓ wrote ${OUT_DIR}/libbox.dll (from sing-box ${SING_BOX_COMMIT})"
rm -rf "${WORK}"