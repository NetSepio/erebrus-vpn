#!/usr/bin/env bash
#
# Build the sing-box mobile core (libbox) into android/app/libs/libbox.aar.
#
# Prereqs: Go ≥1.23, Android NDK (matching app build.gradle ndkVersion),
# gomobile. Run from the repo root:  ./scripts/build-libbox.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=libbox-common.sh
source "${SCRIPT_DIR}/libbox-common.sh"

JAVA_PKG="io.nekohasekai.libbox"                    # must match Kotlin imports
NDK_VERSION="${NDK_VERSION:-28.2.13676358}"         # match Flutter's default ndkVersion
OUT_DIR="${ROOT_DIR}/android/app/libs"
WORK="$(mktemp -d)"

ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_SDK/ndk/$NDK_VERSION}"
if [[ ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "Android NDK not found at $ANDROID_NDK_HOME — install NDK $NDK_VERSION in Android Studio SDK Manager."
  exit 1
fi

echo "▸ sing-box ${SING_BOX_VERSION} (${SING_BOX_COMMIT}) → ${OUT_DIR}/libbox.aar"
echo "▸ gomobile ${GOMOBILE_VERSION}"

ensure_gomobile
prepare_singbox_source "${WORK}"

mkdir -p "$OUT_DIR"
gomobile bind -v \
  -target=android/arm64 \
  -androidapi=21 \
  -javapkg="$JAVA_PKG" \
  -tags="${LIBBOX_TAGS}" \
  -trimpath -ldflags="-s -w" \
  -o "$OUT_DIR/libbox.aar" \
  ./experimental/libbox

echo "✓ wrote $OUT_DIR/libbox.aar (from sing-box $SING_BOX_COMMIT)"
rm -rf "$WORK"