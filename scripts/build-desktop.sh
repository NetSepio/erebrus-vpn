#!/usr/bin/env bash
#
# Build desktop release executables and embed the sing-box CLI.
# Usage: ./scripts/build-desktop.sh [macos|windows|linux|all]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

PLATFORM="${1:-macos}"

embed_singbox_macos() {
  local app
  app="$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' | head -1)"
  if [[ -z "${app}" ]]; then
    echo "✗ macOS .app not found — run flutter build macos first"
    exit 1
  fi
  local arch
  arch="$(uname -m)"
  local src="${ROOT_DIR}/bin/sing-box/darwin-${arch}/sing-box"
  if [[ ! -f "${src}" ]]; then
    echo "▸ sing-box missing for darwin-${arch}, fetching…"
    "${SCRIPT_DIR}/fetch-singbox-cli.sh" macos
  fi
  install -m 755 "${src}" "${app}/Contents/Resources/sing-box"
  echo "✓ embedded sing-box → ${app}/Contents/Resources/sing-box"
  echo "✓ app bundle: ${app}"
}

embed_singbox_linux() {
  local bundle
  bundle="$(find build/linux -maxdepth 2 -type d -name 'bundle' | head -1)"
  if [[ -z "${bundle}" ]]; then
    echo "✗ linux bundle not found"
    exit 1
  fi
  local src="${ROOT_DIR}/bin/sing-box/linux-amd64/sing-box"
  [[ -f "${src}" ]] || "${SCRIPT_DIR}/fetch-singbox-cli.sh" linux
  install -m 755 "${src}" "${bundle}/sing-box"
  echo "✓ embedded sing-box → ${bundle}/sing-box"
}

embed_singbox_windows() {
  local runner
  runner="$(find build/windows -name '*.exe' -path '*/runner/*' | head -1)"
  if [[ -z "${runner}" ]]; then
    runner="$(find build/windows/x64/runner/Release -name '*.exe' | head -1)"
  fi
  if [[ -z "${runner}" ]]; then
    echo "✗ windows exe not found"
    exit 1
  fi
  local dir
  dir="$(dirname "${runner}")"
  local src="${ROOT_DIR}/bin/sing-box/windows-amd64/sing-box.exe"
  [[ -f "${src}" ]] || "${SCRIPT_DIR}/fetch-singbox-cli.sh" windows
  install -m 755 "${src}" "${dir}/sing-box.exe"
  echo "✓ embedded sing-box → ${dir}/sing-box.exe"
}

dart_define_args() {
  if [[ -f "${ROOT_DIR}/.env" ]]; then
    echo "--dart-define-from-file=${ROOT_DIR}/.env"
  else
    echo "⚠ .env missing — cp env.example .env and set REOWN_PROJECT_ID" >&2
  fi
}

build_one() {
  local p="$1"
  local define_args
  define_args="$(dart_define_args)"
  echo "▸ flutter pub get"
  flutter pub get
  echo "▸ flutter build ${p} --release ${define_args}"
  # shellcheck disable=SC2086
  flutter build "${p}" --release ${define_args}
  case "${p}" in
    macos) embed_singbox_macos ;;
    linux) embed_singbox_linux ;;
    windows) embed_singbox_windows ;;
  esac
}

case "${PLATFORM}" in
  macos) build_one macos ;;
  linux) build_one linux ;;
  windows) build_one windows ;;
  all)
    build_one macos
    build_one linux || echo "⚠ linux build skipped (needs Linux host)"
    build_one windows || echo "⚠ windows build skipped (needs Windows host)"
    ;;
  *) echo "usage: $0 [macos|windows|linux|all]"; exit 1 ;;
esac