import Foundation

/// Shared identifiers for the app ↔ Network Extension tunnel.
enum TunnelConstants {
    static let appGroup = "group.com.erebrus.vpn"
    static let tunnelBundleId = "com.erebrus.vpn.ErebrusTunnel"
    static let providerDescription = "Erebrus VPN"
    static let configKey = "singbox_config"
    static let profileNameKey = "profile_name"

    /// App group UserDefaults keys written by the extension.
    enum StatsKeys {
        static let rxBytes = "tunnel_rx_bytes"
        static let txBytes = "tunnel_tx_bytes"
        static let uplinkBps = "tunnel_uplink_bps"
        static let downlinkBps = "tunnel_downlink_bps"
    }
}