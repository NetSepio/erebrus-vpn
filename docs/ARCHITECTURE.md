# Architecture

How the Erebrus VPN app is put together, from the screens down to the packets.
If you're new to the codebase, read this first.

## The big idea: one engine, many disguises

Most apps bundle a separate library per protocol (one for WireGuard, one for the
stealth stuff). Erebrus uses **a single engine** — [sing-box](https://sing-box.sagernet.org/) —
for everything. WireGuard isn't a separate thing; it's just an *endpoint inside*
the sing-box config we hand the engine.

That means switching protocols is only a change in configuration, never a change
in plumbing. The three modes the user sees map to an ordered list of transports
the app tries in turn:

| Mode | Tries, in order |
|---|---|
| **Auto** | WireGuard → VLESS+REALITY → Hysteria2 |
| **Stealth** | VLESS+REALITY → Hysteria2 (skips raw UDP) |
| **WireGuard** | WireGuard only |

- **WireGuard** — a fast UDP tunnel. Great, but easy for networks to spot and block.
- **VLESS + REALITY** — looks exactly like a normal HTTPS visit to a big website. Very hard to block.
- **Hysteria2** — looks like QUIC / HTTP-3 video traffic, over UDP.

"Stealth" carriers wrap the **same** WireGuard tunnel — your encryption and
identity never change, only the disguise on the outside.

## The data flow

```
gateway ── provisions ──▶  CredentialBundle (WireGuard + carrier URIs + a sing-box profile)
                                 │
 VpnController ── builds ──▶  sing-box config for the chosen transport     lib/vpn/vpn_models.dart
                                 │
 SingboxEngine ── channel ─▶  native libbox tunnel                         lib/vpn/singbox_engine.dart
                                 │
                              your traffic, encrypted, out to the internet
```

## The Dart layers (`lib/vpn/`)

**`vpn_models.dart`** — the pure data + logic, no Flutter:
- `ConnectMode` (Auto/Stealth/WireGuard) → its `transports` fallback list.
- `VpnNode` — a server from the network's directory.
- `CredentialBundle` — what the gateway/node gives us: a WireGuard config, the
  `vless://` / `hysteria2://` share URIs, and a ready-made `singbox_profile`.
- `SingboxConfigBuilder` — turns a bundle + a chosen transport + the device's
  WireGuard key into the final sing-box config. For **WireGuard** it dials the
  node directly; for **stealth** it points WireGuard at the node's loopback and
  routes it through a carrier (`detour`). It always adds a `tun` inbound so the
  OS feeds device traffic in. This file is unit-tested (`test/vpn_config_test.dart`).

**`singbox_engine.dart`** — a thin facade over the native tunnel via Flutter
method/event channels (`dev.erebrus/singbox`): `prepare` (ask for VPN
permission), `start`/`stop`, a `stage` stream (connecting/connected/…), a `stats`
stream (bytes up/down), and `genWgKeys` (generate the device's WireGuard keypair
natively — the private key never leaves the phone).

**`vpn_controller.dart`** — the GetX state machine the UI binds to. It:
1. ensures a device WireGuard keypair exists (stored in secure storage),
2. provisions a client (via an injected `provisioner` — see below),
3. tries each transport for the chosen mode, giving each a connect budget before
   falling through to the next.

## The UI (`lib/view/`, `lib/theme/`)

`lib/theme/` is the design system — a dark "stealth-aurora" palette, typography,
and reusable glass-card / gradient-button widgets. Screens never hard-code
colors; they pull from here.

`lib/view/` holds the screens — `connect_view` (the big status orb + protocol
picker), `server_view`, `profile_view`, `settings_view` — tied together by
`bottombar/main_shell.dart`, which `main.dart` launches.

## The native tunnel

Mobile uses **libbox** inside an OS VPN slot; desktop uses the sing-box CLI until
native plugins are wired. Platform matrix: [STATUS.md](STATUS.md).

### Android (`android/.../com/erebrus/vpn/`)

- **`MainActivity`** — Flutter channels, VPN permission, WireGuard keygen.
- **`ErebrusVpnService`** — `VpnService` + libbox; per-app split tunnel.
- **`SingboxBridge`** — stage/stats EventChannels.

### iOS (`ios/ErebrusTunnel/` + `ios/Runner/`)

- **`TunnelManager`** — `NETunnelProviderManager` save/start/stop; observes `NEVPNStatus`.
- **`PacketTunnelProvider`** — libbox service, TUN via `ExtensionPlatformInterface`,
  `NWPathMonitor` for stealth carrier binding, stats → app group.
- **`SingboxBridge`** (`SingboxPlugin.swift`) — same channel contract as Android.

### macOS / Windows / Linux

- **macOS:** `singbox_desktop_runner.dart` spawns the sing-box CLI (proxy mode).
  Network Extension scaffold exists but libbox is not started in the extension yet.
- **Windows / Linux:** channel stubs only — `start` does not run a tunnel yet.

`libbox` binaries are not committed — build per platform ([BUILD.md](BUILD.md)).
Channel contract: [STEALTH_CLIENT.md](STEALTH_CLIENT.md).

## How it joins the network

`VpnController.provisioner` is a hook the app sets to obtain a `CredentialBundle`.
Two ways:
- **Gateway** — call `POST /api/v2/vpn/clients` on the Erebrus gateway (the normal
  path, with accounts and entitlements).
- **Manual import** — paste a node's `singbox_profile` / share URI to connect to a
  single node directly (handy for testing before the gateway is wired).
