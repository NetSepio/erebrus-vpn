# ErebrusTunnel (iOS Network Extension)

Packet Tunnel Provider running sing-box via `Libbox.xcframework`.

The Xcode target is wired by `scripts/setup-ios-tunnel.rb`. After setup:

1. Build libbox: `./scripts/build-libbox-ios.sh`
2. Open `ios/Runner.xcworkspace` in Xcode
3. Enable **App Groups** + **Network Extensions** on the Runner and ErebrusTunnel targets
   (entitlements files are already in the repo)
4. Run on a physical device — VPN does not work in the Simulator

Bundle id: `com.erebrus.vpn.ErebrusTunnel` · App group: `group.com.erebrus.vpn`