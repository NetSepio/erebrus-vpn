# ErebrusTunnel (macOS Network Extension) — TODO

Scaffold for a signed system TUN. **Not wired to libbox yet** — unsigned macOS
dev uses the sing-box CLI in proxy mode instead (`./scripts/setup-macos-dev.sh`).

To finish (mirror `ios/ErebrusTunnel/`):

1. `./scripts/build-libbox-macos.sh`
2. File → New → Target → **Network Extension** → Packet Tunnel Provider
3. Product name `ErebrusTunnel`, bundle id `com.erebrus.vpn.ErebrusTunnel`
4. Replace `PacketTunnelProvider.swift` with libbox startup (copy iOS implementation)
5. Embed `macos/Frameworks/Libbox.xcframework`, App Group `group.com.erebrus.vpn`
6. Debug signing: `Runner/DebugProfile.Tunnel.entitlements`

See [docs/STATUS.md](../../docs/STATUS.md) and [docs/cert.md](../../docs/cert.md).