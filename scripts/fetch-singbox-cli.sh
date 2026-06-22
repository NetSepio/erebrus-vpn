#!/usr/bin/env bash
#
# Download sing-box CLI binaries for desktop packaging.
# Usage:
#   ./scripts/fetch-singbox-cli.sh           # current host arch
#   ./scripts/fetch-singbox-cli.sh all       # macOS arm64+amd64, linux, windows
#   ./scripts/fetch-singbox-cli.sh macos
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=libbox-common.sh
source "${SCRIPT_DIR}/libbox-common.sh"

BIN_ROOT="${ROOT_DIR}/bin/sing-box"
VERSION="${SING_BOX_VERSION#v}"

fetch_one() {
  local os="$1" arch="$2" dest_name="$3"
  local asset="sing-box-${VERSION}-${os}-${arch}"
  local dest="${BIN_ROOT}/${dest_name}"
  mkdir -p "$(dirname "${dest}")"
  echo "▸ fetching ${asset}…"
  local work
  work="$(mktemp -d)"
  local bin
  if [[ "${os}" == "windows" ]]; then
    local url="https://github.com/SagerNet/sing-box/releases/download/${SING_BOX_VERSION}/${asset}.zip"
    curl -fsSL "${url}" -o "${work}/${asset}.zip"
    unzip -q "${work}/${asset}.zip" -d "${work}"
    bin="${work}/${asset}/sing-box.exe"
    dest="${dest}.exe"
  else
    local url="https://github.com/SagerNet/sing-box/releases/download/${SING_BOX_VERSION}/${asset}.tar.gz"
    curl -fsSL "${url}" | tar -xz -C "${work}"
    bin="${work}/${asset}/sing-box"
  fi
  install -m 755 "${bin}" "${dest}"
  rm -rf "${work}"
  echo "✓ ${dest}"
}

case "${1:-host}" in
  all)
    fetch_one darwin arm64 "darwin-arm64/sing-box"
    fetch_one darwin amd64 "darwin-amd64/sing-box"
    fetch_one linux amd64 "linux-amd64/sing-box"
    fetch_one windows amd64 "windows-amd64/sing-box"
    ;;
  macos|darwin)
    if [[ "$(uname -m)" == "arm64" ]]; then
      fetch_one darwin arm64 "darwin-arm64/sing-box"
    else
      fetch_one darwin amd64 "darwin-amd64/sing-box"
    fi
    ;;
  linux)
    fetch_one linux amd64 "linux-amd64/sing-box"
    ;;
  windows)
    fetch_one windows amd64 "windows-amd64/sing-box"
    ;;
  host|*)
    case "$(uname -s)" in
      Darwin)
        if [[ "$(uname -m)" == "arm64" ]]; then
          fetch_one darwin arm64 "darwin-arm64/sing-box"
        else
          fetch_one darwin amd64 "darwin-amd64/sing-box"
        fi
        ;;
      Linux) fetch_one linux amd64 "linux-amd64/sing-box" ;;
      MINGW*|MSYS*|CYGWIN*) fetch_one windows amd64 "windows-amd64/sing-box" ;;
      *) echo "unsupported host OS"; exit 1 ;;
    esac
    ;;
esac