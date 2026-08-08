# Erebrus VPN

**Your internet, kept private — even when networks try to block you.**

Erebrus is a privacy-first VPN built for the Erebrus network. Sign in with
email, a wallet, Google, Apple, or the browser flow available on your platform;
choose a public or organization node; and browse with a built-in private
browser — all in one app.

Most VPNs stop working the moment a network decides to block them. Erebrus doesn't.
When the normal connection is blocked, it quietly **disguises your traffic as
everyday internet** (regular HTTPS or video-call traffic) so you stay connected —
without you having to fiddle with settings.

---

## Why people use it

- **Actually stays connected** — auto-fallback to stealth mode on strict networks
- **Flexible sign-in** — wallet, Google, Apple, browser, and token flows where supported
- **Organization nodes** — switch organizations and connect to their public or private nodes
- **Private browser built in** — Brave Search plus speed, IP, DNS, WebRTC, and IPv6 tools
- **Clear diagnostics** — see whether WireGuard, VLESS + REALITY, or Hysteria2 is active
- **Easy config import** — file import everywhere, plus QR scanning on Android and iOS
- **Works on phone and desktop** — Android, iOS, macOS, Windows, and Linux

---

## Connection modes (plain English)

| Mode | Best for |
|------|----------|
| **Auto** | Everyday use — fast when possible, stealth when needed |
| **Stealth** | Strict networks — always disguised |
| **WireGuard** | Speed on open networks — classic VPN style |

**Auto** is the default and handles the rest.

---

## Get the app

| Platform | Where |
|----------|--------|
| **Android (Solana Mobile)** | [Solana dApp Store](https://dappstore.solanamobile.com) — Seeker / Saga |
| **Android (Google Play)** | Google Play release channel |
| **Android (sideload)** | [GitHub Releases](https://github.com/NetSepio/erebrus-vpn/releases) (APKs from CI) |
| **iOS** | TestFlight / App Store (see [docs/BUILD.md](docs/BUILD.md)) |
| **Desktop** | Build from source — [docs/BUILD.md](docs/BUILD.md) |

Current source version: **1.0.4+5**. See [CHANGELOG.md](CHANGELOG.md) for release notes.

---

## For developers

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

**First-time native tunnel setup**

- **Android / iOS:** `./scripts/build-libbox.sh` (or `build-libbox-ios.sh`)
- **macOS:** `./scripts/build-libbox-macos.sh`, then `ruby ./scripts/setup-macos-tunnel.rb`
- **Windows / Linux:** `./scripts/fetch-singbox-cli.sh`, then `./scripts/build-desktop.sh`

**Release artifacts (this machine):** `./scripts/build-all-release.sh` →
`dist/ErebrusVPN-<platform>-vX.X.X.*` (Play AAB, dApp APK, iOS IPA, macOS, desktop).

Full setup, signing, and troubleshooting → **[docs/BUILD.md](docs/BUILD.md)**

| Topic | Doc |
|-------|-----|
| Release notes | [CHANGELOG.md](CHANGELOG.md) |
| Platform status | [docs/STATUS.md](docs/STATUS.md) |
| How the app works | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Native tunnel contract | [docs/STEALTH_CLIENT.md](docs/STEALTH_CLIENT.md) |

**CI:** Every push to `main` runs analyze + tests. **Releases:** trigger the
`Release` workflow manually in GitHub Actions for sideload APKs.

---

## Project layout

| Folder | What's inside |
|--------|----------------|
| `lib/view/` | Screens — connect, browser, settings |
| `lib/vpn/` | Tunnel logic and gateway |
| `lib/platform/` | Desktop tray, system proxy, platform routing |
| `android/` · `ios/` · `macos/` · `windows/` · `linux/` | Native shells |

---

Questions or stuck? [Open an issue](https://github.com/NetSepio/erebrus-vpn/issues) — we'd rather help than have you guess.
