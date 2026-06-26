#!/usr/bin/env bash
#
# Build sing-box libbox for iOS (device + simulator) into
# ios/Frameworks/Libbox.xcframework.
#
# Prereqs: Go ≥1.23, Xcode CLT, gomobile.
# Usage: ./scripts/build-libbox-ios.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=libbox-common.sh
source "${SCRIPT_DIR}/libbox-common.sh"

OUT_DIR="${ROOT_DIR}/ios/Frameworks"
WORK="$(mktemp -d)"

echo "▸ sing-box ${SING_BOX_VERSION} (${SING_BOX_COMMIT}) → ${OUT_DIR}/Libbox.xcframework"
echo "▸ gomobile ${GOMOBILE_VERSION} · target ios"

ensure_gomobile
prepare_singbox_source "${WORK}"

mkdir -p "${OUT_DIR}"
gomobile bind -v \
  -target=ios \
  -tags="${LIBBOX_TAGS}" \
  -trimpath -ldflags="-s -w" \
  -o "${OUT_DIR}/Libbox.xcframework" \
  ./experimental/libbox

echo "✓ wrote ${OUT_DIR}/Libbox.xcframework (from sing-box ${SING_BOX_COMMIT})"
rm -rf "${WORK}"