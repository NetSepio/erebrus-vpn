# Erebrus VPN — network topology

This document explains how traffic moves on Android when Erebrus is connected,
what the `172.19.x.x` addresses mean, how **tunnel DNS** works, and how a
node-side resolver (Pi-hole, AdGuard Home) fits in.

## Two traffic paths

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Android device                                  │
│                                                                         │
│  Chrome, Firefox, other apps                                            │
│       │                                                                 │
│       ▼                                                                 │
│  Android VpnService TUN  ──►  sing-box tun-in  ──►  wg-out  ──►  node │
│  (system-wide)              (172.19.0.1/30)         (WireGuard)       │
│                                                                         │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │
│                                                                         │
│  Erebrus app (UID excluded from TUN — see below)                        │
│       │                                                                 │
│       ├── Egress IP probe (HttpClient)                                  │
│       └── In-app WebView                                                │
│               │                                                         │
│               ▼                                                         │
│       127.0.0.1:10808  ──►  sing-box mixed-in  ──►  wg-out  ──►  node │
│       (local proxy)                                                     │
└─────────────────────────────────────────────────────────────────────────┘
```

| Path | Who uses it | How it enters sing-box |
|------|-------------|------------------------|
| **System TUN** | Chrome, all non-Erebrus apps | Android routes `0.0.0.0/0` into the VPN interface opened by `ErebrusVpnService` |
| **Local proxy** | Erebrus app only (browser tab, egress readout) | HTTP/SOCKS to `127.0.0.1:10808` → sing-box `mixed` inbound |

Both paths should exit through the same WireGuard tunnel to the selected node.

## Address map (what is hardcoded vs from the gateway)

| Address | Source | Meaning |
|---------|--------|---------|
| `172.19.0.1/30` | Client config (`SingboxConfigBuilder`) | sing-box **local TUN** interface. Convention used by sing-box mobile clients — **not** your public IP. |
| `172.19.0.2` | Derived from TUN `/30` | **Tunnel DNS** on the phone. Android is told to use this; sing-box captures port 53 locally and handles resolution. |
| `10.0.0.x` | Gateway (`bundle.address`) | Your **WireGuard client** address on the node subnet. Internal to the VPN; not the public egress IP. |
| `10.0.0.1` (example) | Gateway (`bundle.dns`) | **Upstream resolver** on the node network — e.g. Pi-hole / AdGuard Home / node gateway. |
| `212.x.x.x` (example) | Gateway (`bundle.endpoint`) | WireGuard **server** UDP endpoint. Must bypass the tunnel (`direct` route) so handshake packets do not loop. |
| `1.1.1.1` etc. | Gateway (`bundle.dns`) default | Public upstream if the node does not run a local filter DNS. |
| Public egress IP | ipify / ifconfig.me via tunnel | What the UI labels **Egress IP** — the node's exit address on the internet. |

Nothing in `VpnController` hardcodes `172.19` or DNS. Those live in
`lib/vpn/vpn_models.dart` (`SingboxConfigBuilder`), which assembles the sing-box
JSON the native engine runs.

## Tunnel DNS (on-device)

Tunnel DNS is how the phone keeps DNS **inside the VPN**. It is **not** the same
as the resolver running on the node.

```
App asks: "what is google.com?"
    │
    ▼
Android OS sends DNS to 172.19.0.2:53   ← tunnel DNS (always on the phone)
    │
    ▼
sing-box captures the query (route action `hijack-dns` in config)
    │
    ▼
sing-box DNS module forwards to dns-remote
    │
    ▼
dns-remote = bundle.dns (e.g. 10.0.0.1 or 1.1.1.1) via wg-out
    │
    ▼
Answer returns to the app
```

**Two different addresses, two jobs:**

| Layer | Address | Where | Job |
|-------|---------|-------|-----|
| Tunnel DNS | `172.19.0.2` | On the phone (TUN) | Capture app DNS so nothing leaks around the VPN |
| Upstream DNS | `bundle.dns` | Through the tunnel | Actually resolve names (public DNS or node filter DNS) |

The phone **never** uses `10.0.0.1` directly as its system DNS. Android always
gets `172.19.0.2`. sing-box then talks to `10.0.0.1` (or whatever the gateway
put in `bundle.dns`) over WireGuard.

Integration points:

1. **Dart** — `SingboxConfigBuilder`: `tunDnsAddress`, `dns.servers[].address`
   from `bundle.dns`, route rule `protocol: dns` → `hijack-dns`
2. **Android** — `ErebrusVpnService.openTun()`: `builder.addDnsServer(TUN_DNS)`
3. **Gateway** — `wireguard.dns` in the provision response sets upstream

## Pi-hole / AdGuard Home on the node

If Erebrus runs Pi-hole or AdGuard Home on the **node** (or gateway) at e.g.
`10.0.0.1:53` on the WireGuard subnet:

```
Phone                         WireGuard tunnel              Node
─────                         ────────────────              ────
Chrome → 172.19.0.2:53
         sing-box tunnel DNS
              → dns-remote 10.0.0.1:53  ──wg-out──►  Pi-hole / AdGuard
                                                      │ block ads / malware
                                                      ▼
                                                 upstream (1.1.1.1, etc.)
```

**What the gateway should return** when provisioning a client:

```json
"wireguard": {
  "address": "10.0.0.7/32",
  "dns": "10.0.0.1",
  "endpoint": "212.147.232.36:51820",
  ...
}
```

The app already maps that into sing-box:

```dart
{'tag': 'dns-remote', 'address': dnsServer, 'detour': wgEndpointTag}
```

So filtering happens **on the node**; the phone only needs tunnel DNS to deliver
queries into the tunnel reliably.

**Typical node layout:**

| Host | Role |
|------|------|
| `10.0.0.1` | Node gateway / Pi-hole / AdGuard Home listener |
| `10.0.0.7/32` | Your phone's WG client address |
| `172.19.0.2` | Tunnel DNS on the phone only — unrelated to `10.0.0.0/24` |

Pi-hole does **not** replace `172.19.0.2` on the client. It replaces (or sits
in front of) `1.1.1.1` as the upstream in `bundle.dns`.

**Not implemented yet (future):** per-user choice of node DNS vs public DNS in
the app UI, or discovery of multiple resolvers. Today it is whatever the
gateway puts in `wireguard.dns`.

## sing-box routing (why order matters)

Config ends with `route.final: wg-out` — all unmatched traffic uses WireGuard.

These **rules run first**:

1. WireGuard server IP → `direct` (handshake must not enter TUN)
2. `protocol: dns` → `hijack-dns` (tunnel DNS capture — sing-box API name)
3. `127.0.0.0/8` → `direct` (stealth loopback peers)

Without tunnel DNS capture working, you see:

```
inbound/tun[tun-in]: ... to 172.19.0.2:53
endpoint/wireguard[wg-out]: outbound ... to 172.19.0.2:53   ← wrong
```

Queries to `172.19.0.2` must be handled locally, not forwarded to `wg-out`.

## Why the Erebrus app is excluded from the system TUN

In `ErebrusVpnService.openTun()`:

```kotlin
builder.addDisallowedApplication(packageName)
```

WireGuard speaks UDP to the node. If that socket is captured by the same TUN,
packets can loop on some OEM devices (Huawei, etc.) even with `protect(fd)`.
Excluding the app UID fixes the tunnel; side effect: **the app must use the
local proxy** for browser and egress display.

## Chrome / Private DNS / DoH

Tunnel DNS handles classic UDP port 53 to `172.19.0.2`. These can bypass it:

- **Chrome Secure DNS** (DoH)
- **Android Private DNS**

For testing filtered DNS through Pi-hole, disable those or use providers that
respect the VPN DNS path.

## Kill switch topology

When kill switch engages, config is replaced with `killSwitchBlockConfig()`:
TUN stays up, `route.final: block`. All traffic is dropped until the user
reconnects.

## Related files

| File | Role |
|------|------|
| `lib/vpn/vpn_models.dart` | sing-box config: TUN, tunnel DNS, routes, mixed inbound |
| `lib/vpn/vpn_controller.dart` | Connect/disconnect; egress probe; app proxy sync |
| `android/.../ErebrusVpnService.kt` | Opens OS TUN, sets tunnel DNS, excludes app UID |
| `lib/vpn/egress_ip_probe.dart` | Public IP check via local proxy |
| `lib/view/browser/browser_controller.dart` | WebView proxy when connected |

See also [ARCHITECTURE.md](ARCHITECTURE.md) and [STEALTH_CLIENT.md](STEALTH_CLIENT.md).