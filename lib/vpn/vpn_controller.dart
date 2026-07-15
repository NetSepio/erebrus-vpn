import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Socket;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

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

  /// False when the tunnel is up but repeated egress probes fail (TUN captures
  /// traffic while the inner WireGuard/carrier is dead — "connected, no internet").
  final tunnelHealthy = true.obs;

  StreamSubscription<VpnStage>? _stageSub;
  StreamSubscription<VpnStats>? _statsSub;
  Worker? _healthWorker;
  Timer? _healthTimer;
  int _egressFailures = 0;
  bool _wasConnected = false;
  bool _userDisconnecting = false;
  bool _syncingNative = false;
  bool _connectInProgress = false;
  bool _cancelRequested = false;

  static const _kWgPrivate = 'erebrus_wg_private';
  static const _kWgPublic = 'erebrus_wg_public';

  bool get isConnected => stage.value == VpnStage.connected;
  bool get isBusy => stage.value == VpnStage.connecting || stage.value == VpnStage.disconnecting;

  /// Allows late injection of the gateway provisioner (e.g. after login).
  set provisioner(Provisioner p) => _provision = p;

  @override
  void onInit() {
    super.onInit();
    // Health monitoring follows the UI stage regardless of which path set it
    // (engine event, connect() success, or syncWithNative()).
    _healthWorker = ever<VpnStage>(stage, (s) {
      if (s == VpnStage.connected) {
        _startHealthMonitor();
      } else {
        _stopHealthMonitor();
      }
    });
    _stageSub = _engine.onStage.listen((s) {
      if (killSwitchBlocking.value && s == VpnStage.connected) {
        stage.value = VpnStage.error;
        return;
      }
      // During connect(), hold the UI on "connecting" until egress is verified.
      if (_connectInProgress && s == VpnStage.connected) return;
      // A TUN that comes up late — after connect() already failed and showed an
      // error — is a zombie from an abandoned attempt: tear it down instead of
      // flipping the UI to "connected" on a tunnel nobody verified.
      if (s == VpnStage.connected &&
          !_wasConnected &&
          !_syncingNative &&
          stage.value == VpnStage.error) {
        debugPrint('[VPN] late connected event after failed connect — stopping zombie tunnel');
        unawaited(_engine.stop().catchError((_) {}));
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
        if (!_connectInProgress) {
          _restorePreferredMode();
        }
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
    _healthWorker?.dispose();
    _healthTimer?.cancel();
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
  Future<void> connect({VpnNode? node, CredentialBundle? providedBundle, String? clientPrivateKey}) async {
    if (_connectInProgress) {
      debugPrint('[VPN] connect already in progress — ignoring duplicate request');
      return;
    }
    final target = node ?? selectedNode.value;
    if (target == null) {
      error.value = 'Select a node first';
      return;
    }
    if (!target.canAcceptClients) {
      error.value = 'Selected server is at capacity — pick another node';
      stage.value = VpnStage.error;
      return;
    }
    if (providedBundle == null && _provision == null) {
      error.value = 'VPN provisioning is not configured';
      return;
    }
    _userDisconnecting = false;
    _connectInProgress = true;
    _cancelRequested = false;
    _wasConnected = false;
    if (killSwitchBlocking.value) {
      await _engine.stop().catchError((_) {});
      killSwitchBlocking.value = false;
      await VpnSessionStore.clear();
    }
    selectedNode.value = target;
    error.value = null;

    try {
      for (var attempt = 0; attempt <= 1; attempt++) {
        try {
          stage.value = VpnStage.connecting;
          if (!await _engine.prepare()) {
            error.value = _engine.desktopPrepareError ??
                (PlatformCapabilities.isDesktop
                    ? 'sing-box missing — run ./scripts/fetch-singbox-cli.sh macos from the repo root'
                    : 'VPN permission denied');
            stage.value = VpnStage.error;
            return;
          }
          final String privateToUse;
          ({String private, String public})? wgKeys;
          CredentialBundle bundle;
          if (providedBundle != null) {
            bundle = providedBundle;
            if (clientPrivateKey != null && clientPrivateKey.isNotEmpty) {
              privateToUse = clientPrivateKey;
            } else {
              wgKeys = await _ensureWgKeys();
              privateToUse = wgKeys.private;
            }
          } else {
            wgKeys = await _ensureWgKeys();
            privateToUse = wgKeys.private;
            bundle = await _provision!(node: target, wgPublicKey: wgKeys.public, name: _clientName());
          }
          if (_cancelRequested) {
            await _finishCancelled();
            return;
          }

          // Stealth needs a full sing-box profile; stale WG-only caches break REALITY.
          if (providedBundle == null &&
              mode.value != ConnectMode.wireguard &&
              !bundle.hasStealth &&
              Get.isRegistered<GatewayController>()) {
            final gw = Get.find<GatewayController>();
            debugPrint('[VPN] bundle missing stealth — refreshing from gateway');
            try {
              final fresh = await gw.client.fetchExistingClientBundle(
                nodeId: target.id,
                wgPublicKey: wgKeys!.public,
              );
              if (fresh != null && fresh.hasStealth) bundle = fresh;
            } catch (e) {
              debugPrint('[VPN] stealth bundle refresh failed: $e');
            }
          }

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

          final resolvedHosts = PlatformCapabilities.isDesktop
              ? const <String, String>{}
              : await SingboxConfigBuilder.resolveDialHosts(bundle);

          for (var i = 0; i < candidates.length; i++) {
            if (_cancelRequested) break;
            final t = candidates[i];
            try {
              if (i > 0) await _ensureTunnelStopped();
              if (_cancelRequested) break;
              stage.value = VpnStage.connecting;
              final config = SingboxConfigBuilder.build(
                bundle: bundle,
                transport: t,
                clientPrivateKey: privateToUse,
                // Desktop CLI: local mixed proxy + system HTTP/SOCKS (no TUN). TUN on
                // unsigned macOS breaks DNS for Safari/Chrome even when the in-app
                // egress probe (explicit 127.0.0.1:10808) works.
                useSystemTunnel: !PlatformCapabilities.isDesktop,
                resolvedHosts: resolvedHosts,
              );
              activeTransport.value = t;
              final srv = bundle.serverPublicKey;
              final srvShort = srv.length > 8 ? '${srv.substring(0, 8)}…' : srv;
              debugPrint(
                '[VPN] trying ${t.label} → ${bundle.dialTarget(t)} '
                '(wg ${bundle.address}, srv $srvShort)',
              );
              var ok = await _armAndStart(
                _engine.start(
                  jsonEncode(config),
                  profileName: 'Erebrus · ${target.name}',
                  splitTunnel: _splitTunnelConfig(),
                ),
              );
              if (!ok) {
                // Native tunnel may be up while EventChannel/method-channel was blocked (e.g. main-thread ANR).
                final native = await _engine.stage().catchError((_) => VpnStage.disconnected);
                if (native == VpnStage.connected) {
                  ok = true;
                  debugPrint('[VPN] ${t.label} native connected (stage event missed)');
                }
              }
              debugPrint('[VPN] ${t.label} finished stage=${stage.value.name} ok=$ok');
              if (ok) {
                final ready = t == Transport.wireguard
                    ? await _waitWireGuardReady()
                    : await _waitStealthReady();
                if (_cancelRequested) break;
                if (!ready) {
                  debugPrint('[VPN] ${t.label} tunnel up but no egress — trying next transport');
                  await _ensureTunnelStopped();
                  continue;
                }
              }
              if (ok) {
                _wasConnected = true;
                stage.value = VpnStage.connected;
                error.value = null;
                unawaited(_syncAppProxy(enabled: true));
                unawaited(_probeEgressIp());
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
            if (_cancelRequested) break;
            await _ensureTunnelStopped();
          }
          _wasConnected = false;
          if (_cancelRequested) {
            await _finishCancelled();
            return;
          }
          await _engine.stop().catchError((_) {});
          error.value = await _connectFailureMessage();
          stage.value = VpnStage.error;
        } on GatewayException catch (e) {
          _wasConnected = false;
          if (_cancelRequested) {
            await _finishCancelled();
            return;
          }
          if (attempt == 0 && _looksLikeMissingServerConfig(e)) {
            debugPrint('[VPN] server config missing for current WG key — rotating and retrying once');
            await _rotateWgKeys();
            continue;
          }
          error.value = friendlyGatewayError(e, nodeName: target.name);
          stage.value = VpnStage.error;
          break;
        } catch (e) {
          _wasConnected = false;
          if (_cancelRequested) {
            await _finishCancelled();
            return;
          }
          error.value = friendlyGatewayError(e, nodeName: target.name);
          stage.value = VpnStage.error;
          break;
        }
      }
    } finally {
      _connectInProgress = false;
    }
  }

  /// User-initiated abort of an in-flight [connect] — stops the engine and
  /// returns the UI to disconnected without surfacing an error.
  Future<void> cancelConnect() async {
    if (!_connectInProgress) return;
    debugPrint('[VPN] connect cancelled by user');
    _cancelRequested = true;
    await _engine.stop().catchError((_) {});
  }

  /// Cleanup shared by every cancelled-connect exit path.
  Future<void> _finishCancelled() async {
    await _engine.stop().catchError((_) {});
    await _ensureTunnelStopped();
    activeTransport.value = null;
    error.value = null;
    stage.value = VpnStage.disconnected;
    _restorePreferredMode();
    debugPrint('[VPN] connect aborted — back to disconnected');
  }

  Future<void> disconnect() async {
    _userDisconnecting = true;
    // Also aborts any connect() still running its transport loop.
    _cancelRequested = true;
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
    _restorePreferredMode();
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
    _restorePreferredMode();
    await VpnSessionStore.clear();
  }

  void _restorePreferredMode() {
    if (!Get.isRegistered<AppSettingsController>()) return;
    mode.value = Get.find<AppSettingsController>().defaultProtocol.value;
  }

  Future<void> _syncAppProxy({required bool enabled}) async {
    final ok = enabled
        ? await _engine.setAppProxy(
            host: SingboxConfigBuilder.localProxyHost,
            port: SingboxConfigBuilder.localProxyPort,
          )
        : await _engine.clearAppProxy();
    if (!ok && !PlatformCapabilities.isDesktop) {
      _showWebViewProxyWarning();
    }
  }

  void _showWebViewProxyWarning() {
    if (Get.isDialogOpen ?? false) return;
    Get.defaultDialog(
      title: 'WebView proxy not supported',
      middleText:
          'Your system WebView does not support proxy override. The in-app browser may not route through the VPN tunnel. Use an external browser to ensure traffic goes through the tunnel.',
      textConfirm: 'OK',
      barrierDismissible: false,
      onConfirm: Get.back,
    );
  }

  Future<void> _probeEgressIp() async {
    if (!isConnected || killSwitchBlocking.value) return;
    egressIpLoading.value = true;
    try {
      final ip = await EgressIpProbe.fetch(useTunnelProxy: true);
      if (isConnected) _recordEgressResult(ip);
      debugPrint('[VPN] egress IP probe → ${ip ?? "failed"}');
    } finally {
      egressIpLoading.value = false;
    }
  }

  // ── Tunnel health monitor ─────────────────────────────────────────────
  // Native reports "connected" when the OS TUN opens, not when the inner
  // WireGuard handshake completes (see ErebrusVpnService.openTun). connect()
  // verifies egress before celebrating, but syncWithNative() and long-lived
  // sessions have no such gate — so re-probe periodically and flag the
  // "TUN up, nothing flows" state instead of showing PROTECTED forever.

  void _startHealthMonitor() {
    _egressFailures = 0;
    tunnelHealthy.value = true;
    _scheduleHealthCheck(const Duration(seconds: 45));
  }

  void _stopHealthMonitor() {
    _healthTimer?.cancel();
    _healthTimer = null;
    _egressFailures = 0;
    tunnelHealthy.value = true;
  }

  void _scheduleHealthCheck(Duration delay) {
    _healthTimer?.cancel();
    _healthTimer = Timer(delay, () async {
      if (!isConnected || killSwitchBlocking.value) return;
      final ip = await EgressIpProbe.fetch(
        timeout: const Duration(seconds: 6),
        useTunnelProxy: true,
      );
      if (!isConnected) return;
      _recordEgressResult(ip);
      // Re-check quickly while degraded so recovery/confirmation is prompt.
      _scheduleHealthCheck(Duration(seconds: _egressFailures > 0 ? 10 : 45));
    });
  }

  void _recordEgressResult(String? ip) {
    if (ip != null) {
      if (!tunnelHealthy.value) debugPrint('[VPN] tunnel egress recovered');
      _egressFailures = 0;
      tunnelHealthy.value = true;
      egressIp.value = ip;
      return;
    }
    _egressFailures += 1;
    if (_egressFailures == 1) _scheduleHealthCheck(const Duration(seconds: 10));
    if (_egressFailures >= 2 && tunnelHealthy.value) {
      tunnelHealthy.value = false;
      debugPrint('[VPN] tunnel up but egress failing — flagging unhealthy');
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

  /// Waits until the local sing-box mixed inbound accepts TCP (egress probe target).
  Future<bool> _waitLocalMixedProxy({
    int attempts = 40,
    Duration interval = const Duration(milliseconds: 250),
  }) async {
    final host = SingboxConfigBuilder.localProxyHost;
    final port = SingboxConfigBuilder.localProxyPort;
    for (var i = 0; i < attempts; i++) {
      if (_cancelRequested) return false;
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 200),
        );
        await socket.close();
        debugPrint('[VPN] mixed proxy ready at $host:$port');
        return true;
      } catch (_) {
        if (i + 1 < attempts) await Future<void>.delayed(interval);
      }
    }
    debugPrint('[VPN] mixed proxy not ready at $host:$port');
    return false;
  }

  Future<bool> _waitTunnelEgress({
    required String label,
    int attempts = 8,
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    for (var i = 0; i < attempts; i++) {
      if (_cancelRequested) return false;
      final ip = await EgressIpProbe.fetch(
        timeout: const Duration(seconds: 4),
        useTunnelProxy: true,
      );
      if (ip != null) {
        debugPrint('[VPN] $label egress ready → $ip');
        return true;
      }
      if (i + 1 < attempts) await Future<void>.delayed(interval);
    }
    return false;
  }

  /// Direct WireGuard: TUN may be up before UDP handshake completes — verify egress.
  Future<bool> _waitWireGuardReady() async {
    if (Platform.isAndroid && !await _waitLocalMixedProxy(attempts: 24)) return false;
    return _waitTunnelEgress(label: 'WireGuard', attempts: 6);
  }

  /// Stealth: wait for mixed-in, then carrier + inner WG, before showing connected.
  /// Probes run in parallel with a hard 4s cap each, so the worst case here is
  /// ~36s before falling through to the next transport (was minutes when the
  /// probe timeout leaked — see EgressIpProbe._get).
  Future<bool> _waitStealthReady() async {
    if (!await _waitLocalMixedProxy()) return false;
    // Carrier (VLESS/Hy2) and loopback WG peer need a beat after mixed-in is up.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return _waitTunnelEgress(label: 'Stealth', attempts: 8);
  }

  /// Fully tears down the native tunnel before the next transport attempt.
  Future<void> _ensureTunnelStopped() async {
    final now = await _engine.stage().catchError((_) => VpnStage.disconnected);
    if (now == VpnStage.disconnected) return;
    await _engine.stop().catchError((_) {});
    for (var i = 0; i < 50; i++) {
      final s = await _engine.stage().catchError((_) => VpnStage.disconnected);
      if (s == VpnStage.disconnected) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    debugPrint('[VPN] stop: timed out waiting for disconnected before transport retry');
  }

  /// Subscribes before [startFuture] completes so fast native errors are not missed.
  /// Also polls native [stage] because Android starts the tunnel asynchronously
  /// after the method channel returns and the EventChannel "connected" event can
  /// be missed, leaving the UI stuck on "connecting" while the OS VPN is up.
  Future<String> _connectFailureMessage() async {
    final native = await _engine.lastTunnelError();
    if (native != null && native.isNotEmpty) {
      if (native.contains('ParsePrefix') || native.contains('ipcidr')) {
        return 'VPN config error — update the Erebrus app to the latest build';
      }
      final short = native.length > 160 ? '${native.substring(0, 160)}…' : native;
      return 'Could not connect — $short';
    }
    final desktop = _engine.desktopPrepareError ?? SingboxDesktopRunner.instance.lastError;
    if (desktop != null && desktop.isNotEmpty) {
      return 'Could not connect — $desktop';
    }
    if (PlatformCapabilities.isDesktop) {
      return 'Could not connect — run ./scripts/setup-macos-dev.sh, then try Stealth or another server';
    }
    return 'Could not connect — try WireGuard or Stealth mode, or pick another server';
  }

  Future<bool> _armAndStart(
    Future<void> startFuture, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final completer = Completer<bool>();
    late StreamSubscription<VpnStage> sub;
    sub = _engine.onStage.listen((s) {
      if (s == VpnStage.connected && !completer.isCompleted) completer.complete(true);
      if (s == VpnStage.error && !completer.isCompleted) completer.complete(false);
    });
    try {
      await startFuture;
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (_cancelRequested) return false;
        if (completer.isCompleted) return await completer.future;
        final now = await _engine.stage();
        if (now == VpnStage.connected) return true;
        if (now == VpnStage.error) return false;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      final finalStage = await _engine.stage().catchError((_) => VpnStage.disconnected);
      if (finalStage == VpnStage.connected) return true;
      debugPrint('[VPN] _armAndStart timed out after ${timeout.inSeconds}s (native=${finalStage.name})');
      return false;
    } finally {
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

  Future<String?> _readStoredSecret(String key) => ErebrusSecureStorage.read(key);

  Future<void> _writeStoredSecret(String key, String value) => ErebrusSecureStorage.write(key, value);

  Future<void> _deleteStoredSecret(String key) async {
    try {
      await ErebrusSecureStorage.delete(key);
    } catch (_) {}
  }

  /// If the gateway no longer recognizes the current WG public key, retry once
  /// with a freshly generated key pair.
  bool _looksLikeMissingServerConfig(GatewayException e) {
    final lower = e.message.toLowerCase();
    if (lower.contains('node not found')) return false;
    final missingHints = [
      'not found',
      'notfound',
      'no such client',
      'client not found',
      'config not found',
      'invalid public key',
      'public key not found',
      'missing client',
      'unknown client',
    ];
    return missingHints.any(lower.contains);
  }

  Future<void> _rotateWgKeys() async {
    await _deleteStoredSecret(_kWgPrivate);
    await _deleteStoredSecret(_kWgPublic);
    final keys = await _engine.generateWireGuardKeyPair();
    await _writeStoredSecret(_kWgPrivate, keys.private);
    await _writeStoredSecret(_kWgPublic, keys.public);
  }

  String _clientName() {
    final platform = defaultTargetPlatform.name;
    return 'erebrus-$platform-${DateTime.now().millisecondsSinceEpoch % 100000}';
  }
}
