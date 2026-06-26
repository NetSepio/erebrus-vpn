# Platform status

What works today vs what still needs work. Updated 2026-06-26.

## Tunnel & protocols

| Platform | WG + stealth tunnel | How | Blockers |
|---|---|---|---|
| **Android** | Yes | `ErebrusVpnService` + `libbox.aar` | arm64 devices only |
| **iOS** | Yes | `ErebrusTunnel` Network Extension + `Libbox.xcframework` | Physical device; Apple App Group + NE entitlements; `./scripts/build-libbox-ios.sh` |
| **macOS** | Partial | **sing-box CLI** proxy mode via `SingboxDesktopRunner` (Dart — not the native plugin). Signed TUN: NE scaffold only | System-wide VPN needs signed NE + libbox in `macos/ErebrusTunnel/` |
| **Windows** | Partial | Same **sing-box CLI** path as macOS (`SingboxEngine` → `SingboxDesktopRunner`). System proxy via registry on connect | Bundle CLI (`./scripts/build-desktop.sh windows`); tray minimize; libbox TUN optional later |
| **Linux** | Partial | Same **sing-box CLI** path as macOS. System proxy via `gsettings` on connect (GNOME/GTK) | Bundle CLI (`./scripts/build-desktop.sh linux`); tray minimize; KDE/non-GNOME may need extra proxy backend |

Dart config (`SingboxConfigBuilder`), connect fallback (Auto / Stealth / WireGuard), and
stealth readiness probe are shared across **all** platforms. Mobile uses native libbox
via `dev.erebrus/singbox` method channels. **All desktop** (macOS / Windows / Linux) uses
`SingboxDesktopRunner` — a sing-box CLI subprocess — and ignores the C++ plugin stubs.

## Features

| Feature | Android | iOS | macOS | Win/Linux |
|---|---|---|---|---|
| Per-app split tunnel | Yes | No (system-wide NE) | No | No |
| In-app browser via tunnel | WebView → `setAppProxy` | System NE routes all traffic | System proxy on connect | System proxy on connect (Win registry / Linux gsettings) |
| Live RX/TX stats | Yes | Yes (app group) | Yes (Clash API `:9090`) | Yes (Clash API `:9090`) |
| Wallet auth (Reown) | Yes | Yes | Web login | Web login |
| Gateway provisioner | Yes | Yes | Yes (`GatewayController`) | Yes (`GatewayController`) |

## Recently fixed (no longer open)

- Stealth dial log showed wrong port (`:51820`) — `CredentialBundle.dialTarget()` parses carrier URI ports.
- Stealth `router: outbound not found: direct` — `direct` outbound always injected in stealth configs.
- Android disconnect `file already closed` — libbox closed before TUN; benign close handling.
- Stealth reported connected before carrier ready — `_waitStealthReady()` egress probe in `vpn_controller.dart`.
- iOS tunnel was a stub — full `ErebrusTunnel` + `TunnelManager` + libbox v1.11 stack shipped.

## Open work (prod blockers)

### Ship mobile (Android / iOS)

1. **iOS** — App Group + NE entitlements on physical device; `./scripts/build-libbox-ios.sh`.
2. **Android** — arm64 only; Play / dApp Store signing per `scripts/build-android-release.sh`.

### Ship desktop

1. **Windows / Linux QA** — run `./scripts/build-desktop.sh windows|linux`, verify connect, egress probe, and browser egress via system proxy.
2. **Linux KDE / non-GNOME** — optional `kwriteconfig` or `xdg-settings` proxy backend if `gsettings` is unavailable.
3. **macOS Network Extension (optional)** — port `ios/ErebrusTunnel/` libbox into `macos/ErebrusTunnel/` for signed system TUN (see `macos/ErebrusTunnel/README.md`). Unsigned builds already ship via CLI proxy mode.

### Future / optional

1. **Windows / Linux libbox TUN** — `windows/runner/singbox_plugin.cpp` and `linux/runner/singbox_plugin.cc` are stubs (emit `error` on `start`). Only needed for **system-wide TUN** without the CLI; not required for proxy-mode MVP.
2. **iOS per-app rules** — optional; `NEAppRule` / managed-app APIs.
3. **DNS picker in UI** — node DNS vs public resolver (`topology.md` future item).

## Verify stealth vs direct WireGuard

On the node, `wg show` **endpoint** is the reliable check:

- Direct WG: client public IP and UDP port (e.g. `111.65.x.x:3983`).
- Stealth: `127.0.0.1:<local-port>` (carrier dials loopback into WG).