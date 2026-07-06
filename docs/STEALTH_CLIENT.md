# Erebrus app — unified sing-box engine (stealth + WireGuard)

The app drives **one** engine for every protocol: sing-box's mobile library
(`libbox`). WireGuard is not a separate plugin anymore — it is an *endpoint
inside the sing-box config* we hand the engine. The legacy `wireguard_flutter`
path is retired.

```
gateway  ──provision──▶  CredentialBundle (WG conf + vless:// + hysteria2:// + singbox_profile)
                              │
 VpnController ──build──▶  sing-box config (per Transport)         lib/vpn/vpn_models.dart
                              │
 SingboxEngine ──channel─▶  native libbox tunnel                   lib/vpn/singbox_engine.dart
```

- **Auto**: try WireGuard (fast), fall back to VLESS+REALITY, then Hysteria2.
- **Stealth**: VLESS+REALITY → Hysteria2 (skips raw WireGuard/UDP).
- **WireGuard**: direct, fastest, most detectable.

The controller does the cross-transport fallback in Dart by watching the stage
stream. Per-transport budget: up to **20s** for the engine to report a stage
(`_armAndStart`), then a readiness gate — mixed-proxy listener (≤10s stealth /
≤6s WG on Android) plus tunnel egress probes (≤~27s WG / ≤~36s stealth). The
user can cancel at any point (`VpnController.cancelConnect`, wired to the dial
and the desktop tray).

## Stage semantics — read this before touching connect logic

**`connected` means "the OS TUN is open", NOT "the tunnel works".** On Android,
`openTun` fires the moment `VpnService.Builder.establish()` succeeds — the inner
WireGuard handshake (and in stealth, the carrier handshake) may still be pending
or may never complete. iOS behaves the same via `ExtensionPlatformInterface`.
Consequences, all handled in `VpnController`:

- `connect()` holds the UI on *connecting* until the mixed proxy accepts TCP
  **and** an egress probe returns a public IP (`_waitWireGuardReady` /
  `_waitStealthReady`).
- After connect (and after `syncWithNative()` adopts a native-`connected`
  tunnel), a **health monitor** re-probes egress every 45s (10s while degraded);
  two consecutive failures flip `tunnelHealthy` to false and the UI shows
  "TUNNEL STALLED" instead of pretending to be protected.
- A `connected` event that arrives *after* a connect attempt already failed is a
  zombie from an abandoned start — the controller stops it rather than trusting it.

`EgressIpProbe` hits `https://1.1.1.1/cdn-cgi/trace` first (IP literal — works
even when DNS through the tunnel is dead), then ipify / ifconfig.me, all in
parallel with a hard per-attempt timeout.

## Method-channel contract

`SingboxEngine` (Dart) ↔ native. Implement these on each platform.

**MethodChannel `dev.erebrus/singbox`**

| method | args | returns | notes |
|---|---|---|---|
| `prepare` | — | `bool` | Android: `VpnService.prepare`. iOS/macOS: `NETunnelProviderManager` profile setup. |
| `start` | `{config: String, name: String, splitTunnelEnabled: bool, splitTunnelMode: String, splitTunnelPackages: List<String>}` | — | `config` is a full sing-box JSON; boot libbox with it. Split-tunnel args are Android-only (`include`/`exclude` app lists); other platforms may ignore them. |
| `stop` | — | — | tear down the tunnel. Dart polls `stage` afterwards until `disconnected`. |
| `stage` | — | `String` | one of `disconnected\|connecting\|connected\|disconnecting\|error`. Android returns `connected` whenever a TUN fd is held (`tunnelActive`), so it survives Flutter engine restarts. |
| `lastError` | — | `String?` | last native start failure; surfaced in the connect-error toast. Cleared on any non-error stage. |
| `genWgKeys` | — | `{private: String, public: String}` | base64 x25519 keypair; private stays on device. |
| `setAppProxy` | `{host: String, port: int}` | — | route the in-app WebView through the local mixed inbound (Android `ProxyController`; desktop no-op — see below). |
| `clearAppProxy` | — | — | undo `setAppProxy`. |
| `listApps` | — | `List<Map>` | Android-only: installed user apps for the split-tunnel picker. |

**EventChannel `dev.erebrus/singbox/status`** → `String` stage on every change.
The current stage is replayed on (re)subscribe.

**EventChannel `dev.erebrus/singbox/stats`** → `Map` every ~1s:
`{rx_bytes, tx_bytes, uplink_bps, downlink_bps}`.

## Native integration steps

### Android (`android/app`) — shipped

1. Build `libbox.aar`: `./scripts/build-libbox.sh`.
2. `ErebrusVpnService` — `Libbox.newService` + `VpnService` TUN, `NWPathMonitor`-equivalent
   via `AndroidNetworkPlatform`, stats via `LibboxStatsMonitor`.
3. `SingboxBridge` in `MainActivity` — channels, split-tunnel args, stage/stats events.

### iOS (`ios`) — shipped

1. Build `Libbox.xcframework`: `./scripts/build-libbox-ios.sh`.
2. One-time Xcode wiring: `ruby ./scripts/setup-ios-tunnel.rb`.
3. **ErebrusTunnel** (`NEPacketTunnelProvider`) — libbox v1.11 service + command server;
   `ExtensionPlatformInterface` opens TUN; stats in app group `group.com.erebrus.vpn`.
4. **Runner** — `TunnelManager.swift` + `SingboxPlugin.swift` drive `NETunnelProviderManager`.

Requires physical device + Apple Developer App Group + Network Extension entitlements.
See [BUILD.md](BUILD.md) and [STATUS.md](STATUS.md).

### macOS (`macos`) — partial

**Today (unsigned dev):** `SingboxDesktopRunner` runs the **sing-box CLI** in proxy mode
(`./scripts/setup-macos-dev.sh`). Not the Network Extension.

**TODO for system TUN:** Wire libbox into `macos/ErebrusTunnel/PacketTunnelProvider.swift`
(same pattern as iOS), add NE target in Xcode, embed `macos/Frameworks/Libbox.xcframework`.
`TunnelManager.swift` + channels exist but the extension is still a lifecycle stub.

### Windows / Linux — CLI proxy mode (partial)

Dart uses `SingboxDesktopRunner` on **all** desktop platforms (`SingboxEngine._useDesktopRunner`).
The C++ plugins in `windows/runner/singbox_plugin.cpp` and `linux/runner/singbox_plugin.cc`
register `dev.erebrus/singbox` but are **never called** from Dart on desktop.

1. Fetch CLI: `./scripts/fetch-singbox-cli.sh windows` (or `linux`).
2. Build: `./scripts/build-desktop.sh windows` (or `linux`) — embeds `sing-box` next to the app.
3. Config: `useSystemTunnel: false` → mixed inbound on `127.0.0.1:10808` only (no TUN).
4. **TODO (prod):** Windows/Linux system proxy (macOS has `MacosSystemProxy` via `networksetup`).
   Without it, `setAppProxy` is a desktop no-op and the in-app WebView does not use the tunnel.
5. **Optional later:** wire libbox TUN in the native plugins for system-wide VPN without CLI.

## Gateway provisioner

`GatewayController` wires `VpnController.provisioner` on init to call
`POST /api/v2/vpn/clients { name, node_id, wg_public_key }` and cache the
returned `CredentialBundle`. WG keys come from `genWgKeys` (native on mobile,
`WgKeygen` in Dart on desktop).

## Troubleshooting connect failures (adb logcat, tag `erebrus-singbox`)

**`endpoint/wireguard[wg-out]: connect to server: EOF` /
`failed to send handshake initiation: EOF` (stealth)** — the carrier reached a
server and the server **closed the connection**. This is *not* DNS. Usual
causes, in order of likelihood:

1. **Stale REALITY params.** The node regenerated its REALITY keypair (e.g. on
   an IP→domain cutover) but the client is dialing with old `pbk`/`sid`/`sni`.
   Check that the provisioned `vless_uri` carries `pbk`, `sid` and `sni` query
   params — `_patchVlessFromUri` only overwrites them when present. Fix by
   re-provisioning (delete + recreate the VPN client) or refreshing the bundle.
2. **Carrier port blocked or fronted wrong** — verify the node's VLESS port is
   reachable and its REALITY `server_name` matches what the node serves.

**Storm of `dns: exchange failed … context canceled` for random domains
(mtalk.google.com, qq.com, …)** — a *symptom*, not the cause: the TUN is up and
capturing all device traffic, but the inner WG endpoint is dead, so every app's
DNS (routed `dns-remote → wg-out`) times out. Find the wg-out/carrier error
above the storm; that's the real failure. The UI now surfaces this state as
"TUNNEL STALLED" via the egress health monitor.

**Hostname WG endpoints (e.g. `us01.erebrus.io:51820`)** — the config builder
pre-resolves dial hosts to IPv4 (`resolveDialHosts`) so the WG peer never needs
tunnel DNS, adds a `dns-direct` bootstrap rule for those domains, and uses
`domain` (not `ip_cidr`) route bypass rules when a hostname survives into the
config. sing-box `ip_cidr` rules reject hostnames with `ParsePrefix` errors —
that's what broke `/32`-style rules when nodes moved from IPs to domains.
