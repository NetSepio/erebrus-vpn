# Erebrus VPN 🛡️

A premium, privacy-first VPN app for the Erebrus network — built with Flutter,
ships as `com.erebrus.vpn`.

Most VPNs stop working the moment a network decides to block them. Erebrus
doesn't. When the normal connection is blocked, it quietly **disguises your
traffic as everyday internet** (regular HTTPS / video-call traffic) so you stay
connected — without you having to do anything.

```
 Auto      → tries the fast path, falls back to stealth automatically
 Stealth   → always disguised (best on strict networks)
 WireGuard → classic, fastest, most detectable
```

## Run it locally

You'll need [Flutter](https://docs.flutter.dev/get-started/install) installed.
Then:

```bash
flutter pub get      # fetch dependencies
flutter analyze      # check the code (should say "No issues found!")
flutter test         # run the tests (should pass)
flutter run          # launch on a connected device or emulator
```

> **Heads-up:** Android and iOS need a one-time **libbox** build before the tunnel
> works (`./scripts/build-libbox.sh` or `build-libbox-ios.sh`). See
> **[docs/BUILD.md](docs/BUILD.md)**. macOS uses the sing-box CLI for unsigned dev;
> Windows/Linux tunnel plugins are not wired yet — see **[docs/STATUS.md](docs/STATUS.md)**.

## Where things live

| Folder | What's inside |
|---|---|
| `lib/view/` | The screens — connect, servers, account, settings |
| `lib/theme/` | Colors, fonts, and reusable UI pieces (the look & feel) |
| `lib/vpn/` | The connection brain — picks the protocol and talks to the tunnel |
| `android/` · `ios/` · `macos/` · `windows/` · `linux/` | Native tunnel + platform shells |
| `lib/platform/` | Desktop menu-bar tray and platform routing |
| `docs/` | Deeper explanations — start with [STATUS.md](docs/STATUS.md) for platform parity |

## Learn more

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how the app actually works:
  the single engine, the three protocols, and the stealth trick. Start here to
  understand the codebase.
- **[docs/BUILD.md](docs/BUILD.md)** — full setup, building the native tunnel,
  iOS notes, and troubleshooting.
- **[docs/STEALTH_CLIENT.md](docs/STEALTH_CLIENT.md)** — the exact contract
  between the Flutter code and the native tunnel (for native contributors).
- **[docs/STATUS.md](docs/STATUS.md)** — platform parity: what ships vs what's left.

## Status

✅ **Android & iOS** — full libbox tunnel (WireGuard + stealth carriers), tested on device.
✅ **macOS** — connect via sing-box CLI (proxy mode); signed system TUN still TODO.
🚧 **Windows / Linux** — UI runs; native tunnel plugin not linked yet.
🚧 **Production gateway** — manual credential import works; wire `VpnController.provisioner` for live accounts.

See **[docs/STATUS.md](docs/STATUS.md)** for the full matrix.

Questions or stuck? Open an issue — we'd rather help than have you guess. 💜
