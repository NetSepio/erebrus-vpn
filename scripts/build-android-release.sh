#!/usr/bin/env bash
# Build signed release artifacts for Google Play and Solana dApp Store (erebrus-drop pattern).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f android/key.properties ]]; then
  echo "Missing android/key.properties — run ./scripts/create-android-release-keystore.sh first."
  exit 1
fi

if [[ ! -f android/app/libs/libbox.aar ]]; then
  echo "Building libbox.aar…"
  ./scripts/build-libbox.sh
fi

FLAVOR="${1:-all}"

build_playstore() {
  echo "==> Google Play (playstoreRelease AAB)"
  flutter build appbundle --flavor playstore --release
  echo "    build/app/outputs/bundle/playstoreRelease/app-playstore-release.aab"
}

build_dappstore() {
  echo "==> Solana dApp Store (dappstoreRelease APK)"
  flutter build apk --flavor dappstore --release
  echo "    build/app/outputs/flutter-apk/app-dappstore-release.apk"
}

case "$FLAVOR" in
  playstore) build_playstore ;;
  dappstore) build_dappstore ;;
  all)
    build_playstore
    build_dappstore
    ;;
  *)
    echo "Usage: $0 [playstore|dappstore|all]"
    exit 1
    ;;
esac

echo "Done."