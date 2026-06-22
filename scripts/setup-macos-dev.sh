#!/usr/bin/env bash
# Fetch sing-box for macOS dev (flutter run -d macos).
# The desktop runner looks in bin/sing-box/darwin-{arch}/sing-box automatically.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"${SCRIPT_DIR}/fetch-singbox-cli.sh" macos
echo ""
echo "✓ sing-box ready. Hot restart the app, then tap Connect."
echo "  Or: export EREBRUS_SINGBOX=\"${SCRIPT_DIR}/../bin/sing-box/darwin-$(uname -m)/sing-box\""