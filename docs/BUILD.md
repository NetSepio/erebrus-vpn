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

The tunnel links sing-box's mobile core, `libbox` (`io.nekohasekai.libbox.*`).
It's a large generated binary, so it isn't checked in — build it once per platform.

All scripts share pinned versions via `scripts/libbox-common.sh`
(`SING_BOX_COMMIT`, `GOMOBILE_VERSION`, `LIBBOX_TAGS`).

| Platform | Script | Output |
|---|---|---|
| Android arm64 | `./scripts/build-libbox.sh` | `android/app/libs/libbox.aar` |
| iOS device + sim | `./scripts/build-libbox-ios.sh` | `ios/Frameworks/Libbox.xcframework` |
| macOS M + Intel | `./scripts/build-libbox-macos.sh` | `macos/Frameworks/Libbox.xcframework` |
| Windows x64 + arm64 | `./scripts/build-libbox-windows.sh` | `windows/native/libbox/libbox.dll` |
| Linux x64 + arm64 | `./scripts/build-libbox-linux.sh` | `linux/native/libbox/libbox.so` |
| All | `./scripts/build-libbox-all.sh` | all of the above |

Android example:

```bash
./scripts/build-libbox.sh
flutter run            # arm64 device — can establish a tunnel
```

> Android is restricted to `arm64-v8a`. CI should run the libbox scripts and
> cache artifacts per platform.

## 4. Connect to the network

The app needs a server config (a "credential bundle"). Wire one of:

- **Gateway (production):** set `VpnController.provisioner` to call
  `POST /api/v2/vpn/clients` on the Erebrus gateway and return a
  `CredentialBundle` from the response. This is the path with accounts,
  entitlements, and the server directory.
- **Manual import (testing):** paste a node's `singbox_profile` or its `vless://`
  / `hysteria2://` share URI to connect directly to one node — no gateway needed.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how a bundle becomes a live tunnel.

## macOS (menu bar + stealth)

```bash
./scripts/build-libbox-macos.sh
flutter run -d macos
```

1. Build `Libbox.xcframework` (see table above).
2. Open `macos/Runner.xcworkspace` in Xcode and add the **ErebrusTunnel**
   Network Extension target (scaffold in `macos/ErebrusTunnel/`).
3. Enable App Group + Network Extension entitlements on app + extension.
4. Embed `Libbox.xcframework` in the extension target.
5. For **tunnel testing**, set Debug entitlements to `Runner/DebugProfile.Tunnel.entitlements`
   in Xcode (requires an Apple Development certificate). Unsigned debug builds use the
   slimmer `DebugProfile.entitlements` so `flutter build macos` works without signing.
6. Notarize for distribution outside the Mac App Store.

Auth on desktop uses **Reown** (wallets + social). Stealth modes use the same
Dart `SingboxConfigBuilder` as mobile.

## Windows / Linux

```bash
./scripts/build-libbox-windows.sh   # or build-libbox-linux.sh
flutter run -d windows                # or -d linux
```

Wire the generated libbox binary into the native `singbox_plugin` (see
`windows/runner/` and `linux/runner/`). Windows uses Wintun; Linux needs TUN
capabilities (`cap_net_admin` or polkit).

## iOS

```bash
./scripts/build-libbox-ios.sh
ruby ./scripts/setup-ios-tunnel.rb   # once — adds ErebrusTunnel target to Xcode
flutter run -d <iphone-device-id>
```

1. Build `Libbox.xcframework` (gomobile `-target=ios`).
2. `setup-ios-tunnel.rb` wires the **ErebrusTunnel** Packet Tunnel extension
   (sources in `ios/ErebrusTunnel/`).
3. Enable **App Groups** + **Network Extensions** on Runner + extension in the
   Apple Developer portal (`group.com.erebrus.vpn`, bundle `com.erebrus.vpn.ErebrusTunnel`).
4. Run on a **physical device** — VPN tunnels do not work in the Simulator.

WireGuard and stealth (VLESS/Hysteria2) use the same Dart `SingboxConfigBuilder` as
Android. Details in [STEALTH_CLIENT.md](STEALTH_CLIENT.md).

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `flutter run` fails linking, mentions `libbox` | `libbox.aar` not built — run `./scripts/build-libbox.sh`. |
| Tunnel won't start, "permission" error | The OS VPN consent was declined; the app re-asks on next connect. |
| Builds but only works on some phones | Expected — `arm64-v8a` only. Use an arm64 device/emulator. |
| `reality server is not included` | The `libbox.aar` was built without the REALITY tags — rebuild with the script (tags are set there). |
| App connects then drops on strict Wi-Fi | That's the fallback working — it should re-establish on a stealth carrier; check the mode is **Auto** or **Stealth**. |
