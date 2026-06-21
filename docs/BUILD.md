# Build & run

From "just cloned" to "connected to a VPN", in order.

## 1. Prerequisites

- **Flutter** (stable) — `flutter doctor` should be all green for the platforms
  you target. See https://docs.flutter.dev/get-started/install.
- For Android: Android Studio + an SDK + an arm64 device or emulator.
- For the native tunnel build (step 3): **Go ≥ 1.23** and the **Android NDK**.

## 2. Run the app (UI only)

```bash
flutter pub get
flutter analyze      # expect: No issues found!
flutter test         # expect: All tests passed!
flutter run          # launches on a connected device / emulator
```

At this point the app runs, the screens work, and you can move around. It
**won't actually tunnel traffic yet** — that needs the native engine below.

## 3. Build the native tunnel (`libbox`)

The Android tunnel links sing-box's mobile core, `libbox`
(`io.nekohasekai.libbox.*`). It's a large generated binary, so it isn't checked
in — build it once:

```bash
./scripts/build-libbox.sh
```

This uses `gomobile` to compile sing-box (pinned to a version that matches the
node's carriers) into `android/app/libs/libbox.aar`. After it finishes:

```bash
flutter run            # on an arm64 device — now it can establish a tunnel
```

> The app is restricted to `arm64-v8a` (that's what `libbox.aar` is built for).
> CI should run `build-libbox.sh` and cache the artifact.

## 4. Connect to the network

The app needs a server config (a "credential bundle"). Wire one of:

- **Gateway (production):** set `VpnController.provisioner` to call
  `POST /api/v2/vpn/clients` on the Erebrus gateway and return a
  `CredentialBundle` from the response. This is the path with accounts,
  entitlements, and the server directory.
- **Manual import (testing):** paste a node's `singbox_profile` or its `vless://`
  / `hysteria2://` share URI to connect directly to one node — no gateway needed.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how a bundle becomes a live tunnel.

## iOS

iOS needs a Network Extension target running the same engine:
- Build `Libbox.xcframework` (gomobile `-target=ios`).
- Add a `NEPacketTunnelProvider` extension that starts sing-box with the config.
- Wire `NETunnelProviderManager` + an app group.

The Dart side is identical (same channels). Details in
[STEALTH_CLIENT.md](STEALTH_CLIENT.md).

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `flutter run` fails linking, mentions `libbox` | `libbox.aar` not built — run `./scripts/build-libbox.sh`. |
| Tunnel won't start, "permission" error | The OS VPN consent was declined; the app re-asks on next connect. |
| Builds but only works on some phones | Expected — `arm64-v8a` only. Use an arm64 device/emulator. |
| `reality server is not included` | The `libbox.aar` was built without the REALITY tags — rebuild with the script (tags are set there). |
| App connects then drops on strict Wi-Fi | That's the fallback working — it should re-establish on a stealth carrier; check the mode is **Auto** or **Stealth**. |
