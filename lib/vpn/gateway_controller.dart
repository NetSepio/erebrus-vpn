import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/wallet_auth_controller.dart';
import 'credential_cache.dart';
import 'gateway_client.dart';
import 'vpn_controller.dart';
import 'vpn_models.dart';
import 'vpn_session_store.dart';

/// Loads the gateway node list and wires [VpnController.provisioner].
///
/// Nodes are scoped: the default "Public network" scope shows the public
/// discovery list (`GET /api/v2/nodes`); selecting an organization the user
/// belongs to shows that org's nodes (incl. private) sourced from
/// `GET /api/v2/operator/nodes`. The active scope is persisted across launches.
class GatewayController extends GetxController {
  GatewayController({GatewayClient? client, String? gatewayUrl})
      : _client = client ?? GatewayClient(baseUrl: gatewayUrl);

  final GatewayClient _client;
  GatewayClient get client => _client;
  final _bundleCache = CredentialCache();

  /// The active, scope-filtered node list the UI binds to.
  final nodes = <VpnNode>[].obs;

  /// Organizations the signed-in user belongs to (empty when logged out).
  final orgs = <VpnOrg>[].obs;

  /// Active node scope: `null` = Public network, otherwise an org slug.
  final selectedScope = RxnString();

  final loading = false.obs;
  final error = RxnString();
  final warning = RxnString();
  late final RxString gatewayUrl;

  // Raw fetched buffers; [_applyActiveNodes] filters + sorts for display.
  List<VpnNode> _publicNodes = const [];
  Map<String, List<VpnNode>> _orgNodesBySlug = {};

  // Last persisted scope choice (org slug) or null; restored once its org loads.
  static const _kScopeKey = 'gateway.node_scope';
  String? _persistedScope;
  bool _scopeLoaded = false;

  Timer? _refreshTimer;
  static const _registryPollInterval = Duration(seconds: 30);

  @override
  void onInit() {
    super.onInit();
    gatewayUrl = _client.baseUrl.obs;
    if (Get.isRegistered<WalletAuthController>()) {
      _client.setBearerToken(Get.find<WalletAuthController>().bearerToken);
    }
    _wireProvisioner();
    _refreshTimer = Timer.periodic(_registryPollInterval, (_) {
      if (!loading.value) refreshNodes(silent: true);
    });
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    super.onClose();
  }

  void setBearerToken(String? token) => _client.setBearerToken(token);

  Future<void> clearLocalCaches() => _bundleCache.clearAll();

  /// The org backing the active scope, or null when on the Public network.
  VpnOrg? get activeOrg {
    final slug = selectedScope.value;
    if (slug == null) return null;
    for (final o in orgs) {
      if (o.slug == slug) return o;
    }
    return null;
  }

  /// Human label for the active scope ("Public network" or the org name).
  String get scopeLabel => activeOrg?.name ?? 'Public network';

  /// Online node count for a scope (`null` = public), used by the picker chips.
  int nodeCountForScope(String? slug) {
    final source = slug == null ? _publicNodes : (_orgNodesBySlug[slug] ?? const []);
    return source.where((n) => !n.isDraining && !n.isOffline).length;
  }

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
      } on GatewayException {
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
  /// Always refreshes the public pool; when authenticated, also refreshes the
  /// caller's orgs and org-scoped nodes (best-effort).
  Future<void> refreshNodes({bool silent = false}) async {
    if (!silent) loading.value = true;
    error.value = null;
    if (!silent) warning.value = null;
    await _ensureScopeLoaded();
    final previousActive = List<VpnNode>.from(nodes);
    try {
      debugPrint('[Gateway] fetching nodes from ${gatewayUrl.value}');
      _publicNodes = await _client.fetchNodes();

      // Org scope is best-effort: skipped when logged out, ignored on auth error.
      await _refreshOrgScope();
      _reconcileScope();

      _applyActiveNodes();

      if (nodes.isEmpty && selectedScope.value == null) {
        debugPrint('[Gateway] registry empty — 0 online nodes from API');
        warning.value = 'No servers available — try refresh again in a moment';
      }

      debugPrint(
        '[Gateway] loaded ${nodes.length} node(s) in scope "$scopeLabel"'
        '${orgs.isNotEmpty ? " · ${orgs.length} org(s)" : ""}',
      );
    } on GatewayException catch (e) {
      debugPrint('[Gateway] error: ${e.message}');
      error.value = '${e.message} · ${gatewayUrl.value}';
      _restorePreviousOrClear(previousActive);
    } catch (e) {
      debugPrint('[Gateway] error: $e');
      error.value = e.toString();
      _restorePreviousOrClear(previousActive);
    } finally {
      if (!silent) loading.value = false;
    }
  }

  /// Refreshes [orgs] and the per-org node buffer. Logged-out users (no bearer)
  /// get empty results; transient auth/network errors keep the prior buffers.
  Future<void> _refreshOrgScope() async {
    try {
      final fetchedOrgs = await _client.fetchOrgs();
      final fetchedNodes = await _client.fetchOrgNodes();

      final bySlug = <String, List<VpnNode>>{};
      for (final n in fetchedNodes) {
        final slug = n.org?.slug;
        if (slug == null || slug.isEmpty) continue;
        (bySlug[slug] ??= <VpnNode>[]).add(n);
      }
      _orgNodesBySlug = bySlug;

      // Start from the authoritative /orgs list, then add any org that has nodes
      // but wasn't returned by /orgs (synthesized from the node's org block), so
      // a member always gets a chip for an org whose nodes they can reach.
      final merged = <VpnOrg>[...fetchedOrgs];
      final known = merged.map((o) => o.slug).toSet();
      for (final entry in bySlug.entries) {
        if (known.contains(entry.key)) continue;
        final orgBlock = entry.value.first.org;
        merged.add(VpnOrg(
          name: orgBlock?.name ?? entry.key,
          slug: entry.key,
          verificationStatus: orgBlock?.verified == true
              ? 'verified'
              : orgBlock?.verificationStatus,
        ));
        known.add(entry.key);
      }
      orgs.assignAll(merged);
    } catch (e) {
      debugPrint('[Gateway] org scope unavailable: $e');
    }
  }

  /// Restores a persisted scope once its org is available, and degrades to the
  /// Public network when the active scope's org is no longer present.
  void _reconcileScope() {
    final available = <String>{
      ..._orgNodesBySlug.keys,
      ...orgs.map((o) => o.slug),
    };
    if (selectedScope.value == null &&
        _persistedScope != null &&
        available.contains(_persistedScope)) {
      selectedScope.value = _persistedScope;
    }
    if (selectedScope.value != null && !available.contains(selectedScope.value)) {
      selectedScope.value = null;
    }
  }

  List<VpnNode> _scopeSource() {
    final slug = selectedScope.value;
    if (slug == null) return _publicNodes;
    return _orgNodesBySlug[slug] ?? const [];
  }

  /// Recomputes [nodes] from the active scope, then reconciles VPN selection.
  void _applyActiveNodes() {
    final list = sortNodesForPicker(
      _scopeSource().where((n) => !n.isDraining && !n.isOffline),
    );
    nodes.assignAll(list);
    nodes.refresh();
    _reconcileSelection(list);
    if (Get.isRegistered<VpnController>()) {
      Get.find<VpnController>().reconcileNodeFromGateway();
    }
  }

  void _restorePreviousOrClear(List<VpnNode> previousActive) {
    if (previousActive.isNotEmpty) {
      warning.value = 'Showing last known servers — refresh failed';
      nodes.assignAll(previousActive);
      nodes.refresh();
    } else {
      nodes.clear();
      _reconcileSelection(const []);
    }
  }

  /// Switches the active node scope. `null` selects the Public network; a slug
  /// selects that org's nodes. Persisted across launches.
  Future<void> setScope(String? slug) async {
    final normalized = (slug == null || slug.isEmpty) ? null : slug;
    selectedScope.value = normalized;
    _persistedScope = normalized;
    _scopeLoaded = true;
    warning.value = null;
    final prefs = await SharedPreferences.getInstance();
    if (normalized == null) {
      await prefs.remove(_kScopeKey);
    } else {
      await prefs.setString(_kScopeKey, normalized);
    }
    _applyActiveNodes();
  }

  Future<void> _ensureScopeLoaded() async {
    if (_scopeLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _persistedScope = prefs.getString(_kScopeKey);
    _scopeLoaded = true;
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

  /// Clears VPN-side persisted state (bundles, session snapshot, WG keys) and
  /// resets scope back to the Public network (e.g. on logout).
  Future<void> resetVpnLocalState() async {
    await setScope(null);
    orgs.clear();
    _orgNodesBySlug = {};
    await clearLocalCaches();
    await VpnSessionStore.clear();
    if (Get.isRegistered<VpnController>()) {
      await Get.find<VpnController>().resetLocalVpnData();
    }
    await refreshNodes();
  }
}
