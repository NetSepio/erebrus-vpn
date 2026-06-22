import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/platform_capabilities.dart';
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
/// On mobile: Android `VpnService` + libbox AAR, iOS Network Extension.
/// On desktop: bundled sing-box CLI subprocess ([SingboxDesktopRunner]).
class SingboxEngine {
  SingboxEngine._();
  static final SingboxEngine instance = SingboxEngine._();

  static const MethodChannel _method = MethodChannel('dev.erebrus/singbox');
  static const EventChannel _statusChannel = EventChannel('dev.erebrus/singbox/status');
  static const EventChannel _statsChannel = EventChannel('dev.erebrus/singbox/stats');

  final _desktop = SingboxDesktopRunner.instance;

  Stream<VpnStage>? _stage;
  Stream<VpnStats>? _stats;

  bool get _useDesktopRunner => PlatformCapabilities.isDesktop;

  /// Stream of lifecycle stages.
  Stream<VpnStage> get onStage => _stage ??= _useDesktopRunner
      ? _desktop.onStage
      : _statusChannel.receiveBroadcastStream().map((e) => _stageFrom(e as String?));

  /// Stream of byte counters (~1s cadence while connected).
  Stream<VpnStats> get onStats => _stats ??= _useDesktopRunner
      ? _desktop.onStats
      : _statsChannel.receiveBroadcastStream().map((e) => VpnStats.fromMap((e as Map?) ?? const {}));

  /// Desktop-only hint when [prepare] returns false (e.g. missing sing-box CLI).
  String? get desktopPrepareError => _useDesktopRunner ? _desktop.lastError : null;

  Future<bool> prepare() async {
    if (_useDesktopRunner) return _desktop.prepare();
    try {
      return (await _method.invokeMethod<bool>('prepare')) ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> start(String configJson, {String profileName = 'Erebrus'}) async {
    if (_useDesktopRunner) {
      await _desktop.start(configJson, profileName: profileName);
      return;
    }
    await _method.invokeMethod('start', {'config': configJson, 'name': profileName});
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

  /// Routes in-app HTTP/WebView through the local sing-box mixed inbound.
  Future<void> setAppProxy({required String host, required int port}) async {
    if (_useDesktopRunner) return;
    try {
      await _method.invokeMethod('setAppProxy', {'host': host, 'port': port});
    } on PlatformException catch (e) {
      debugPrint('[SingboxEngine] setAppProxy failed: $e');
    }
  }

  Future<void> clearAppProxy() async {
    if (_useDesktopRunner) return;
    try {
      await _method.invokeMethod('clearAppProxy');
    } on PlatformException catch (e) {
      debugPrint('[SingboxEngine] clearAppProxy failed: $e');
    }
  }

  Future<({String private, String public})> generateWireGuardKeyPair() async {
    if (_useDesktopRunner) return WgKeygen.generate();
    try {
      final m = await _method.invokeMapMethod<String, String>('genWgKeys');
      final priv = m?['private'] ?? '';
      final pub = m?['public'] ?? '';
      if (priv.isNotEmpty && pub.isNotEmpty) return (private: priv, public: pub);
    } catch (e) {
      debugPrint('[SingboxEngine] native genWgKeys failed: $e');
    }
    return WgKeygen.generate();
  }
}