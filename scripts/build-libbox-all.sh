#!/usr/bin/env bash
#
# Build libbox for every supported platform.
# Usage: ./scripts/build-libbox-all.sh [android|macos|windows|linux|all]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-all}"

run() {
  echo ""
  echo "════════════════════════════════════════"
  echo "  $1"
  echo "════════════════════════════════════════"
  "${SCRIPT_DIR}/$2"
}

case "${TARGET}" in
  android) run "Android arm64" build-libbox.sh ;;
  macos)   run "macOS universal" build-libbox-macos.sh ;;
  windows) run "Windows amd64+arm64" build-libbox-windows.sh ;;
  linux)   run "Linux amd64+arm64" build-libbox-linux.sh ;;
  all)
    run "Android arm64" build-libbox.sh
    run "macOS universal" build-libbox-macos.sh
    run "Windows amd64+arm64" build-libbox-windows.sh
    run "Linux amd64+arm64" build-libbox-linux.sh
    ;;
  *)
    echo "usage: $0 [android|macos|windows|linux|all]"
    exit 1
    ;;
esac

echo ""
echo "✓ libbox build complete (${TARGET})"