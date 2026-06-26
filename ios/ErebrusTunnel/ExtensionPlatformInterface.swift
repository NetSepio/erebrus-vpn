import Foundation
import Libbox
import Network
import NetworkExtension

/// libbox PlatformInterface for iOS Network Extension TUN setup (v1.11 API).
final class ExtensionPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol {
    private weak var tunnel: PacketTunnelProvider?
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var nwMonitor: NWPathMonitor?

    init(_ tunnel: PacketTunnelProvider) {
        self.tunnel = tunnel
    }

    func reset() {
        networkSettings = nil
        nwMonitor?.cancel()
        nwMonitor = nil
    }

    func openTun(_ options: LibboxTunOptionsProtocol?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        try runBlocking { [self] in
            try await openTunAsync(options, ret0_)
        }
    }

    private func openTunAsync(_ options: LibboxTunOptionsProtocol?, _ ret0_: UnsafeMutablePointer<Int32>?) async throws {
        guard let options else {
            throw NSError(domain: "ExtensionPlatformInterface", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Nil TUN options",
            ])
        }
        guard let ret0_ else {
            throw NSError(domain: "ExtensionPlatformInterface", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Nil return pointer",
            ])
        }
        guard let tunnel else {
            throw NSError(domain: "ExtensionPlatformInterface", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Tunnel deallocated",
            ])
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            let dnsBox = try options.getDNSServerAddress()
            let dnsSettings = NEDNSSettings(servers: [dnsBox.value])
            settings.dnsSettings = dnsSettings

            var ipv4Address: [String] = []
            var ipv4Mask: [String] = []
            if let iterator = options.getInet4Address() {
                while iterator.hasNext() {
                    let prefix = iterator.next()!
                    ipv4Address.append(prefix.address())
                    ipv4Mask.append(prefix.mask())
                }
            }

            let ipv4Settings = NEIPv4Settings(addresses: ipv4Address, subnetMasks: ipv4Mask)
            var ipv4Routes: [NEIPv4Route] = []
            if let routeIterator = options.getInet4RouteAddress(), routeIterator.hasNext() {
                while routeIterator.hasNext() {
                    let route = routeIterator.next()!
                    ipv4Routes.append(NEIPv4Route(
                        destinationAddress: route.address(),
                        subnetMask: route.mask()
                    ))
                }
            } else {
                ipv4Routes.append(NEIPv4Route.default())
            }
            ipv4Settings.includedRoutes = ipv4Routes
            settings.ipv4Settings = ipv4Settings

            if let iterator = options.getInet6Address() {
                var ipv6Address: [String] = []
                var ipv6Prefixes: [NSNumber] = []
                while iterator.hasNext() {
                    let prefix = iterator.next()!
                    ipv6Address.append(prefix.address())
                    ipv6Prefixes.append(NSNumber(value: prefix.prefix()))
                }
                if !ipv6Address.isEmpty {
                    let ipv6Settings = NEIPv6Settings(addresses: ipv6Address, networkPrefixLengths: ipv6Prefixes)
                    var ipv6Routes: [NEIPv6Route] = []
                    if let routeIterator = options.getInet6RouteAddress(), routeIterator.hasNext() {
                        while routeIterator.hasNext() {
                            let route = routeIterator.next()!
                            ipv6Routes.append(NEIPv6Route(
                                destinationAddress: route.address(),
                                networkPrefixLength: NSNumber(value: route.prefix())
                            ))
                        }
                    } else {
                        ipv6Routes.append(NEIPv6Route.default())
                    }
                    ipv6Settings.includedRoutes = ipv6Routes
                    settings.ipv6Settings = ipv6Settings
                }
            }
        }

        networkSettings = settings
        try await tunnel.setTunnelNetworkSettings(settings)

        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            ret0_.pointee = tunFd
            return
        }

        let tunFdFromLoop = LibboxGetTunnelFileDescriptor()
        if tunFdFromLoop != -1 {
            ret0_.pointee = tunFdFromLoop
        } else {
            throw NSError(domain: "ExtensionPlatformInterface", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Missing TUN file descriptor",
            ])
        }
    }

    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        guard let listener else { return }
        let monitor = NWPathMonitor()
        nwMonitor = monitor
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onUpdateDefaultInterface(listener, path: path)
            semaphore.signal()
            monitor.pathUpdateHandler = { [weak self] path in
                self?.onUpdateDefaultInterface(listener, path: path)
            }
        }
        monitor.start(queue: DispatchQueue.global())
        semaphore.wait()
    }

    private func onUpdateDefaultInterface(
        _ listener: LibboxInterfaceUpdateListenerProtocol,
        path: Network.NWPath
    ) {
        guard path.status != .unsatisfied,
              let iface = path.availableInterfaces.first
        else {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        listener.updateDefaultInterface(
            iface.name,
            interfaceIndex: Int32(iface.index),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }

    func closeDefaultInterfaceMonitor(_: LibboxInterfaceUpdateListenerProtocol?) throws {
        nwMonitor?.cancel()
        nwMonitor = nil
    }

    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        guard let nwMonitor else {
            throw NSError(domain: "ExtensionPlatformInterface", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "NWMonitor not started",
            ])
        }
        let path = nwMonitor.currentPath
        if path.status == .unsatisfied {
            return NetworkInterfaceArray([])
        }
        var interfaces: [LibboxNetworkInterface] = []
        for iface in path.availableInterfaces {
            let item = LibboxNetworkInterface()
            item.name = iface.name
            item.index = Int32(iface.index)
            switch iface.type {
            case .wifi: item.type = LibboxInterfaceTypeWIFI
            case .cellular: item.type = LibboxInterfaceTypeCellular
            case .wiredEthernet: item.type = LibboxInterfaceTypeEthernet
            default: item.type = LibboxInterfaceTypeOther
            }
            interfaces.append(item)
        }
        return NetworkInterfaceArray(interfaces)
    }

    private final class NetworkInterfaceArray: NSObject, LibboxNetworkInterfaceIteratorProtocol {
        private var iterator: IndexingIterator<[LibboxNetworkInterface]>
        private var nextValue: LibboxNetworkInterface?

        init(_ array: [LibboxNetworkInterface]) {
            iterator = array.makeIterator()
        }

        func hasNext() -> Bool {
            nextValue = iterator.next()
            return nextValue != nil
        }

        func next() -> LibboxNetworkInterface? { nextValue }
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

    func uid(byPackageName _: String?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        ret0_?.pointee = -1
    }

    func clearDNSCache() {
        guard let networkSettings, let tunnel else { return }
        try? runBlocking {
            tunnel.reasserting = true
            defer { tunnel.reasserting = false }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                tunnel.setTunnelNetworkSettings(nil) { _ in continuation.resume() }
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                tunnel.setTunnelNetworkSettings(networkSettings) { _ in continuation.resume() }
            }
        }
    }

    func readWIFIState() -> LibboxWIFIState? {
        let network = try? runBlocking { await NEHotspotNetwork.fetchCurrent() }
        guard let network else { return nil }
        return LibboxNewWIFIState(network.ssid, network.bssid)
    }

    func writeLog(_ message: String?) {
        guard let message else { return }
        tunnel?.writeMessage(message)
    }

    func send(_: LibboxNotification?) throws {}
}