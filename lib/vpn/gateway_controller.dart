import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../auth/wallet_auth_controller.dart';
import 'gateway_client.dart';
import 'vpn_controller.dart';
import 'vpn_models.dart';

/// Loads the gateway node list and wires [VpnController.provisioner].
class GatewayController extends GetxController {
  GatewayController({GatewayClient? client, String? gatewayUrl})
      : _client = client ?? GatewayClient(baseUrl: gatewayUrl);

  final GatewayClient _client;

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

  void _wireProvisioner() {
    final vpn = Get.find<VpnController>();
    vpn.provisioner = ({
      required VpnNode node,
      required String wgPublicKey,
      required String name,
    }) =>
        _client.provisionClient(nodeId: node.id, wgPublicKey: wgPublicKey, name: name);
  }

  Future<void> refreshNodes() async {
    loading.value = true;
    error.value = null;
    warning.value = null;
    try {
      debugPrint('[Gateway] fetching nodes from ${gatewayUrl.value}');
      var list = await _client.fetchNodes();
      if (list.isEmpty) {
        debugPrint('[Gateway] registry empty — using dev fallback erebrus-nexus');
        list = GatewayClient.devFallbackNodes();
        warning.value =
            'Gateway returned 0 nodes. Showing erebrus-nexus from cache — '
            'the node may need to re-register with the gateway.';
      }
      nodes.assignAll(list);
      nodes.refresh();
      debugPrint('[Gateway] loaded ${list.length} node(s): ${list.map((n) => n.name).join(", ")}');
      final vpn = Get.find<VpnController>();
      if (vpn.selectedNode.value == null && list.isNotEmpty) {
        vpn.selectNode(list.first);
      }
    } on GatewayException catch (e) {
      debugPrint('[Gateway] error: ${e.message}');
      error.value = e.message;
      nodes.clear();
    } catch (e) {
      debugPrint('[Gateway] error: $e');
      error.value = e.toString();
      nodes.clear();
    } finally {
      loading.value = false;
    }
  }
}