# Erebrus VPN — network topology

This document explains how traffic moves on Android when Erebrus is connected,
what the `172.19.x.x` addresses mean, and why the in-app browser can behave
differently from Chrome.

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
| `172.19.0.2` | Derived from TUN `/30` | **DNS hijack** target on the TUN. Android is told to use this as VPN DNS; sing-box intercepts port 53 and resolves via its DNS module. |
| `10.0.0.x` | Gateway (`bundle.address`) | Your **WireGuard tunnel** address on the node. Internal to the VPN; not the public egress IP. |
| `212.x.x.x` (example) | Gateway (`bundle.endpoint`) | WireGuard **server** UDP endpoint. Must bypass the tunnel (`direct` route) so handshake packets do not loop. |
| `1.1.1.1` etc. | Gateway (`bundle.dns`) | Upstream resolver sing-box uses **after** hijacking DNS; queries go through `wg-out`. |
| Public egress IP | ipify / ifconfig.me via tunnel | What the UI labels **Egress IP** — the node's exit address on the internet. |

Nothing in `VpnController` hardcodes `172.19` or DNS. Those live in
`lib/vpn/vpn_models.dart` (`SingboxConfigBuilder`), which assembles the sing-box
JSON the native engine runs.

## sing-box routing (why order matters)

Config ends with `route.final: wg-out` — all unmatched traffic uses WireGuard.

These **rules run first**:

1. WireGuard server IP → `direct` (handshake must not enter TUN)
2. `protocol: dns` → `hijack-dns` (hand DNS to sing-box DNS module)
3. `127.0.0.0/8` → `direct` (stealth loopback peers)
4. ~~`172.19.0.0/30` → `direct`~~ — **removed**; a blanket rule here ran *before*
   DNS hijack and broke Chrome by sending queries to `172.19.0.2` out the wrong
   path.

Without DNS hijack working, you see log spam like:

```
inbound/tun[tun-in]: ... to 172.19.0.2:53
endpoint/wireguard[wg-out]: outbound ... to 172.19.0.2:53   ← wrong
```

DNS to `172.19.0.2` must never go to `wg-out`.

## Why the Erebrus app is excluded from the system TUN

In `ErebrusVpnService.openTun()`:

```kotlin
builder.addDisallowedApplication(packageName)
```

WireGuard speaks UDP to the node. If that socket is captured by the same TUN,
packets can loop on some OEM devices (Huawei, etc.) even with `protect(fd)`.
Excluding the app UID fixes the tunnel; side effect: **the app must use the
local proxy** for browser and egress display.

`protect(fd)` in `autoDetectInterfaceControl()` still applies to libbox sockets
owned by the VPN service process.

## What changed around the UI/UX work

The `172.19.0.1/30` TUN address existed before the UI refresh. What added
complexity:

| Change | Effect |
|--------|--------|
| In-app browser + egress IP UI | Makes leak/wrong-IP visible; needs local proxy because app UID is excluded from TUN |
| `addDisallowedApplication` | Restored after a brief removal — fixes WG loop, splits app vs system paths |
| Kill switch | Can replace a live tunnel with a block-only config if it fires during connect retries |
| Session restore | UI shows connected when native TUN is still up |

The underlying DNS routing bug (`final: wg-out` without proper hijack ordering)
was latent earlier; broken DNS affects **Chrome** (system TUN path), not the
in-app browser (proxy path).

## Chrome still not on VPN?

Check these in order:

1. **Rebuild** after routing/DNS fixes — stale APK is a common cause.
2. **Chrome Secure DNS** — Settings → Privacy → Use Secure DNS. Set to Off or
   "Use your current service provider" while testing. DoH can bypass VPN DNS.
3. **Android Private DNS** — Settings → Network → Private DNS → Off for testing.
4. **Verify system path** — With VPN connected, open Chrome (not Erebrus browser)
   and visit https://api.ipify.org — should show the node egress IP.
5. **Logcat** — `adb logcat -s erebrus-singbox:*` should show TCP via `wg-out`,
   not DNS to `172.19.0.2` via `wg-out`.

## Kill switch topology

When kill switch engages, config is replaced with `killSwitchBlockConfig()`:
TUN stays up, `route.final: block`. All traffic is dropped until the user
reconnects.

## Related files

| File | Role |
|------|------|
| `lib/vpn/vpn_models.dart` | sing-box config: TUN, DNS, routes, local mixed inbound |
| `lib/vpn/vpn_controller.dart` | Connect/disconnect; egress probe; app proxy sync |
| `android/.../ErebrusVpnService.kt` | Opens OS TUN, sets VPN DNS, excludes app UID |
| `lib/vpn/egress_ip_probe.dart` | Public IP check via local proxy |
| `lib/view/browser/browser_controller.dart` | WebView proxy when connected |

See also [ARCHITECTURE.md](ARCHITECTURE.md) and [STEALTH_CLIENT.md](STEALTH_CLIENT.md).