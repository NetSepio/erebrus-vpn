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

At this point the UI runs on every platform. **Tunnel traffic** needs the native
engine below (Android/iOS/macOS: libbox; Windows/Linux: sing-box CLI).
See [STATUS.md](STATUS.md) for platform-specific tunnel and proxy differences.

The canonical application version is the `version:` field in `pubspec.yaml`.
Flutter maps `1.0.3+4` to Apple version `1.0.3` build `4`, and Android
`versionName=1.0.3` / `versionCode=4`.

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
| All of the above | `./scripts/build-libbox-all.sh` | Android + iOS + macOS |

Windows and Linux have **no libbox** — `gomobile bind` only targets
android/ios/macos. Those platforms tunnel through the sing-box CLI instead
(`./scripts/fetch-singbox-cli.sh`); the `build-libbox-{windows,linux}.sh`
scripts are fail-fast placeholders that explain this.

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

## macOS (App Sandbox + Network Extension)

```bash
./scripts/build-libbox-macos.sh
ruby ./scripts/setup-macos-tunnel.rb
flutter run -d macos
```

macOS uses the sandboxed **ErebrusTunnel Packet Tunnel Provider**. The extension
runs libbox and supports WireGuard, VLESS + REALITY, and Hysteria2 with the same
configuration and fallback path as iOS. The OS routes the in-app browser and
other apps through the full-device tunnel; `networksetup`, administrator
elevation, and a separate sing-box executable are not used.

Auth on desktop uses **web login** (not Reown). Stealth configs use the same Dart
`SingboxConfigBuilder` as mobile. Guest configuration import on desktop uses
the file picker only; camera scanning and camera entitlements are intentionally
excluded from every desktop build.

## Windows / Linux

Windows/Linux tunneling uses the **sing-box CLI**, not the
C++ `singbox_plugin` stubs in `windows/runner/` and `linux/runner/`.

```bash
./scripts/fetch-singbox-cli.sh windows   # or linux
flutter run -d windows                   # or -d linux
# release + embed CLI:
./scripts/build-desktop.sh windows       # or linux
```

**What works today:** connect / disconnect, Auto / Stealth / WireGuard, egress
probe, live stats (Clash API), web wallet login, gateway node list + provision.

**System proxy:** On connect, `DesktopSystemProxy` routes HTTP/HTTPS/SOCKS through
`127.0.0.1:10808` (Windows: registry, Linux: `gsettings`).
The in-app browser and system browsers use the tunnel while connected. Close the
window to **minimize to tray**; use tray → Quit to exit fully.

**Optional later:** system-wide VPN without the CLI would need a `go build
-buildmode=c-shared` libbox shim (gomobile cannot target Windows/Linux) plus
Wintun / `cap_net_admin` TUN wiring in `singbox_plugin`. Not required for the
proxy-mode MVP.

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

## Release builds

Run analysis and tests before producing store artifacts:

```bash
flutter pub get
flutter analyze
flutter test
```

### Android stores

Configure the two signing blocks in `android/key.properties`, then run:

```bash
./scripts/build-android-release.sh all
```

Outputs:

- Google Play:
  `build/app/outputs/bundle/playstoreRelease/app-playstore-release.aab`
- Solana dApp Store:
  `build/app/outputs/flutter-apk/app-dappstore-release.apk`

Android releases are intentionally `arm64-v8a` only because the bundled
sing-box VPN core is ARM64-only. Do not publish ARMv7 or x86 variants without a
matching `libgojni.so`.

### iOS / TestFlight

```bash
./scripts/build-libbox-ios.sh
flutter build ipa --release
```

The App Store IPA is written under `build/ios/ipa/`. Verify that both
`Runner.app` and `ErebrusTunnel.appex` report the version and build from
`pubspec.yaml` before uploading with Transporter.

### macOS

```bash
./scripts/build-libbox-macos.sh
ruby ./scripts/setup-macos-tunnel.rb
flutter build macos --release
open macos/Runner.xcworkspace
```

For Mac App Store delivery, choose **Runner** and **Any Mac**, then Product →
Archive → Distribute App → App Store Connect. Both `Runner` and
`ErebrusTunnel` need App Store provisioning profiles with App Groups and
Network Extensions enabled. `./scripts/build-desktop.sh macos` remains a
convenient local ZIP builder; the Organizer archive is the store artifact.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `flutter run` fails linking, mentions `libbox` | `libbox.aar` not built — run `./scripts/build-libbox.sh`. |
| Tunnel won't start, "permission" error | The OS VPN consent was declined; the app re-asks on next connect. |
| Builds but only works on some phones | Expected — `arm64-v8a` only. Use an arm64 device/emulator. |
| `reality server is not included` | The `libbox.aar` was built without the REALITY tags — rebuild with the script (tags are set there). |
| App connects then drops on strict Wi-Fi | That's the fallback working — it should re-establish on a stealth carrier; check the mode is **Auto** or **Stealth**. |
| iOS connects then immediate error | Build libbox + run on a **physical device**; enable App Group + NE in Apple Developer portal. |
| macOS cannot create the VPN profile | Enable App Groups + Network Extensions for both macOS identifiers and refresh their provisioning profiles. |
| Stealth shows connected but no egress | Wait for stealth readiness probe; on node check `wg show` endpoint is `127.0.0.1:…` not the client IP. |
