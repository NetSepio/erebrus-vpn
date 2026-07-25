import Foundation
import Libbox
import Network
import NetworkExtension

/// libbox platform hooks for the sandboxed macOS Packet Tunnel Provider.
final class ExtensionPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol {
    private weak var tunnel: PacketTunnelProvider?
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var pathMonitor: NWPathMonitor?

    init(_ tunnel: PacketTunnelProvider) {
        self.tunnel = tunnel
    }

    func reset() {
        networkSettings = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        try runBlocking { [self] in
            try await openTunAsync(options, ret0_)
        }
    }

    private func openTunAsync(
        _ options: LibboxTunOptionsProtocol?,
        _ result: UnsafeMutablePointer<Int32>?
    ) async throws {
        guard let options else {
            throw platformError("Nil TUN options")
        }
        guard let result else {
            throw platformError("Nil TUN return pointer")
        }
        guard let tunnel else {
            throw platformError("Tunnel provider was deallocated")
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            let dnsAddress = try options.getDNSServerAddress()
            settings.dnsSettings = NEDNSSettings(servers: [dnsAddress.value])

            var ipv4Addresses: [String] = []
            var ipv4Masks: [String] = []
            if let iterator = options.getInet4Address() {
                while iterator.hasNext() {
                    guard let prefix = iterator.next() else { continue }
                    ipv4Addresses.append(prefix.address())
                    ipv4Masks.append(prefix.mask())
                }
            }

            let ipv4 = NEIPv4Settings(addresses: ipv4Addresses, subnetMasks: ipv4Masks)
            var ipv4Routes: [NEIPv4Route] = []
            if let iterator = options.getInet4RouteAddress(), iterator.hasNext() {
                while iterator.hasNext() {
                    guard let route = iterator.next() else { continue }
                    ipv4Routes.append(
                        NEIPv4Route(
                            destinationAddress: route.address(),
                            subnetMask: route.mask()
                        )
                    )
                }
            } else {
                ipv4Routes.append(.default())
            }
            ipv4.includedRoutes = ipv4Routes
            settings.ipv4Settings = ipv4

            if let iterator = options.getInet6Address() {
                var addresses: [String] = []
                var prefixes: [NSNumber] = []
                while iterator.hasNext() {
                    guard let prefix = iterator.next() else { continue }
                    addresses.append(prefix.address())
                    prefixes.append(NSNumber(value: prefix.prefix()))
                }
                if !addresses.isEmpty {
                    let ipv6 = NEIPv6Settings(
                        addresses: addresses,
                        networkPrefixLengths: prefixes
                    )
                    var routes: [NEIPv6Route] = []
                    if let routeIterator = options.getInet6RouteAddress(),
                       routeIterator.hasNext() {
                        while routeIterator.hasNext() {
                            guard let route = routeIterator.next() else { continue }
                            routes.append(
                                NEIPv6Route(
                                    destinationAddress: route.address(),
                                    networkPrefixLength: NSNumber(value: route.prefix())
                                )
                            )
                        }
                    } else {
                        routes.append(.default())
                    }
                    ipv6.includedRoutes = routes
                    settings.ipv6Settings = ipv6
                }
            }
        }

        networkSettings = settings
        try await tunnel.setTunnelNetworkSettings(settings)

        // NetworkExtension does not publish the packet-flow descriptor as a
        // public property. libbox uses the same provider bridge as the working
        // iOS implementation and falls back to its protected descriptor hook.
        if let descriptor = tunnel.packetFlow.value(
            forKeyPath: "socket.fileDescriptor"
        ) as? Int32 {
            result.pointee = descriptor
            return
        }

        let descriptor = LibboxGetTunnelFileDescriptor()
        guard descriptor != -1 else {
            throw platformError("Missing TUN file descriptor")
        }
        result.pointee = descriptor
    }

    func startDefaultInterfaceMonitor(
        _ listener: LibboxInterfaceUpdateListenerProtocol?
    ) throws {
        guard let listener else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        let ready = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { [weak self] path in
            self?.updateDefaultInterface(listener, path: path)
            ready.signal()
            monitor.pathUpdateHandler = { [weak self] path in
                self?.updateDefaultInterface(listener, path: path)
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        ready.wait()
    }

    private func updateDefaultInterface(
        _ listener: LibboxInterfaceUpdateListenerProtocol,
        path: Network.NWPath
    ) {
        guard path.status != .unsatisfied,
              let interface = path.availableInterfaces.first else {
            listener.updateDefaultInterface(
                "",
                interfaceIndex: -1,
                isExpensive: false,
                isConstrained: false
            )
            return
        }
        listener.updateDefaultInterface(
            interface.name,
            interfaceIndex: Int32(interface.index),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }

    func closeDefaultInterfaceMonitor(
        _: LibboxInterfaceUpdateListenerProtocol?
    ) throws {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        guard let pathMonitor else {
            throw platformError("Default-interface monitor is not running")
        }
        let path = pathMonitor.currentPath
        guard path.status != .unsatisfied else {
            return NetworkInterfaceArray([])
        }

        let interfaces = path.availableInterfaces.map { interface in
            let item = LibboxNetworkInterface()
            item.name = interface.name
            item.index = Int32(interface.index)
            switch interface.type {
            case .wifi:
                item.type = LibboxInterfaceTypeWIFI
            case .cellular:
                item.type = LibboxInterfaceTypeCellular
            case .wiredEthernet:
                item.type = LibboxInterfaceTypeEthernet
            default:
                item.type = LibboxInterfaceTypeOther
            }
            return item
        }
        return NetworkInterfaceArray(interfaces)
    }

    private final class NetworkInterfaceArray: NSObject, LibboxNetworkInterfaceIteratorProtocol {
        private var iterator: IndexingIterator<[LibboxNetworkInterface]>
        private var nextValue: LibboxNetworkInterface?

        init(_ interfaces: [LibboxNetworkInterface]) {
            iterator = interfaces.makeIterator()
        }

        func hasNext() -> Bool {
            nextValue = iterator.next()
            return nextValue != nil
        }

        func next() -> LibboxNetworkInterface? {
            nextValue
        }
    }

    func usePlatformAutoDetectControl() -> Bool { false }
    func autoDetectControl(_: Int32) throws {}
    func useProcFS() -> Bool { false }
    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { true }

    func findConnectionOwner(
        _: Int32,
        sourceAddress _: String?,
        sourcePort _: Int32,
        destinationAddress _: String?,
        destinationPort _: Int32,
        ret0_: UnsafeMutablePointer<Int32>?
    ) throws {
        ret0_?.pointee = -1
    }

    func packageName(byUid _: Int32, error: NSErrorPointer) -> String {
        _ = error
        return ""
    }

    func uid(
        byPackageName _: String?,
        ret0_: UnsafeMutablePointer<Int32>?
    ) throws {
        ret0_?.pointee = -1
    }

    func clearDNSCache() {
        guard let networkSettings, let tunnel else { return }
        try? runBlocking {
            tunnel.reasserting = true
            defer { tunnel.reasserting = false }
            await withCheckedContinuation { continuation in
                tunnel.setTunnelNetworkSettings(nil) { _ in
                    continuation.resume()
                }
            }
            await withCheckedContinuation { continuation in
                tunnel.setTunnelNetworkSettings(networkSettings) { _ in
                    continuation.resume()
                }
            }
        }
    }

    /// Wi-Fi SSID access is not required for tunnel routing and would add a
    /// location/privacy dependency to the Mac App Store build.
    func readWIFIState() -> LibboxWIFIState? { nil }

    func writeLog(_ message: String?) {
        guard let message else { return }
        tunnel?.writeMessage(message)
    }

    func send(_: LibboxNotification?) throws {}

    private func platformError(_ message: String) -> NSError {
        NSError(
            domain: "ExtensionPlatformInterface",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
