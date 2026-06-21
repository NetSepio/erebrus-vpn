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

> **Heads-up:** the app builds and runs the UI today, but **actually connecting
> to a VPN needs one extra native step** (building the tunnel engine). It's a
> one-time command — see **[docs/BUILD.md](docs/BUILD.md)**.

## Where things live

| Folder | What's inside |
|---|---|
| `lib/view/` | The screens — connect, servers, account, settings |
| `lib/theme/` | Colors, fonts, and reusable UI pieces (the look & feel) |
| `lib/vpn/` | The connection brain — picks the protocol and talks to the tunnel |
| `android/` · `ios/` · `macos/` · `windows/` · `linux/` | Native tunnel + platform shells |
| `lib/platform/` | Desktop menu-bar tray and platform routing |
| `docs/` | Deeper explanations (read these when you want the "how") |

## Learn more

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how the app actually works:
  the single engine, the three protocols, and the stealth trick. Start here to
  understand the codebase.
- **[docs/BUILD.md](docs/BUILD.md)** — full setup, building the native tunnel,
  iOS notes, and troubleshooting.
- **[docs/STEALTH_CLIENT.md](docs/STEALTH_CLIENT.md)** — the exact contract
  between the Flutter code and the native tunnel (for native contributors).

## Status

✅ UI, theming, and the connection logic are in place and tested.
🚧 Next: build the native tunnel engine, then connect it to the Erebrus network
(automatic via the gateway, or by pasting a node's config for quick testing).

Questions or stuck? Open an issue — we'd rather help than have you guess. 💜
