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
| `prepare` | — | `bool` | Android: `VpnService.prepare`, return true if already/granted. iOS: no-op `true`. |
| `start` | `{config: String, name: String}` | — | `config` is a full sing-box JSON; boot libbox with it. |
| `stop` | — | — | tear down the tunnel. |
| `stage` | — | `String` | one of `disconnected\|connecting\|connected\|disconnecting\|error`. |
| `genWgKeys` | — | `{private: String, public: String}` | base64 x25519 keypair; private stays on device. |

**EventChannel `dev.erebrus/singbox/status`** → `String` stage on every change.

**EventChannel `dev.erebrus/singbox/stats`** → `Map` every ~1s:
`{rx_bytes, tx_bytes, uplink_bps, downlink_bps}`.

## Native integration steps

### Android (`android/app`)
1. Add the sing-box `libbox` AAR (built via `gomobile bind -target=android` from
   sing-box with tags `with_reality_server`-equivalent client tags, i.e.
   `with_gvisor,with_quic,with_utls`). Place in `android/app/libs/`.
2. A `VpnService` subclass that:
   - on `start`: writes `config` to a temp file, calls `Libbox.newService(...)`
     / `BoxService.start()`, and adopts the tun fd from `establish()`.
   - bridges libbox's command-server stats → the stats EventChannel.
   - emits stage transitions on the status EventChannel.
3. `MainActivity` registers the MethodChannel and forwards to the service;
   `prepare` calls `VpnService.prepare(this)` and resolves on the activity result.

### iOS (`ios`)
1. Add `Libbox.xcframework` (gomobile `-target=ios`).
2. A Network Extension target (`NEPacketTunnelProvider`) that starts libbox with
   the supplied config and serves the packet flow.
3. The app group + `NETunnelProviderManager` wiring; `start`/`stop` toggle the
   tunnel; stats read from the extension via the app group or libbox command client.

## Wiring the gateway provisioner

`VpnController.provisioner` must be set (e.g. after login) to a function that
calls `POST /api/v2/vpn/clients { name, node_id, wg_public_key }` and returns a
`CredentialBundle.fromJson(response)`. The WG public key comes from
`genWgKeys` (generated once, persisted in `flutter_secure_storage`).
