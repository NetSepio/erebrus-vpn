import Foundation
import Libbox

/// Bridges libbox traffic counters to the shared app group for the Flutter UI.
final class TunnelStatsMonitor: NSObject, LibboxCommandClientHandlerProtocol, LibboxCommandServerHandlerProtocol {
    private var commandClient: LibboxCommandClient?

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: TunnelConstants.appGroup)
    }

    func start() {
        stop()
        let options = LibboxCommandClientOptions()
        options.command = LibboxCommandStatus
        options.statusInterval = 1_000_000_000

        guard let client = LibboxNewCommandClient(self, options) else { return }
        commandClient = client
        do {
            try client.connect()
        } catch {
            NSLog("[TunnelStatsMonitor] connect failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        if let client = commandClient {
            try? client.disconnect()
            try? client.serviceClose()
        }
        commandClient = nil
    }

    func writeStatus(_ message: LibboxStatusMessage?) {
        guard let message, message.trafficAvailable else { return }
        guard let defaults else { return }
        defaults.set(message.downlinkTotal, forKey: TunnelConstants.StatsKeys.rxBytes)
        defaults.set(message.uplinkTotal, forKey: TunnelConstants.StatsKeys.txBytes)
        defaults.set(message.downlink, forKey: TunnelConstants.StatsKeys.downlinkBps)
        defaults.set(message.uplink, forKey: TunnelConstants.StatsKeys.uplinkBps)
    }

    func connected() {}
    func disconnected(_: String?) {}
    func clearLogs() {}
    func writeLogs(_: LibboxStringIteratorProtocol?) {}
    func writeGroups(_: LibboxOutboundGroupIteratorProtocol?) {}
    func write(_ message: LibboxConnections?) { _ = message }
    func initializeClashMode(_: LibboxStringIteratorProtocol?, currentMode _: String?) {}
    func updateClashMode(_: String?) {}

    func getSystemProxyStatus() -> LibboxSystemProxyStatus? {
        let status = LibboxSystemProxyStatus()
        status.available = false
        status.enabled = false
        return status
    }

    func postServiceClose() {}

    func serviceReload() throws {}

    func setSystemProxyEnabled(_: Bool) throws {}
}