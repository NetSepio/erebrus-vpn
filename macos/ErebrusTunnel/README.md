# ErebrusTunnel (macOS Network Extension)

Scaffold for the Packet Tunnel Provider. Add this as an Xcode target:

1. File → New → Target → **Network Extension** → **Packet Tunnel Provider**
2. Product name: `ErebrusTunnel`, bundle id: `com.erebrus.erebrusVpn.ErebrusTunnel`
3. Replace generated `PacketTunnelProvider.swift` with the file in this folder
4. Set entitlements to `ErebrusTunnel.entitlements`
5. Add `Shared/TunnelConstants.swift` to the extension target membership
6. Embed `../Frameworks/Libbox.xcframework` (from `./scripts/build-libbox-macos.sh`)
7. Enable App Group `group.com.erebrus.vpn` on app + extension