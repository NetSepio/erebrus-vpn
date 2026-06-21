import 'dart:async';
import 'package:flutter/services.dart';

/// Lifecycle stages reported by the native tunnel.
enum VpnStage { disconnected, connecting, connected, disconnecting, error }

VpnStage _stageFrom(String? s) => switch (s) {
      'connecting' => VpnStage.connecting,
      'connected' => VpnStage.connected,
      'disconnecting' => VpnStage.disconnecting,
      'error' => VpnStage.error,
      _ => VpnStage.disconnected,
    };

/// Cumulative tunnel byte counters surfaced by the engine.
class VpnStats {
  const VpnStats({this.rxBytes = 0, this.txBytes = 0, this.uplinkBps = 0, this.downlinkBps = 0});
  final int rxBytes;
  final int txBytes;
  final int uplinkBps;
  final int downlinkBps;

  factory VpnStats.fromMap(Map<dynamic, dynamic> m) => VpnStats(
        rxBytes: (m['rx_bytes'] as num?)?.toInt() ?? 0,
        txBytes: (m['tx_bytes'] as num?)?.toInt() ?? 0,
        uplinkBps: (m['uplink_bps'] as num?)?.toInt() ?? 0,
        downlinkBps: (m['downlink_bps'] as num?)?.toInt() ?? 0,
      );
}

/// Dart facade over the native sing-box (libbox) tunnel.
///
/// This is the single integration seam: the Android `VpnService` +
/// `libbox.so`/AAR and the iOS `NEPacketTunnelProvider` + `Libbox.framework`
/// implement these channels. The same engine drives WireGuard *and* the stealth
/// carriers — WireGuard is just an endpoint inside the sing-box config we hand
/// it (see [SingboxConfigBuilder]). The legacy `wireguard_flutter` path is
/// retired in favor of this unified engine.
///
/// Channel contract (see docs/STEALTH_CLIENT.md):
///   method  dev.erebrus/singbox          start(configJson) / stop() / stage() / prepare()
///   event   dev.erebrus/singbox/status   String stage
///   event   dev.erebrus/singbox/stats    Map stats (1s cadence)
class SingboxEngine {
  SingboxEngine._();
  static final SingboxEngine instance = SingboxEngine._();

  static const MethodChannel _method = MethodChannel('dev.erebrus/singbox');
  static const EventChannel _statusChannel = EventChannel('dev.erebrus/singbox/status');
  static const EventChannel _statsChannel = EventChannel('dev.erebrus/singbox/stats');

  Stream<VpnStage>? _stage;
  Stream<VpnStats>? _stats;

  /// Stream of lifecycle stages.
  Stream<VpnStage> get onStage =>
      _stage ??= _statusChannel.receiveBroadcastStream().map((e) => _stageFrom(e as String?));

  /// Stream of byte counters (~1s cadence while connected).
  Stream<VpnStats> get onStats => _stats ??=
      _statsChannel.receiveBroadcastStream().map((e) => VpnStats.fromMap((e as Map?) ?? const {}));

  /// Requests the OS VPN permission (Android `VpnService.prepare`; no-op on iOS
  /// where the system prompts on first start). Returns true if granted.
  Future<bool> prepare() async {
    try {
      return (await _method.invokeMethod<bool>('prepare')) ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Starts the tunnel with a sing-box config (JSON-encoded). [profileName] is
  /// shown in the OS VPN/notification UI.
  Future<void> start(String configJson, {String profileName = 'Erebrus'}) async {
    await _method.invokeMethod('start', {'config': configJson, 'name': profileName});
  }

  /// Stops the tunnel.
  Future<void> stop() async {
    await _method.invokeMethod('stop');
  }

  /// Polls the current stage (used to resync state on app resume).
  Future<VpnStage> stage() async {
    final s = await _method.invokeMethod<String>('stage');
    return _stageFrom(s);
  }

  /// Generates a WireGuard (x25519) keypair natively via libbox. Returns
  /// base64-encoded {private, public}. The private key never leaves the device.
  Future<({String private, String public})> generateWireGuardKeyPair() async {
    final m = await _method.invokeMapMethod<String, String>('genWgKeys');
    return (private: m?['private'] ?? '', public: m?['public'] ?? '');
  }
}
