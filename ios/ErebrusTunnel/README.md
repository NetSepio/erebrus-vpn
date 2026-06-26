# ErebrusTunnel (iOS Network Extension)

Packet Tunnel Provider running sing-box via `Libbox.xcframework`.

## Setup

```bash
./scripts/build-libbox-ios.sh
ruby ./scripts/setup-ios-tunnel.rb   # once — adds Xcode target
```

Open `ios/Runner.xcworkspace`, enable **App Groups** + **Network Extensions** on
Runner and ErebrusTunnel (entitlements are in-repo). Run on a **physical device**.

Bundle id: `com.erebrus.vpn.ErebrusTunnel` · App group: `group.com.erebrus.vpn`

See [docs/BUILD.md](../../docs/BUILD.md) and [docs/STATUS.md](../../docs/STATUS.md).