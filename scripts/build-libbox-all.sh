#!/usr/bin/env bash
#
# Build libbox for every platform gomobile supports.
# Usage: ./scripts/build-libbox-all.sh [android|ios|macos|all]
#
# Windows/Linux have no libbox: gomobile cannot target them, and desktop
# tunnels through the sing-box CLI instead (scripts/fetch-singbox-cli.sh).
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
  ios)     run "iOS device + simulator" build-libbox-ios.sh ;;
  macos)   run "macOS universal" build-libbox-macos.sh ;;
  windows|linux)
    # Delegate so the placeholder prints the full explanation.
    run "${TARGET} (unsupported)" "build-libbox-${TARGET}.sh"
    ;;
  all)
    run "Android arm64" build-libbox.sh
    run "iOS device + simulator" build-libbox-ios.sh
    run "macOS universal" build-libbox-macos.sh
    echo ""
    echo "▸ skipped windows/linux — no gomobile support; desktop uses the sing-box CLI"
    ;;
  *)
    echo "usage: $0 [android|ios|macos|all]"
    exit 1
    ;;
esac

echo ""
echo "✓ libbox build complete (${TARGET})"
