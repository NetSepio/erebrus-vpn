#!/usr/bin/env bash
#
# PLACEHOLDER — libbox for Linux cannot be built with gomobile.
#
# `gomobile bind` only supports android/ios/iossimulator/macos/maccatalyst:
#   $ gomobile bind -target=linux/amd64
#   gomobile: invalid -target="linux/amd64": unsupported platform: "linux"
#
# Linux desktop doesn't need this today: the app tunnels through the sing-box
# CLI (scripts/fetch-singbox-cli.sh + SingboxDesktopRunner). A native libbox
# path would mean `go build -buildmode=c-shared` against a hand-written cgo
# export shim (sing-box has no c-shared entry point) plus a TUN implementation
# with cap_net_admin — tracked as future work in docs/BUILD.md.
#
set -euo pipefail

echo "✗ build-libbox-linux.sh is a placeholder — gomobile cannot target linux." >&2
echo "  Use the sing-box CLI instead: ./scripts/fetch-singbox-cli.sh linux" >&2
exit 1
