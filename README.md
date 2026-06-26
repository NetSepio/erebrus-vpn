# Erebrus VPN

**Your internet, kept private — even when networks try to block you.**

Erebrus is a privacy-first VPN built for the Erebrus network. Sign in with your
crypto wallet (no passwords, no email), pick a server, and browse with a built-in
private browser — all in one app.

Most VPNs stop working the moment a network decides to block them. Erebrus doesn't.
When the normal connection is blocked, it quietly **disguises your traffic as
everyday internet** (regular HTTPS or video-call traffic) so you stay connected —
without you having to fiddle with settings.

---

## Why people use it

- **Actually stays connected** — auto-fallback to stealth mode on strict networks
- **Wallet sign-in** — your wallet is your account; no passwords to remember
- **Private browser built in** — browse through the tunnel without switching apps
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
| **Android (Solana Mobile)** | Solana dApp Store — Seeker / Saga |
| **Android (general)** | [GitHub Releases](https://github.com/NetSepio/erebrus-vpn/releases) (sideload APKs from CI) |
| **iOS** | TestFlight / App Store (see [docs/BUILD.md](docs/BUILD.md)) |
| **Desktop** | Build from source — [docs/BUILD.md](docs/BUILD.md) |

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
- **Desktop:** `./scripts/fetch-singbox-cli.sh` then `./scripts/build-desktop.sh`

Full setup, signing, and troubleshooting → **[docs/BUILD.md](docs/BUILD.md)**

| Topic | Doc |
|-------|-----|
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
