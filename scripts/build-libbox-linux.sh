#!/usr/bin/env bash
#
# Build sing-box libbox for Linux (amd64 + arm64) into
# linux/native/libbox/.
#
# Prereqs: Go ≥1.23, gcc, gomobile.
# Usage: ./scripts/build-libbox-linux.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=libbox-common.sh
source "${SCRIPT_DIR}/libbox-common.sh"

OUT_DIR="${ROOT_DIR}/linux/native/libbox"
WORK="$(mktemp -d)"
JAVA_PKG="io.nekohasekai.libbox"

echo "▸ sing-box ${SING_BOX_VERSION} (${SING_BOX_COMMIT}) → ${OUT_DIR}/"
echo "▸ gomobile ${GOMOBILE_VERSION} · targets linux/amd64 + linux/arm64"

ensure_gomobile
prepare_singbox_source "${WORK}"

mkdir -p "${OUT_DIR}"
gomobile bind -v \
  -target=linux/amd64,linux/arm64 \
  -javapkg="${JAVA_PKG}" \
  -tags="${LIBBOX_TAGS}" \
  -trimpath -ldflags="-s -w" \
  -o "${OUT_DIR}/libbox.so" \
  ./experimental/libbox

echo "✓ wrote ${OUT_DIR}/libbox.so (from sing-box ${SING_BOX_COMMIT})"
rm -rf "${WORK}"