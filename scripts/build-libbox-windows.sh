#!/usr/bin/env bash
#
# PLACEHOLDER — libbox for Windows cannot be built with gomobile.
#
# `gomobile bind` only supports android/ios/iossimulator/macos/maccatalyst:
#   $ gomobile bind -target=windows/amd64
#   gomobile: invalid -target="windows/amd64": unsupported platform: "windows"
#
# Windows desktop doesn't need this today: the app tunnels through the sing-box
# CLI (scripts/fetch-singbox-cli.sh + SingboxDesktopRunner). A native libbox
# path would mean `go build -buildmode=c-shared` against a hand-written cgo
# export shim (sing-box has no c-shared entry point) plus Wintun integration —
# tracked as future work in docs/BUILD.md.
#
set -euo pipefail

echo "✗ build-libbox-windows.sh is a placeholder — gomobile cannot target windows." >&2
echo "  Use the sing-box CLI instead: ./scripts/fetch-singbox-cli.sh windows" >&2
exit 1
