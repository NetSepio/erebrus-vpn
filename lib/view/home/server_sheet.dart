import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../theme/app_theme.dart';
import '../../vpn/gateway_controller.dart';
import '../../vpn/node_probe.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';
import 'node_display.dart';
import 'node_ui_widgets.dart';
import 'nodes_empty_panel.dart';
import 'sheet_chrome.dart';

/// Presents the node-picker bottom sheet (slide-up, rounded top, dim backdrop).
Future<void> showServerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => const SheetFrame(maxHeightFactor: 0.78, child: _ServerSheet()),
  );
}

class _ServerSheet extends StatefulWidget {
  const _ServerSheet();
  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  String _filter = 'all'; // all | public | private
  Map<String, int> _clientPingMs = const {};
  bool _probing = false;
  int _probeGeneration = 0;
  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAndProbe());
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted) return;
      _startClientProbes(Get.find<GatewayController>().nodes);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAndProbe({bool silent = false}) async {
    if (!mounted) return;
    final gateway = Get.find<GatewayController>();
    await gateway.refreshNodes(silent: silent);
    if (!mounted) return;
    await _startClientProbes(gateway.nodes);
  }

  Future<void> _startClientProbes(List<VpnNode> nodes) async {
    final generation = ++_probeGeneration;
    setState(() {
      _probing = true;
      _clientPingMs = const {};
    });
    final results = await NodeProbe.probeAll(nodes);
    if (!mounted || generation != _probeGeneration) return;
    setState(() {
      _clientPingMs = results;
      _probing = false;
    });
  }

  bool _matchesFilter(VpnNode node) {
    return switch (_filter) {
      'private' => node.isPrivateAccess,
      'public' => !node.isPrivateAccess,
      _ => true,
    };
  }

  Future<void> _refresh(GatewayController gateway) async {
    setState(() => _filter = 'all');
    await _refreshAndProbe();
  }

  @override
  Widget build(BuildContext context) {
    final gateway = Get.find<GatewayController>();
    final vpn = Get.find<VpnController>();

    return Obx(() {
      final allNodes = gateway.nodes;
      final nodes = sortNodesForPicker(
        allNodes.where(_matchesFilter),
        clientPingMs: _clientPingMs,
      );
      final subtitle = _probing
          ? (_clientPingMs.isEmpty
              ? 'MEASURING PING…'
              : '${nodes.length} NODES · UPDATING PING')
          : (_clientPingMs.isEmpty
              ? '${allNodes.length} NODES · SORTED BY LOAD'
              : (_filter == 'all'
                  ? '${allNodes.length} NODES · SORTED BY PING'
                  : '${nodes.length} OF ${allNodes.length} · SORTED BY PING'));
      final err = gateway.error.value;
      final warn = gateway.warning.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select node', style: grotesk(size: 18, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: mono(size: 11, weight: FontWeight.w400, color: AppColors.textMuted, letterSpacing: 11 * 0.04),
                    ),
                  ],
                ),
                const Spacer(),
                Obx(() {
                  final busy = gateway.loading.value;
                  return GestureDetector(
                    onTap: busy ? null : () => _refresh(gateway),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                            )
                          : const Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
                    ),
                  );
                }),
                SheetCloseButton(onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          if (warn != null && warn.isNotEmpty && allNodes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Text(warn, style: grotesk(size: 12, color: AppColors.warn)),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 10),
                  Text('Search nodes, cities…', style: grotesk(size: 13.5, weight: FontWeight.w400, color: AppColors.textMuted)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Row(
              children: [
                for (final f in const [('all', 'ALL'), ('public', 'PUBLIC'), ('private', 'PRIVATE')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(label: f.$2, active: _filter == f.$1, onTap: () => setState(() => _filter = f.$1)),
                  ),
              ],
            ),
          ),
          Flexible(
            child: nodes.isEmpty
                ? _buildEmptyState(gateway: gateway, allNodes: allNodes, err: err)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                    itemCount: nodes.length,
                    itemBuilder: (_, i) {
                      final node = nodes[i];
                      final selected = vpn.selectedNode.value?.id == node.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _NodeRow(
                          node: node,
                          selected: selected,
                          clientPingMs: _clientPingMs[node.id],
                          probing: _probing,
                          onTap: () => _select(vpn, node),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }

  Widget _buildEmptyState({
    required GatewayController gateway,
    required List<VpnNode> allNodes,
    required String? err,
  }) {
    if (allNodes.isEmpty) {
      if (gateway.loading.value) {
        return NodesEmptyPanel.registryEmpty(loading: true);
      }
      if (err != null && err.isNotEmpty) {
        return NodesEmptyPanel.registryError(
          message: err,
          gatewayUrl: gateway.gatewayUrl.value,
          onRetry: () => _refresh(gateway),
        );
      }
      return NodesEmptyPanel.registryEmpty(onRetry: () => _refresh(gateway));
    }
    return NodesEmptyPanel.filteredEmpty(
      filter: _filter,
      totalOnline: allNodes.length,
      onShowAll: () => setState(() => _filter = 'all'),
    );
  }

  void _select(VpnController vpn, VpnNode node) {
    Navigator.of(context).pop();
    if (vpn.isConnected) {
      vpn.connect(node: node);
    } else {
      vpn.selectNode(node);
    }
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.node,
    required this.selected,
    required this.onTap,
    this.clientPingMs,
    this.probing = false,
  });
  final VpnNode node;
  final bool selected;
  final int? clientPingMs;
  final bool probing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = NodeDisplay.of(node, clientPingMs: clientPingMs, showActivity: true);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withValues(alpha: 0.08) : AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.accent.withValues(alpha: 0.55) : AppColors.stroke),
        ),
        child: NodeCompactRow(
          display: d,
          metrics: NodeMetricsColumn(display: d, probing: probing),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.accent.withValues(alpha: 0.5) : AppColors.strokeHi),
        ),
        child: Text(
          label,
          style: mono(
            size: 11,
            weight: FontWeight.w500,
            color: active ? AppColors.accent : AppColors.textTertiary,
            letterSpacing: 11 * 0.04,
          ),
        ),
      ),
    );
  }
}