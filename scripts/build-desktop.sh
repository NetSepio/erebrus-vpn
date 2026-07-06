#!/usr/bin/env bash
#
# Build desktop release bundles and embed the sing-box CLI.
# Usage: ./scripts/build-desktop.sh [macos|windows|linux|all]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

PLATFORM="${1:-macos}"

package_macos() {
  local app
  app="$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' | head -1)"
  if [[ -z "${app}" ]]; then
    echo "✗ macOS .app not found — run flutter build macos first"
    exit 1
  fi
  local tag="${1:-local}"
  mkdir -p dist
  local out="dist/erebrus-vpn-macos-${tag}.zip"
  ditto -c -k --keepParent "${app}" "${out}"
  echo "✓ packaged → ${out}"
}

package_linux() {
  local bundle
  bundle="$(find build/linux -maxdepth 2 -type d -name 'bundle' | head -1)"
  if [[ -z "${bundle}" ]]; then
    echo "✗ linux bundle not found"
    exit 1
  fi
  local tag="${1:-local}"
  mkdir -p dist
  local out="dist/erebrus-vpn-linux-${tag}.tar.gz"
  tar -czf "${out}" -C "$(dirname "${bundle}")" "$(basename "${bundle}")"
  echo "✓ packaged → ${out}"
}

package_windows() {
  local runner_dir="${ROOT_DIR}/build/windows/x64/runner/Release"
  if [[ ! -d "${runner_dir}" ]]; then
    echo "✗ windows Release folder not found"
    exit 1
  fi
  local tag="${1:-local}"
  mkdir -p dist
  # Absolute path — zip resolves relative paths against the cd'd runner dir.
  local out="${ROOT_DIR}/dist/erebrus-vpn-windows-${tag}.zip"
  (cd "${runner_dir}" && zip -qr "${out}" .)
  echo "✓ packaged → dist/erebrus-vpn-windows-${tag}.zip"
}

read_version_tag() {
  local version_line
  version_line="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
  local version_name="${version_line%%+*}"
  echo "v${version_name}"
}

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
  local runner_dir="${ROOT_DIR}/build/windows/x64/runner/Release"
  if [[ ! -d "${runner_dir}" ]]; then
    echo "✗ windows Release folder not found"
    exit 1
  fi
  local src="${ROOT_DIR}/bin/sing-box/windows-amd64/sing-box.exe"
  [[ -f "${src}" ]] || "${SCRIPT_DIR}/fetch-singbox-cli.sh" windows
  install -m 755 "${src}" "${runner_dir}/sing-box.exe"
  echo "✓ embedded sing-box → ${runner_dir}/sing-box.exe"
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
  local tag
  tag="$(read_version_tag)"
  local define_args
  define_args="$(dart_define_args)"
  echo "▸ flutter pub get"
  flutter pub get
  echo "▸ generate desktop brand assets"
  python3 scripts/generate-desktop-assets.py
  echo "▸ flutter build ${p} --release ${define_args}"
  # shellcheck disable=SC2086
  flutter build "${p}" --release ${define_args}
  case "${p}" in
    macos) embed_singbox_macos ;;
    linux) embed_singbox_linux ;;
    windows) embed_singbox_windows ;;
  esac
  case "${p}" in
    macos) package_macos "${tag}" ;;
    linux) package_linux "${tag}" ;;
    windows) package_windows "${tag}" ;;
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