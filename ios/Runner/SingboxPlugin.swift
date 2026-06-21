import CryptoKit
import Flutter
import UIKit

/// iOS stub for `dev.erebrus/singbox` — WireGuard keygen works; tunnel TBD.
final class SingboxBridge {
  static let shared = SingboxBridge()
  static let methodChannel = "dev.erebrus/singbox"
  static let statusChannel = "dev.erebrus/singbox/status"
  static let statsChannel = "dev.erebrus/singbox/stats"

  private var statusSink: FlutterEventSink?
  private(set) var stage = "disconnected"

  func register(with messenger: FlutterBinaryMessenger) {
    let method = FlutterMethodChannel(name: Self.methodChannel, binaryMessenger: messenger)
    method.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "prepare":
        result(true)
      case "start":
        self.stage = "connecting"
        self.emitStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          self.stage = "error"
          self.emitStatus()
        }
        result(nil)
      case "stop":
        self.stage = "disconnected"
        self.emitStatus()
        result(nil)
      case "stage":
        result(self.stage)
      case "genWgKeys":
        result(self.generateWireGuardKeyPair())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let status = FlutterEventChannel(name: Self.statusChannel, binaryMessenger: messenger)
    status.setStreamHandler(StatusStreamHandler(bridge: self))

    let stats = FlutterEventChannel(name: Self.statsChannel, binaryMessenger: messenger)
    stats.setStreamHandler(StatsStreamHandler())
  }

  func emitStatus() {
    statusSink?(stage)
  }

  private func generateWireGuardKeyPair() -> [String: String] {
    let privateKey = Curve25519.KeyAgreement.PrivateKey()
    let publicKey = privateKey.publicKey
    return [
      "private": privateKey.rawRepresentation.base64EncodedString(),
      "public": publicKey.rawRepresentation.base64EncodedString(),
    ]
  }
}

private final class StatusStreamHandler: NSObject, FlutterStreamHandler {
  weak var bridge: SingboxBridge?
  init(bridge: SingboxBridge) { self.bridge = bridge }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    bridge?.statusSink = events
    if let stage = bridge?.stage { events(stage) }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    bridge?.statusSink = nil
    return nil
  }
}

private final class StatsStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    events(["rxBytes": 0, "txBytes": 0, "downlinkBps": 0, "uplinkBps": 0])
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? { nil }
}