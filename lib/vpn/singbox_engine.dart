import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/platform_capabilities.dart';
import '../settings/split_tunnel_config.dart';
import 'singbox_desktop_runner.dart';
import 'wg_keygen.dart';

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
  const VpnStats({
    this.rxBytes = 0,
    this.txBytes = 0,
    this.uplinkBps = 0,
    this.downlinkBps = 0,
  });
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
/// On mobile: Android `VpnService` + libbox AAR, iOS Network Extension.
/// On desktop: bundled sing-box CLI subprocess ([SingboxDesktopRunner]).
class SingboxEngine {
  SingboxEngine._();
  static final SingboxEngine instance = SingboxEngine._();

  static const MethodChannel _method = MethodChannel('dev.erebrus/singbox');
  static const EventChannel _statusChannel = EventChannel(
    'dev.erebrus/singbox/status',
  );
  static const EventChannel _statsChannel = EventChannel(
    'dev.erebrus/singbox/stats',
  );

  final _desktop = SingboxDesktopRunner.instance;

  Stream<VpnStage>? _stage;
  Stream<VpnStats>? _stats;

  bool get _useDesktopRunner => PlatformCapabilities.isDesktop;

  /// Stream of lifecycle stages.
  Stream<VpnStage> get onStage => _stage ??= _useDesktopRunner
      ? _desktop.onStage
      : _statusChannel.receiveBroadcastStream().map(
          (e) => _stageFrom(e as String?),
        );

  /// Stream of byte counters (~1s cadence while connected).
  Stream<VpnStats> get onStats => _stats ??= _useDesktopRunner
      ? _desktop.onStats
      : _statsChannel.receiveBroadcastStream().map(
          (e) => VpnStats.fromMap((e as Map?) ?? const {}),
        );

  /// Desktop-only hint when [prepare] returns false (e.g. missing sing-box CLI).
  String? get desktopPrepareError =>
      _useDesktopRunner ? _desktop.lastError : null;

  /// Native sing-box start failure (Android/iOS), when the tunnel errors before connect.
  Future<String?> lastTunnelError() async {
    if (_useDesktopRunner) return _desktop.lastError;
    try {
      return await _method.invokeMethod<String>('lastError');
    } on PlatformException {
      return null;
    }
  }

  Future<bool> prepare() async {
    if (_useDesktopRunner) return _desktop.prepare();
    try {
      return (await _method.invokeMethod<bool>('prepare')) ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> start(
    String configJson, {
    String profileName = 'Erebrus',
    SplitTunnelConfig splitTunnel = const SplitTunnelConfig(),
  }) async {
    if (_useDesktopRunner) {
      await _desktop.start(configJson, profileName: profileName);
      return;
    }
    await _method.invokeMethod('start', {
      'config': configJson,
      'name': profileName,
      'splitTunnelEnabled': splitTunnel.enabled,
      'splitTunnelMode': splitTunnel.mode.name,
      'splitTunnelPackages': splitTunnel.packages,
    });
  }

  Future<void> stop() async {
    if (_useDesktopRunner) {
      await _desktop.stop();
      return;
    }
    await _method.invokeMethod('stop');
    // stop() is async via startService — wait until the TUN is actually torn down.
    for (var i = 0; i < 40; i++) {
      final s = await _method.invokeMethod<String>('stage');
      if (s == 'disconnected') return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    debugPrint('[SingboxEngine] stop: timed out waiting for disconnected');
  }

  Future<VpnStage> stage() async {
    if (_useDesktopRunner) return _stageFrom(_desktop.stage);
    final s = await _method.invokeMethod<String>('stage');
    return _stageFrom(s);
  }

  /// Legacy optional WebView proxy override. Current mobile builds include the
  /// app in the system TUN and do not depend on this capability for routing.
  Future<bool> setAppProxy({required String host, required int port}) async {
    if (_useDesktopRunner) return true;
    try {
      return await _method.invokeMethod('setAppProxy', {
                'host': host,
                'port': port,
              })
              as bool? ??
          false;
    } on MissingPluginException catch (e) {
      debugPrint('[SingboxEngine] setAppProxy unsupported: $e');
      return false;
    } on PlatformException catch (e) {
      debugPrint('[SingboxEngine] setAppProxy failed: $e');
      return false;
    }
  }

  Future<bool> clearAppProxy() async {
    if (_useDesktopRunner) return true;
    try {
      return await _method.invokeMethod('clearAppProxy') as bool? ?? false;
    } on MissingPluginException catch (e) {
      debugPrint('[SingboxEngine] clearAppProxy unsupported: $e');
      return false;
    } on PlatformException catch (e) {
      debugPrint('[SingboxEngine] clearAppProxy failed: $e');
      return false;
    }
  }

  /// Configures iOS VPN On Demand. Other platforms retain their existing
  /// app-launch auto-connect behavior and report this capability as absent.
  Future<bool> setOnDemandEnabled(bool enabled) async {
    if (_useDesktopRunner) return false;
    try {
      return await _method.invokeMethod<bool>('setOnDemandEnabled', {
            'enabled': enabled,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('[SingboxEngine] setOnDemandEnabled failed: $e');
      return false;
    }
  }

  Future<({String private, String public})> generateWireGuardKeyPair() async {
    if (_useDesktopRunner) return WgKeygen.generate();
    try {
      final m = await _method.invokeMapMethod<String, String>('genWgKeys');
      final priv = m?['private'] ?? '';
      final pub = m?['public'] ?? '';
      if (priv.isNotEmpty && pub.isNotEmpty) {
        return (private: priv, public: pub);
      }
    } catch (e) {
      debugPrint('[SingboxEngine] native genWgKeys failed: $e');
    }
    return WgKeygen.generate();
  }
}
