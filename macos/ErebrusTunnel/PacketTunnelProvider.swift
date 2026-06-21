import NetworkExtension
import os.log

/// macOS Packet Tunnel Provider — runs sing-box (libbox) inside the extension.
///
/// Embed `macos/Frameworks/Libbox.xcframework` (from `./scripts/build-libbox-macos.sh`)
/// and wire Libbox service startup here. Until then this provider acknowledges
/// the tunnel lifecycle so NETunnelProviderManager integration can be tested.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = Logger(subsystem: "com.erebrus.vpn.ErebrusTunnel", category: "tunnel")

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let config = protocolConfiguration.providerConfiguration?[TunnelConstants.configKey] as? String,
              !config.isEmpty else {
            completionHandler(NSError(domain: "ErebrusTunnel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing sing-box config",
            ]))
            return
        }

        log.info("startTunnel — config bytes: \(config.utf8.count, privacy: .public)")

        // TODO: Libbox.newService(config) when Libbox.xcframework is embedded.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.255"])
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        setTunnelNetworkSettings(settings) { error in
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("stopTunnel reason=\(reason.rawValue, privacy: .public)")
        completionHandler()
    }
}