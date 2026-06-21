import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';

import 'gateway_client.dart';
import 'gateway_errors.dart';
import 'singbox_engine.dart';
import 'vpn_models.dart';

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
  final _storage = const FlutterSecureStorage();
  Provisioner? _provision;

  // observables
  final stage = VpnStage.disconnected.obs;
  final mode = ConnectMode.auto.obs;
  final activeTransport = Rxn<Transport>();
  final selectedNode = Rxn<VpnNode>();
  final stats = const VpnStats().obs;
  final error = RxnString();

  StreamSubscription<VpnStage>? _stageSub;
  StreamSubscription<VpnStats>? _statsSub;

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
      stage.value = s;
      if (s == VpnStage.disconnected || s == VpnStage.error) activeTransport.value = null;
    });
    _statsSub = _engine.onStats.listen((s) => stats.value = s);
    _engine.stage().then((s) => stage.value = s).catchError((_) => VpnStage.disconnected);
  }

  @override
  void onClose() {
    _stageSub?.cancel();
    _statsSub?.cancel();
    super.onClose();
  }

  void setMode(ConnectMode m) => mode.value = m;
  void selectNode(VpnNode n) => selectedNode.value = n;

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
    selectedNode.value = target;
    error.value = null;
    stage.value = VpnStage.connecting;

    try {
      if (!await _engine.prepare()) {
        error.value = 'VPN permission denied';
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

      for (final t in candidates) {
        try {
          final config = SingboxConfigBuilder.build(
            bundle: bundle, transport: t, clientPrivateKey: keys.private);
          activeTransport.value = t;
          await _engine.start(jsonEncode(config), profileName: 'Erebrus · ${target.name}');
          if (await _awaitConnected()) return; // success
        } catch (e) {
          if (kDebugMode) debugPrint('transport ${t.label} failed: $e');
        }
        await _engine.stop().catchError((_) {});
      }
      error.value = 'Could not connect on this network — try Stealth mode or another server';
      stage.value = VpnStage.error;
    } on GatewayException catch (e) {
      error.value = friendlyGatewayError(e, nodeName: target.name);
      stage.value = VpnStage.error;
    } catch (e) {
      error.value = friendlyGatewayError(e, nodeName: target.name);
      stage.value = VpnStage.error;
    }
  }

  Future<void> disconnect() async {
    stage.value = VpnStage.disconnecting;
    try {
      await _engine.stop();
      stage.value = await _engine.stage();
    } catch (_) {
      stage.value = VpnStage.disconnected;
    }
    activeTransport.value = null;
    error.value = null;
  }

  Future<void> toggle() => isConnected ? disconnect() : connect();

  /// Waits up to [timeout] for the engine to report connected; false otherwise.
  Future<bool> _awaitConnected({Duration timeout = const Duration(seconds: 12)}) async {
    if (stage.value == VpnStage.connected) return true;
    final completer = Completer<bool>();
    late StreamSubscription<VpnStage> sub;
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    sub = _engine.onStage.listen((s) {
      if (s == VpnStage.connected && !completer.isCompleted) completer.complete(true);
      if (s == VpnStage.error && !completer.isCompleted) completer.complete(false);
    });
    final result = await completer.future;
    timer.cancel();
    await sub.cancel();
    return result;
  }

  Future<({String private, String public})> _ensureWgKeys() async {
    final priv = await _storage.read(key: _kWgPrivate);
    final pub = await _storage.read(key: _kWgPublic);
    if (priv != null && priv.isNotEmpty && pub != null && pub.isNotEmpty) {
      return (private: priv, public: pub);
    }
    final keys = await _engine.generateWireGuardKeyPair();
    await _storage.write(key: _kWgPrivate, value: keys.private);
    await _storage.write(key: _kWgPublic, value: keys.public);
    return keys;
  }

  String _clientName() {
    final platform = defaultTargetPlatform.name;
    return 'erebrus-$platform-${DateTime.now().millisecondsSinceEpoch % 100000}';
  }
}
