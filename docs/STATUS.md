# Platform status

What works today vs what still needs work. Updated 2026-07-25.

## Tunnel & protocols

| Platform | WG + stealth tunnel | How | Blockers |
|---|---|---|---|
| **Android** | Yes | `ErebrusVpnService` + `libbox.aar` | arm64 devices only |
| **iOS** | Yes | `ErebrusTunnel` Network Extension + `Libbox.xcframework` | Physical device; Apple App Group + NE entitlements; `./scripts/build-libbox-ios.sh` |
| **macOS** | Yes | `ErebrusTunnel` Network Extension + universal `Libbox.xcframework` | Apple App Group + NE entitlements; `./scripts/build-libbox-macos.sh` |
| **Windows** | Partial | **sing-box CLI** via `SingboxDesktopRunner`. System proxy via registry on connect | Bundle CLI (`./scripts/build-desktop.sh windows`); tray minimize; libbox TUN optional later |
| **Linux** | Partial | **sing-box CLI** via `SingboxDesktopRunner`. System proxy via `gsettings` on connect (GNOME/GTK) | Bundle CLI (`./scripts/build-desktop.sh linux`); tray minimize; KDE/non-GNOME may need extra proxy backend |

Dart config (`SingboxConfigBuilder`), connect fallback (Auto / Stealth / WireGuard), and
stealth readiness probe are shared across **all** platforms. Android, iOS, and
macOS use native libbox via `dev.erebrus/singbox`; Windows and Linux use
`SingboxDesktopRunner`.

## Features

| Feature | Android | iOS | macOS | Win/Linux |
|---|---|---|---|---|
| Per-app split tunnel | Yes | No (system-wide NE) | No | No |
| In-app browser via tunnel | WebView → `setAppProxy` | System NE routes all traffic | System NE routes all traffic | System proxy on connect (Win registry / Linux gsettings) |
| Live RX/TX stats | Yes | Yes (app group) | Yes (app group) | Yes (Clash API `:9090`) |
| Account auth | Google / Reown / Solana MWA | Apple / Google / Reown | Apple + browser/token | Browser/token |
| Gateway provisioner | Yes | Yes | Yes (`GatewayController`) | Yes (`GatewayController`) |
| Public + org nodes | Yes | Yes | Yes | Yes |
| Org switcher | Yes | Yes | Yes | Yes |
| Active transport diagnostics | Yes | Yes | Yes | Yes |
| Brave Search + network tools | Yes | Yes | Yes | Yes |
| Config import | File + QR camera | File + QR camera | File only | File only |

Desktop builds intentionally omit the QR-camera scanner and camera permissions.
Users can import `.conf`, `.json`, or `.txt` configurations with the file
picker instead.

## Recently fixed (no longer open)

- Stealth dial log showed wrong port (`:51820`) — `CredentialBundle.dialTarget()` parses carrier URI ports.
- Stealth `router: outbound not found: direct` — `direct` outbound always injected in stealth configs.
- Android disconnect `file already closed` — libbox closed before TUN; benign close handling.
- Stealth reported connected before carrier ready — `_waitStealthReady()` egress probe in `vpn_controller.dart`.
- iOS tunnel was a stub — full `ErebrusTunnel` + `TunnelManager` + libbox v1.11 stack shipped.
- iOS status events dispatched off Flutter's platform thread — native events now
  return on the main thread.
- Repeated egress probes and gateway refreshes could overlap and exhaust memory
  — work is deduplicated and bounded.
- Android release bundles advertised incomplete non-ARM64 variants — final
  packaging now ships only `arm64-v8a`, matching the VPN core.
- Browser quick actions were placeholders — Brave Search and six network tools
  now navigate in the active private-browser tab.

## Open work (prod blockers)

### Ship mobile (Android / iOS)

1. **iOS** — keep App Group + NE entitlements and distribution profiles valid;
   test each archive on TestFlight.
2. **Android** — ARM64-only Play / dApp Store signing per
   `scripts/build-android-release.sh`.

### Ship desktop

1. **Windows / Linux QA** — run `./scripts/build-desktop.sh windows|linux`, verify connect, egress probe, and browser egress via system proxy.
2. **Linux KDE / non-GNOME** — optional `kwriteconfig` or `xdg-settings` proxy backend if `gsettings` is unavailable.
3. **macOS App Store** — enable App Groups and Network Extensions on both
   identifiers, refresh App Store provisioning, archive, and test WG,
   VLESS/REALITY, and Hysteria2 through TestFlight.

### Future / optional

1. **Windows / Linux libbox TUN** — `windows/runner/singbox_plugin.cpp` and `linux/runner/singbox_plugin.cc` are stubs (emit `error` on `start`). Only needed for **system-wide TUN** without the CLI; not required for proxy-mode MVP.
2. **iOS per-app rules** — optional; `NEAppRule` / managed-app APIs.
3. **DNS picker in UI** — node DNS vs public resolver (`topology.md` future item).

## Verify stealth vs direct WireGuard

On the node, `wg show` **endpoint** is the reliable check:

- Direct WG: client public IP and UDP port (e.g. `111.65.x.x:3983`).
- Stealth: `127.0.0.1:<local-port>` (carrier dials loopback into WG).
