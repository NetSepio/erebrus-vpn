import Foundation
import NetworkExtension

/// Controls the iOS Packet Tunnel Provider via NETunnelProviderManager.
final class TunnelManager {
    static let shared = TunnelManager()

    private(set) var stage: String = "disconnected"
    var onStageChange: ((String) -> Void)?

    private var statusObserver: NSObjectProtocol?

    private init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStageFromSystem()
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }

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
            TunnelConstants.configKey: config as NSString,
            TunnelConstants.profileNameKey: profileName as NSString,
        ]
        manager.localizedDescription = TunnelConstants.providerDescription
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try manager.connection.startVPNTunnel()
        refreshStageFromSystem()
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

    func refreshStageFromSystem() {
        Task {
            guard let manager = try? await loadManager() else {
                setStage("disconnected")
                return
            }
            setStage(mapStatus(manager.connection.status))
        }
    }

    private func mapStatus(_ status: NEVPNStatus) -> String {
        switch status {
        case .connected: return "connected"
        case .connecting, .reasserting: return "connecting"
        case .disconnecting: return "disconnecting"
        case .disconnected, .invalid: return "disconnected"
        @unknown default: return "disconnected"
        }
    }

    private func setStage(_ value: String) {
        guard stage != value else { return }
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