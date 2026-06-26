import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../auth/wallet_auth_controller.dart';
import 'credential_cache.dart';
import 'gateway_client.dart';
import 'vpn_controller.dart';
import 'vpn_models.dart';
import 'vpn_session_store.dart';

/// Loads the gateway node list and wires [VpnController.provisioner].
class GatewayController extends GetxController {
  GatewayController({GatewayClient? client, String? gatewayUrl})
      : _client = client ?? GatewayClient(baseUrl: gatewayUrl);

  final GatewayClient _client;
  GatewayClient get client => _client;
  final _bundleCache = CredentialCache();

  final nodes = <VpnNode>[].obs;
  final loading = false.obs;
  final error = RxnString();
  final warning = RxnString();
  late final RxString gatewayUrl;

  @override
  void onInit() {
    super.onInit();
    gatewayUrl = _client.baseUrl.obs;
    if (Get.isRegistered<WalletAuthController>()) {
      _client.setBearerToken(Get.find<WalletAuthController>().bearerToken);
    }
    _wireProvisioner();
    refreshNodes();
  }

  void setBearerToken(String? token) => _client.setBearerToken(token);

  Future<void> clearLocalCaches() => _bundleCache.clearAll();

  void _wireProvisioner() {
    final vpn = Get.find<VpnController>();
    vpn.provisioner = ({
      required VpnNode node,
      required String wgPublicKey,
      required String name,
    }) async {
      try {
        final bundle = await _client.provisionClient(
          nodeId: node.id,
          wgPublicKey: wgPublicKey,
          name: name,
        );
        await _bundleCache.write(
          nodeId: node.id,
          wgPublicKey: wgPublicKey,
          bundle: bundle,
        );
        return bundle;
      } on GatewayException catch (e) {
        final cached = await _bundleCache.read(
          nodeId: node.id,
          wgPublicKey: wgPublicKey,
        );
        if (cached != null && cached.hasWireGuard && cached.hasStealth) {
          debugPrint('[Gateway] using cached credential bundle for ${node.name}');
          return cached;
        }
        final reused = await _client.fetchExistingClientBundle(
          nodeId: node.id,
          wgPublicKey: wgPublicKey,
        );
        if (reused != null) {
          debugPrint('[Gateway] reusing existing VPN client for ${node.name}');
          await _bundleCache.write(
            nodeId: node.id,
            wgPublicKey: wgPublicKey,
            bundle: reused,
          );
          return reused;
        }
        rethrow;
      }
    };
  }

  /// Fetches the live node registry from the gateway (not cached locally).
  Future<void> refreshNodes() async {
    loading.value = true;
    error.value = null;
    warning.value = null;
    final previous = List<VpnNode>.from(nodes);
    try {
      debugPrint('[Gateway] fetching nodes from ${gatewayUrl.value}');
      var list = await _client.fetchNodes();
      list = sortNodesForPicker(list.where((n) => !n.isDraining && !n.isOffline));

      if (list.isEmpty) {
        if (kDebugMode) {
          debugPrint('[Gateway] registry empty — dev fallback erebrus-nexus');
          list = GatewayClient.devFallbackNodes();
          warning.value = 'Dev: gateway returned 0 online nodes — showing erebrus-nexus';
        } else {
          warning.value = 'No servers available — try refresh again in a moment';
        }
      }

      nodes.assignAll(list);
      nodes.refresh();
      debugPrint('[Gateway] loaded ${list.length} node(s): ${list.map((n) => n.name).join(", ")}');
      _reconcileSelection(list);
      Get.find<VpnController>().reconcileNodeFromGateway();
    } on GatewayException catch (e) {
      debugPrint('[Gateway] error: ${e.message}');
      error.value = '${e.message} · ${gatewayUrl.value}';
      if (previous.isNotEmpty) {
        warning.value = 'Showing last known servers — refresh failed';
        nodes.assignAll(previous);
        nodes.refresh();
      } else {
        nodes.clear();
        _reconcileSelection(const []);
      }
    } catch (e) {
      debugPrint('[Gateway] error: $e');
      error.value = e.toString();
      if (previous.isNotEmpty) {
        warning.value = 'Showing last known servers — refresh failed';
        nodes.assignAll(previous);
        nodes.refresh();
      } else {
        nodes.clear();
        _reconcileSelection(const []);
      }
    } finally {
      loading.value = false;
    }
  }

  void _reconcileSelection(List<VpnNode> list) {
    final vpn = Get.find<VpnController>();
    final current = vpn.selectedNode.value;

    if (current != null) {
      VpnNode? match;
      for (final n in list) {
        if (n.id == current.id) {
          match = n;
          break;
        }
      }
      if (match != null) {
        vpn.selectNode(match);
        return;
      }
      if (!vpn.isConnected && !vpn.killSwitchBlocking.value) {
        vpn.clearSelectedNode();
        if (list.isNotEmpty) {
          vpn.selectNode(list.first);
          warning.value ??= 'Previous server is no longer available — picked ${list.first.name}';
        } else {
          warning.value ??= 'Previous server is no longer available';
        }
        return;
      }
    }

    if (current == null && list.isNotEmpty && !vpn.isConnected) {
      vpn.selectNode(list.first);
    }
  }

  /// Clears VPN-side persisted state (bundles, session snapshot, WG keys).
  Future<void> resetVpnLocalState() async {
    await clearLocalCaches();
    await VpnSessionStore.clear();
    if (Get.isRegistered<VpnController>()) {
      await Get.find<VpnController>().resetLocalVpnData();
    }
    await refreshNodes();
  }
}