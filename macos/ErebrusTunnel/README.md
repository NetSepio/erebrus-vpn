# ErebrusTunnel (macOS Network Extension)

Sandboxed Packet Tunnel Provider running the universal macOS libbox framework.
It supports WireGuard, VLESS + REALITY, and Hysteria2 through the shared Dart
configuration and fallback logic.

Setup:

1. `./scripts/build-libbox-macos.sh`
2. `ruby ./scripts/setup-macos-tunnel.rb`
3. Enable App Group `group.com.erebrus.vpn` and Packet Tunnel Provider for
   `com.erebrus.vpn` and `com.erebrus.vpn.ErebrusTunnel`.
4. Build or archive the Runner scheme.

See [docs/STATUS.md](../../docs/STATUS.md) and [docs/cert.md](../../docs/cert.md).
