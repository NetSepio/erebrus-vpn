import Foundation
import NetworkExtension

/// Controls the macOS Packet Tunnel Provider via NETunnelProviderManager.
final class TunnelManager {
    static let shared = TunnelManager()

    private(set) var stage: String = "disconnected"
    var onStageChange: ((String) -> Void)?

    private init() {}

    func prepare() async -> Bool {
        do {
            _ = try await loadOrCreateManager()
            return true
        } catch {
            NSLog("[TunnelManager] prepare failed: \(error)")
            return false
        }
    }

    func start(config: String, profileName: String) async throws {
        setStage("connecting")
        let manager = try await loadOrCreateManager()
        let proto = manager.protocolConfiguration as! NETunnelProviderProtocol
        proto.providerBundleIdentifier = TunnelConstants.tunnelBundleId
        proto.serverAddress = TunnelConstants.providerDescription
        proto.providerConfiguration = [
            TunnelConstants.configKey: config,
            TunnelConstants.profileNameKey: profileName,
        ]
        manager.localizedDescription = TunnelConstants.providerDescription
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try manager.connection.startVPNTunnel()
        setStage("connected")
    }

    func stop() async {
        setStage("disconnecting")
        guard let manager = try? await loadManager() else {
            setStage("disconnected")
            return
        }
        manager.connection.stopVPNTunnel()
        manager.isEnabled = false
        try? await manager.saveToPreferences()
        setStage("disconnected")
    }

    private func setStage(_ value: String) {
        stage = value
        onStageChange?(value)
    }

    private func loadManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let existing = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == TunnelConstants.tunnelBundleId
        }) {
            return existing
        }
        throw NSError(domain: "ErebrusTunnel", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "VPN profile not found",
        ])
    }

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        if let manager = try? await loadManager() { return manager }
        let manager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = TunnelConstants.tunnelBundleId
        proto.serverAddress = TunnelConstants.providerDescription
        manager.protocolConfiguration = proto
        manager.localizedDescription = TunnelConstants.providerDescription
        return manager
    }
}