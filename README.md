# Erebrus VPN

The Erebrus mobile app — a premium, stealth-capable DePIN VPN client. Ships as
`com.erebrus.vpn` (Flutter).

One **sing-box engine** drives every protocol: WireGuard is an endpoint *inside*
the sing-box config, and when WireGuard's UDP is throttled or DPI-blocked the
same tunnel falls back to a stealth carrier that looks like ordinary traffic:

- **Auto** — WireGuard → VLESS+REALITY → Hysteria2 (the controller probes and
  falls through within a budget per transport).
- **Stealth** — VLESS+REALITY → Hysteria2 (skips raw UDP).
- **WireGuard** — direct, fastest, most detectable.

## Layout

```
lib/theme/         design system (stealth-aurora dark theme, glass components)
lib/vpn/           the engine:
  vpn_models.dart      ConnectMode/Transport, CredentialBundle, SingboxConfigBuilder
  singbox_engine.dart  method/event-channel facade over native libbox
  vpn_controller.dart  GetX state machine: keypair, provision, auto-failover
lib/view/          premium screens (connect, servers, profile, settings) + shell
android/app/src/main/kotlin/com/erebrus/vpn/
  MainActivity.kt      channel wiring + VPN permission + x25519 keygen
  ErebrusVpnService.kt VpnService running sing-box via libbox
  SingboxBridge.kt     service ↔ Flutter event bridge
```

## Build

```bash
flutter pub get
flutter analyze
flutter test
```

### Native tunnel (required to actually connect)

The Android tunnel links sing-box's `libbox` (`io.nekohasekai.libbox.*`), which
is **not committed** — build it once:

```bash
./scripts/build-libbox.sh        # gomobile build → android/app/libs/libbox.aar
flutter run                       # arm64 device
```

See [docs/STEALTH_CLIENT.md](docs/STEALTH_CLIENT.md) for the channel contract and
the iOS `NEPacketTunnelProvider` integration.

## Wiring to the network

`VpnController.provisioner` must be set to a function that provisions a client
via the Erebrus gateway (`POST /api/v2/vpn/clients`) and returns a
`CredentialBundle`. A manual-import path (paste a node's `singbox_profile` / share
URI) can drive a standalone node without the gateway for testing.
