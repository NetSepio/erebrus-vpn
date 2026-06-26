import Foundation
import Libbox
import NetworkExtension
import os.log

/// Packet Tunnel Provider — runs sing-box (libbox) inside the iOS Network Extension.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = Logger(subsystem: TunnelConstants.tunnelBundleId, category: "tunnel")

    private var boxService: LibboxBoxService?
    private var commandServer: LibboxCommandServer?
    private lazy var platformInterface = ExtensionPlatformInterface(self)
    private let statsMonitor = TunnelStatsMonitor()

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Task {
            do {
                try await startTunnelAsync(options: options)
                completionHandler(nil)
            } catch {
                self.log.error("startTunnel failed: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
            }
        }
    }

    private func startTunnelAsync(options: [String: NSObject]?) async throws {
        let proto = protocolConfiguration as? NETunnelProviderProtocol
        let providerConfig = proto?.providerConfiguration ?? [:]
        let config = (providerConfig[TunnelConstants.configKey] as? String)
            ?? (options?[TunnelConstants.configKey] as? String)
        guard let config, !config.isEmpty else {
            throw NSError(domain: "ErebrusTunnel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing sing-box config",
            ])
        }

        let profileName = (providerConfig[TunnelConstants.profileNameKey] as? String) ?? "Erebrus"
        log.info("startTunnel profile=\(profileName, privacy: .public) bytes=\(config.utf8.count, privacy: .public)")

        try FilePath.ensureDirectory(FilePath.workingDirectory)
        try FilePath.ensureDirectory(FilePath.cacheDirectory)

        let setup = LibboxSetupOptions()
        setup.basePath = FilePath.sharedDirectory.path
        setup.workingPath = FilePath.workingDirectory.path
        setup.tempPath = FilePath.cacheDirectory.path

        var setupError: NSError?
        LibboxSetup(setup, &setupError)
        if let setupError { throw setupError }

        let stderrPath = FilePath.cacheDirectory.appendingPathComponent("stderr.log").path
        var stderrError: NSError?
        LibboxRedirectStderr(stderrPath, &stderrError)
        if let stderrError { throw stderrError }

        LibboxSetMemoryLimit(true)

        var serviceError: NSError?
        let service = LibboxNewService(config, platformInterface, &serviceError)
        if let serviceError { throw serviceError }
        guard let service else {
            throw NSError(domain: "ErebrusTunnel", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create libbox service",
            ])
        }

        try service.start()
        boxService = service

        guard let server = LibboxNewCommandServer(statsMonitor, 300) else {
            throw NSError(domain: "ErebrusTunnel", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "command server create failed",
            ])
        }
        server.setService(service)
        try server.start()
        commandServer = server
        statsMonitor.start()

        log.info("libbox service started")
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("stopTunnel reason=\(reason.rawValue, privacy: .public)")
        stopService()
        completionHandler()
    }

    func stopService() {
        statsMonitor.stop()
        platformInterface.reset()

        if let service = boxService {
            try? service.close()
            boxService = nil
        }

        if let server = commandServer {
            try? server.close()
            commandServer = nil
        }
    }

    func writeMessage(_ message: String) {
        commandServer?.writeMessage(message)
        log.info("\(message, privacy: .public)")
    }
}