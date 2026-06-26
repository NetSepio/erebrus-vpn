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
stream (12s connect budget per transport).

## Method-channel contract

`SingboxEngine` (Dart) ↔ native. Implement these on each platform.

**MethodChannel `dev.erebrus/singbox`**

| method | args | returns | notes |
|---|---|---|---|
| `prepare` | — | `bool` | Android: `VpnService.prepare`. iOS/macOS: `NETunnelProviderManager` profile setup. |
| `start` | `{config: String, name: String}` | — | `config` is a full sing-box JSON; boot libbox with it. |
| `stop` | — | — | tear down the tunnel. |
| `stage` | — | `String` | one of `disconnected\|connecting\|connected\|disconnecting\|error`. |
| `genWgKeys` | — | `{private: String, public: String}` | base64 x25519 keypair; private stays on device. |

**EventChannel `dev.erebrus/singbox/status`** → `String` stage on every change.

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

### Windows / Linux — not wired

1. Build libbox: `./scripts/build-libbox-windows.sh` or `build-libbox-linux.sh`.
2. **TODO:** Implement tunnel start in `windows/runner/singbox_plugin.cpp` and
   `linux/runner/singbox_plugin.cc` (currently emit `error` on `start`).

## Wiring the gateway provisioner

`VpnController.provisioner` must be set (e.g. after login) to a function that
calls `POST /api/v2/vpn/clients { name, node_id, wg_public_key }` and returns a
`CredentialBundle.fromJson(response)`. The WG public key comes from
`genWgKeys` (generated once, persisted in `flutter_secure_storage`).
