#!/usr/bin/env bash
# Build signed release artifacts for Google Play and Solana dApp Store (erebrus-drop pattern).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f android/key.properties ]]; then
  cat >&2 <<'EOF'
Missing android/key.properties. Generate a keystore per flavor, e.g.:

  keytool -genkey -v -keystore ~/keys/erebrus-playstore.jks \
    -keyalg RSA -keysize 2048 -validity 10000 -alias erebrus

then create android/key.properties with per-flavor prefixes
(fields read by android/app/build.gradle.kts):

  playstore.storeFile=/absolute/path/erebrus-playstore.jks
  playstore.storePassword=...
  playstore.keyAlias=erebrus
  playstore.keyPassword=...
  dappstore.storeFile=...      # same four keys for the dappstore flavor
EOF
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