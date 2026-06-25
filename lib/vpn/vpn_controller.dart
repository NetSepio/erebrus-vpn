import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../platform/desktop_prefs_storage.dart';
import '../platform/platform_capabilities.dart';
import '../platform/secure_storage.dart';
import '../settings/app_settings_controller.dart';
import '../settings/split_tunnel_config.dart';
import 'gateway_client.dart';
import 'gateway_controller.dart';
import 'gateway_errors.dart';
import 'egress_ip_probe.dart';
import 'singbox_desktop_runner.dart';
import 'singbox_engine.dart';
import 'vpn_models.dart';
import 'vpn_session_store.dart';

/// Provisions a VPN client on a node through the gateway and returns the
/// credential bundle. Injected so the controller stays independent of the HTTP
/// layer (api.dart provides the real implementation:
/// POST /api/v2/vpn/clients { name, node_id, wg_public_key }).
typedef Provisioner = Future<CredentialBundle> Function({
  required VpnNode node,
  required String wgPublicKey,
  required String name,
});

/// Drives the single sing-box engine for every protocol. The UI binds to its
/// observables; the connect flow provisions a client, builds the per-transport
/// sing-box config (WireGuard as the endpoint), and — for Auto/Stealth — falls
/// back across transports until one establishes.
class VpnController extends GetxController {
  VpnController({Provisioner? provisioner}) : _provision = provisioner;

  final _engine = SingboxEngine.instance;
  final _storage = ErebrusSecureStorage.instance;
  Provisioner? _provision;

  // observables
  final stage = VpnStage.disconnected.obs;
  final mode = ConnectMode.auto.obs;
  final activeTransport = Rxn<Transport>();
  final selectedNode = Rxn<VpnNode>();
  final stats = const VpnStats().obs;
  final error = RxnString();
  final killSwitchBlocking = false.obs;
  final egressIp = RxnString();
  final egressIpLoading = false.obs;

  StreamSubscription<VpnStage>? _stageSub;
  StreamSubscription<VpnStats>? _statsSub;
  bool _wasConnected = false;
  bool _userDisconnecting = false;
  bool _syncingNative = false;
  bool _connectInProgress = false;

  static const _kWgPrivate = 'erebrus_wg_private';
  static const _kWgPublic = 'erebrus_wg_public';

  bool get isConnected => stage.value == VpnStage.connected;
  bool get isBusy => stage.value == VpnStage.connecting || stage.value == VpnStage.disconnecting;

  /// Allows late injection of the gateway provisioner (e.g. after login).
  set provisioner(Provisioner p) => _provision = p;

  @override
  void onInit() {
    super.onInit();
    _stageSub = _engine.onStage.listen((s) {
      if (killSwitchBlocking.value && s == VpnStage.connected) {
        stage.value = VpnStage.error;
        return;
      }
      stage.value = s;
      if (s == VpnStage.connected) {
        _wasConnected = true;
        killSwitchBlocking.value = false;
        unawaited(_syncAppProxy(enabled: true));
        unawaited(_probeEgressIp());
      }
      if (s == VpnStage.disconnected || s == VpnStage.error) {
        unawaited(_syncAppProxy(enabled: false));
        egressIp.value = null;
        egressIpLoading.value = false;
        activeTransport.value = null;
        if (_wasConnected &&
            !_userDisconnecting &&
            !_syncingNative &&
            !_connectInProgress &&
            _killSwitchEnabled) {
          unawaited(_engageKillSwitch());
        } else if (_userDisconnecting) {
          _wasConnected = false;
          _userDisconnecting = false;
        }
      }
    });
    _statsSub = _engine.onStats.listen((s) => stats.value = s);
    unawaited(syncWithNative());
  }

  /// Reconciles Flutter observables with the native tunnel and persisted session.
  /// Call on cold start and whenever the app returns to the foreground.
  Future<void> syncWithNative() async {
    _syncingNative = true;
    try {
      final native = await _engine.stage().catchError((_) => VpnStage.disconnected);
      final session = await VpnSessionStore.load();

      if (native == VpnStage.connected) {
        _wasConnected = true;
        _userDisconnecting = false;
        killSwitchBlocking.value = false;
        stage.value = VpnStage.connected;
        error.value = null;
        if (session?.killSwitchActive == true) {
          await VpnSessionStore.clear();
          debugPrint('[VPN] sync: cleared stale kill-switch session (tunnel is up)');
        }
        _applySession(session);
        unawaited(_syncAppProxy(enabled: true));
        unawaited(_probeEgressIp());
        debugPrint(
          '[VPN] sync: native connected'
          '${session != null ? ' · ${session.nodeName} (${session.transport.label})' : ''}',
        );
        return;
      }

      if (killSwitchBlocking.value || session?.killSwitchActive == true) {
        _wasConnected = true;
        stage.value = VpnStage.error;
        error.value = 'Kill switch active — traffic blocked until you reconnect';
        killSwitchBlocking.value = true;
        _applySession(session);
        debugPrint('[VPN] sync: kill switch session restored');
        return;
      }

      stage.value = native;
      if (native == VpnStage.disconnected || native == VpnStage.error) {
        _wasConnected = false;
        activeTransport.value = null;
        if (session != null) await VpnSessionStore.clear();
      }
      debugPrint('[VPN] sync: native ${native.name}');
    } finally {
      _syncingNative = false;
    }
  }

  void _applySession(VpnSessionSnapshot? session) {
    if (session == null) return;
    mode.value = session.mode;
    activeTransport.value = session.transport;
    final matched = _matchNode(session);
    if (matched != null) {
      selectedNode.value = matched;
    } else if (isConnected || killSwitchBlocking.value) {
      selectedNode.value = session.toNode();
    }
  }

  VpnNode? _matchNode(VpnSessionSnapshot session) {
    if (!Get.isRegistered<GatewayController>()) return null;
    for (final n in Get.find<GatewayController>().nodes) {
      if (n.id == session.nodeId) return n;
    }
    return null;
  }

  void reconcileNodeFromGateway() {
    if (!isConnected && !killSwitchBlocking.value) return;
    final current = selectedNode.value;
    if (current == null) return;
    if (!Get.isRegistered<GatewayController>()) return;
    for (final n in Get.find<GatewayController>().nodes) {
      if (n.id == current.id) {
        selectedNode.value = n;
        return;
      }
    }
  }

  @override
  void onClose() {
    _stageSub?.cancel();
    _statsSub?.cancel();
    super.onClose();
  }

  void setMode(ConnectMode m) => mode.value = m;
  void selectNode(VpnNode n) => selectedNode.value = n;
  void clearSelectedNode() => selectedNode.value = null;

  /// Wipes locally stored WG keys and disconnects (used on sign-out / reset).
  Future<void> resetLocalVpnData() async {
    await disconnect().catchError((_) {});
    selectedNode.value = null;
    activeTransport.value = null;
    await _deleteStoredSecret(_kWgPrivate);
    await _deleteStoredSecret(_kWgPublic);
    await VpnSessionStore.clear();
  }

  /// Connects to [node] (or the currently selected node) using the current mode,
  /// trying each candidate transport in order until one connects.
  Future<void> connect({VpnNode? node}) async {
    final target = node ?? selectedNode.value;
    if (target == null) {
      error.value = 'Select a node first';
      return;
    }
    if (_provision == null) {
      error.value = 'VPN provisioning is not configured';
      return;
    }
    _userDisconnecting = false;
    _connectInProgress = true;
    _wasConnected = false;
    if (killSwitchBlocking.value) {
      await _engine.stop().catchError((_) {});
      killSwitchBlocking.value = false;
      await VpnSessionStore.clear();
    }
    selectedNode.value = target;
    error.value = null;
    stage.value = VpnStage.connecting;

    try {
      if (!await _engine.prepare()) {
        error.value = _engine.desktopPrepareError ??
            (PlatformCapabilities.isDesktop
                ? 'sing-box missing — run ./scripts/fetch-singbox-cli.sh macos from the repo root'
                : 'VPN permission denied');
        stage.value = VpnStage.error;
        return;
      }
      final keys = await _ensureWgKeys();
      final bundle = await _provision!(node: target, wgPublicKey: keys.public, name: _clientName());

      // Filter candidate transports to what this node/bundle actually supports.
      final candidates = mode.value.transports.where((t) {
        if (t == Transport.wireguard) return true;
        return bundle.hasStealth && target.supportsStealth;
      }).toList();
      if (candidates.isEmpty) {
        error.value = 'No usable transport for this node';
        stage.value = VpnStage.error;
        return;
      }

      debugPrint(
        '[VPN] mode=${mode.value.label} · try order: '
        '${candidates.map((t) => t.label).join(' → ')}',
      );

      for (final t in candidates) {
        try {
          final config = SingboxConfigBuilder.build(
            bundle: bundle,
            transport: t,
            clientPrivateKey: keys.private,
            // Desktop CLI: local mixed proxy + system HTTP/SOCKS (no TUN). TUN on
            // unsigned macOS breaks DNS for Safari/Chrome even when the in-app
            // egress probe (explicit 127.0.0.1:10808) works.
            useSystemTunnel: !PlatformCapabilities.isDesktop,
          );
          activeTransport.value = t;
          final srv = bundle.serverPublicKey;
          final srvShort = srv.length > 8 ? '${srv.substring(0, 8)}…' : srv;
          debugPrint(
            '[VPN] trying ${t.label} → ${bundle.endpoint} '
            '(wg ${bundle.address}, srv $srvShort)',
          );
          final ok = await _armAndStart(
            _engine.start(
              jsonEncode(config),
              profileName: 'Erebrus · ${target.name}',
              splitTunnel: _splitTunnelConfig(),
            ),
          );
          debugPrint('[VPN] ${t.label} finished stage=${stage.value.name} ok=$ok');
          if (ok) {
            _wasConnected = true;
            debugPrint(
              '[VPN] connected · mode=${mode.value.label} · transport=${t.label} · '
              'config=${t == Transport.wireguard ? "direct-wg" : "stealth-singbox"}',
            );
            await VpnSessionStore.save(
              node: target,
              transport: t,
              mode: mode.value,
              profileName: 'Erebrus · ${target.name}',
            );
            return;
          }
        } catch (e, st) {
          debugPrint('[VPN] transport ${t.label} failed: $e\n$st');
        }
        _wasConnected = false;
        await _engine.stop().catchError((_) {});
      }
      _wasConnected = false;
      error.value = _engine.desktopPrepareError ??
          SingboxDesktopRunner.instance.lastError ??
          'Could not connect — run ./scripts/setup-macos-dev.sh, then try Stealth or another server';
      stage.value = VpnStage.error;
    } on GatewayException catch (e) {
      _wasConnected = false;
      error.value = friendlyGatewayError(e, nodeName: target.name);
      stage.value = VpnStage.error;
    } catch (e) {
      _wasConnected = false;
      error.value = friendlyGatewayError(e, nodeName: target.name);
      stage.value = VpnStage.error;
    } finally {
      _connectInProgress = false;
    }
  }

  Future<void> disconnect() async {
    _userDisconnecting = true;
    killSwitchBlocking.value = false;
    stage.value = VpnStage.disconnecting;
    await _syncAppProxy(enabled: false);
    try {
      await _engine.stop();
      stage.value = await _engine.stage();
    } catch (_) {
      stage.value = VpnStage.disconnected;
    }
    _wasConnected = false;
    activeTransport.value = null;
    error.value = null;
    egressIp.value = null;
    egressIpLoading.value = false;
    await VpnSessionStore.clear();
  }

  Future<void> releaseKillSwitchIfActive() async {
    if (!killSwitchBlocking.value) return;
    killSwitchBlocking.value = false;
    _wasConnected = false;
    await _engine.stop().catchError((_) {});
    stage.value = VpnStage.disconnected;
    error.value = null;
    egressIp.value = null;
    egressIpLoading.value = false;
    await VpnSessionStore.clear();
  }

  Future<void> _syncAppProxy({required bool enabled}) async {
    if (enabled) {
      await _engine.setAppProxy(
        host: SingboxConfigBuilder.localProxyHost,
        port: SingboxConfigBuilder.localProxyPort,
      );
      return;
    }
    await _engine.clearAppProxy();
  }

  Future<void> _probeEgressIp() async {
    if (!isConnected || killSwitchBlocking.value) return;
    egressIpLoading.value = true;
    try {
      final ip = await EgressIpProbe.fetch(useTunnelProxy: true);
      if (isConnected) egressIp.value = ip;
      debugPrint('[VPN] egress IP probe → ${ip ?? "failed"}');
    } finally {
      egressIpLoading.value = false;
    }
  }

  bool get _killSwitchEnabled =>
      Get.isRegistered<AppSettingsController>() &&
      Get.find<AppSettingsController>().killSwitchEnabled.value;

  SplitTunnelConfig _splitTunnelConfig() {
    if (!Get.isRegistered<AppSettingsController>()) return const SplitTunnelConfig();
    return Get.find<AppSettingsController>().activeSplitTunnelConfig();
  }

  Future<void> _engageKillSwitch() async {
    if (killSwitchBlocking.value || !_killSwitchEnabled) return;
    killSwitchBlocking.value = true;
    error.value = 'Kill switch active — traffic blocked until you reconnect';
    stage.value = VpnStage.error;
    try {
      await _engine.stop().catchError((_) {});
      final config = SingboxConfigBuilder.killSwitchBlockConfig();
      await _engine.start(
        jsonEncode(config),
        profileName: 'Erebrus · Kill switch',
        splitTunnel: _splitTunnelConfig(),
      );
      final node = selectedNode.value;
      if (node != null) {
        await VpnSessionStore.save(
          node: node,
          transport: activeTransport.value ?? Transport.wireguard,
          mode: mode.value,
          profileName: 'Erebrus · Kill switch',
          killSwitchActive: true,
        );
      }
      debugPrint('[VPN] kill switch engaged — replaced tunnel with block config');
    } catch (e) {
      debugPrint('[VPN] kill switch engage failed: $e');
      killSwitchBlocking.value = false;
    }
  }

  Future<void> toggle() => isConnected ? disconnect() : connect();

  /// Subscribes before [startFuture] completes so fast native errors are not missed.
  Future<bool> _armAndStart(
    Future<void> startFuture, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final completer = Completer<bool>();
    late StreamSubscription<VpnStage> sub;
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    sub = _engine.onStage.listen((s) {
      if (s == VpnStage.connected && !completer.isCompleted) completer.complete(true);
      if (s == VpnStage.error && !completer.isCompleted) completer.complete(false);
    });
    try {
      await startFuture;
      final now = await _engine.stage();
      if (now == VpnStage.connected) return true;
      if (now == VpnStage.error) return false;
      return await completer.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  Future<({String private, String public})> _ensureWgKeys() async {
    final priv = await _readStoredSecret(_kWgPrivate);
    final pub = await _readStoredSecret(_kWgPublic);
    if (priv != null && priv.isNotEmpty && pub != null && pub.isNotEmpty) {
      return (private: priv, public: pub);
    }
    final keys = await _engine.generateWireGuardKeyPair();
    await _writeStoredSecret(_kWgPrivate, keys.private);
    await _writeStoredSecret(_kWgPublic, keys.public);
    return keys;
  }

  Future<String?> _readStoredSecret(String key) {
    if (PlatformCapabilities.isDesktop) {
      return DesktopPrefsStorage.read(key);
    }
    return _storage.read(key: key);
  }

  Future<void> _writeStoredSecret(String key, String value) {
    if (PlatformCapabilities.isDesktop) {
      return DesktopPrefsStorage.write(key, value);
    }
    return _storage.write(key: key, value: value);
  }

  Future<void> _deleteStoredSecret(String key) async {
    try {
      if (PlatformCapabilities.isDesktop) {
        await DesktopPrefsStorage.delete(key);
      } else {
        await _storage.delete(key: key);
      }
    } catch (_) {}
  }

  String _clientName() {
    final platform = defaultTargetPlatform.name;
    return 'erebrus-$platform-${DateTime.now().millisecondsSinceEpoch % 100000}';
  }
}
