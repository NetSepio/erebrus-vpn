# Platform status

What works today vs what still needs work. Updated 2026-06-26.

## Tunnel & protocols

| Platform | WG + stealth tunnel | How | Blockers |
|---|---|---|---|
| **Android** | Yes | `ErebrusVpnService` + `libbox.aar` | arm64 devices only |
| **iOS** | Yes | `ErebrusTunnel` Network Extension + `Libbox.xcframework` | Physical device; Apple App Group + NE entitlements; `./scripts/build-libbox-ios.sh` |
| **macOS** | Partial | Unsigned: **sing-box CLI** proxy mode (`singbox_desktop_runner`). Signed TUN: NE scaffold only — libbox not wired in `macos/ErebrusTunnel/` | Full system VPN needs signed NE + libbox in extension |
| **Windows** | No | Channel stub → `error` | Wire `windows/runner/singbox_plugin.cpp` to built `libbox.dll` + Wintun |
| **Linux** | No | Channel stub → `error` | Wire `linux/runner/singbox_plugin.cc` to built `libbox.so` + TUN caps |

Dart config (`SingboxConfigBuilder`), connect fallback (Auto / Stealth / WireGuard), and
stealth readiness probe are shared across mobile. Android and iOS use the same method
channels (`dev.erebrus/singbox`).

## Features

| Feature | Android | iOS | macOS | Win/Linux |
|---|---|---|---|---|
| Per-app split tunnel | Yes | No (system-wide NE) | No | No |
| In-app browser via tunnel | WebView → local proxy | System NE routes WebView | System proxy (CLI) | — |
| Live RX/TX stats | Yes | Yes (app group) | CLI log / partial | — |
| Wallet auth (Reown) | Yes | Yes | Web login | Web login |

## Recently fixed (no longer open)

- Stealth dial log showed wrong port (`:51820`) — `CredentialBundle.dialTarget()` parses carrier URI ports.
- Stealth `router: outbound not found: direct` — `direct` outbound always injected in stealth configs.
- Android disconnect `file already closed` — libbox closed before TUN; benign close handling.
- Stealth reported connected before carrier ready — `_waitStealthReady()` egress probe in `vpn_controller.dart`.
- iOS tunnel was a stub — full `ErebrusTunnel` + `TunnelManager` + libbox v1.11 stack shipped.

## Open work

1. **macOS Network Extension** — port `ios/ErebrusTunnel/` libbox integration into `macos/ErebrusTunnel/`, add Xcode target (see `macos/ErebrusTunnel/README.md`).
2. **Windows / Linux native plugin** — link built libbox; implement TUN (Wintun / `cap_net_admin`).
3. **iOS per-app rules** — optional; needs `NEAppRule` / managed-app APIs (different from Android split tunnel).
4. **DNS picker in UI** — node DNS vs public resolver (`topology.md` future item).
5. **Gateway provisioner in app** — hook `VpnController.provisioner` to production gateway (manual import works for testing).

## Verify stealth vs direct WireGuard

On the node, `wg show` **endpoint** is the reliable check:

- Direct WG: client public IP and UDP port (e.g. `111.65.x.x:3983`).
- Stealth: `127.0.0.1:<local-port>` (carrier dials loopback into WG).