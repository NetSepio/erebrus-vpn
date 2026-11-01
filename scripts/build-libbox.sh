#!/usr/bin/env bash
#
# Build the sing-box mobile core (libbox) into android/app/libs/libbox.aar.
#
# Prereqs: Go 1.23–1.26 (1.27 cannot link sing-box v1.11.15), Android NDK
# (matching app build.gradle ndkVersion), gomobile. Run from the repo root:
#   ./scripts/build-libbox.sh
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

# A //go:linkname the toolchain cannot resolve (sing-box v1.11 with Go 1.27) is
# left as an undefined dynamic symbol, and only fails when Android loads it.
unzip -p "$OUT_DIR/libbox.aar" jni/arm64-v8a/libgojni.so > "$WORK/libgojni.so"
NM="$(echo "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/bin/llvm-nm)"
unresolved="$("$NM" -D -u "$WORK/libgojni.so" | grep -vE ' U [A-Za-z_][A-Za-z0-9_]*(@.*)?$' || true)"
if [[ -n "$unresolved" ]]; then
  echo "✗ libgojni.so has unresolved Go symbols (built with $(go env GOVERSION)):"
  echo "$unresolved"
  rm -f "$OUT_DIR/libbox.aar"
  exit 1
fi

echo "✓ wrote $OUT_DIR/libbox.aar (from sing-box $SING_BOX_COMMIT)"
rm -rf "$WORK"