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
    builder: (_) => const SheetFrame(maxHeightFactor: 0.82, child: _ServerSheet()),
  );
}

class _ServerSheet extends StatefulWidget {
  const _ServerSheet();
  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  int _tab = 0; // 0 = Public, 1 = Private

  // Public filters.
  String? _pubRegion; // null = all

  // Private filters.
  String? _privType; // null | erebrus | shield | sentinel
  String? _privWorkspace; // null = all; else org slug
  String? _privRegion;

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

  Future<void> _refresh() => _refreshAndProbe();

  // ── filtering ────────────────────────────────────────

  List<VpnNode> _publicList(GatewayController gateway) {
    final list = gateway.publicNodes.where(
      (n) => _pubRegion == null || n.region.toUpperCase() == _pubRegion,
    );
    return sortNodesForPicker(list, clientPingMs: _clientPingMs);
  }

  List<VpnNode> _privateList(GatewayController gateway) {
    final list = gateway.orgNodes.where((n) {
      if (_privType != null && n.deploymentProfile.toLowerCase() != _privType) return false;
      if (_privWorkspace != null && n.org?.slug != _privWorkspace) return false;
      if (_privRegion != null && n.region.toUpperCase() != _privRegion) return false;
      return true;
    });
    return sortNodesForPicker(list, clientPingMs: _clientPingMs);
  }

  List<String> _regionsOf(Iterable<VpnNode> nodes) {
    final set = <String>{};
    for (final n in nodes) {
      final r = n.region.trim().toUpperCase();
      if (r.isNotEmpty) set.add(r);
    }
    final out = set.toList()..sort();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final gateway = Get.find<GatewayController>();
    final vpn = Get.find<VpnController>();

    return Obx(() {
      final isPublic = _tab == 0;
      final nodes = isPublic ? _publicList(gateway) : _privateList(gateway);
      final total = isPublic ? gateway.publicNodes.length : gateway.orgNodes.length;
      final subtitle = _probing
          ? 'MEASURING PING…'
          : '${nodes.length}${nodes.length != total ? ' OF $total' : ''} NODES · '
              '${_clientPingMs.isEmpty ? 'SORTED BY LOAD' : 'SORTED BY PING'}';
      final err = gateway.error.value;
      final warn = gateway.warning.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(subtitle: subtitle, onClose: () => Navigator.of(context).pop(), onRefresh: _refresh),
          if (warn != null && warn.isNotEmpty && total > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Text(warn, style: grotesk(size: 12, color: AppColors.warn)),
            ),

          // Public / Private tabs.
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Row(
              children: [
                Expanded(
                  child: _TabButton(
                    label: 'PUBLIC',
                    icon: Icons.public,
                    active: isPublic,
                    onTap: () => setState(() => _tab = 0),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TabButton(
                    label: 'PRIVATE',
                    icon: Icons.apartment_rounded,
                    active: !isPublic,
                    onTap: () => setState(() => _tab = 1),
                  ),
                ),
              ],
            ),
          ),

          // Filters for the active tab.
          if (isPublic)
            _FilterChips(
              options: [const _Opt(null, 'ALL'), for (final r in _regionsOf(gateway.publicNodes)) _Opt(r, r)],
              selected: _pubRegion,
              onSelect: (v) => setState(() => _pubRegion = v),
            )
          else ...[
            _FilterChips(
              options: const [
                _Opt(null, 'ALL TYPES'),
                _Opt('erebrus', 'STANDARD'),
                _Opt('shield', 'SHIELD'),
                _Opt('sentinel', 'SENTINEL'),
              ],
              selected: _privType,
              onSelect: (v) => setState(() => _privType = v),
            ),
            if (gateway.orgs.length > 1)
              _FilterChips(
                options: [
                  const _Opt(null, 'ALL WORKSPACES'),
                  for (final o in gateway.orgs) _Opt(o.slug, o.name.toUpperCase()),
                ],
                selected: _privWorkspace,
                onSelect: (v) => setState(() => _privWorkspace = v),
              ),
            _FilterChips(
              options: [const _Opt(null, 'ALL REGIONS'), for (final r in _regionsOf(gateway.orgNodes)) _Opt(r, r)],
              selected: _privRegion,
              onSelect: (v) => setState(() => _privRegion = v),
            ),
          ],

          Flexible(
            child: nodes.isEmpty
                ? _emptyState(gateway: gateway, isPublic: isPublic, err: err)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
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
                          showType: !isPublic,
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

  Widget _emptyState({required GatewayController gateway, required bool isPublic, required String? err}) {
    if (!isPublic) {
      if (gateway.orgs.isEmpty) {
        return const NodesEmptyPanel(
          title: 'No private nodes',
          subtitle: "You're not in any organization yet. Private nodes appear here once you own or "
              'join an org that has enrolled nodes.',
        );
      }
      if (gateway.orgNodes.isEmpty) {
        return const NodesEmptyPanel(
          title: 'No nodes in your organizations',
          subtitle: 'An org admin can enroll a Standard, Shield or Sentinel node — it will show up here.',
        );
      }
      return NodesEmptyPanel(
        title: 'No matching nodes',
        subtitle: 'No private nodes match these filters.',
        actionLabel: 'CLEAR FILTERS',
        onRetry: () => setState(() {
          _privType = null;
          _privWorkspace = null;
          _privRegion = null;
        }),
      );
    }
    if (_pubRegion != null && gateway.publicNodes.isNotEmpty) {
      return NodesEmptyPanel(
        title: 'No nodes in $_pubRegion',
        subtitle: 'No public nodes in this region right now.',
        actionLabel: 'ALL REGIONS',
        onRetry: () => setState(() => _pubRegion = null),
      );
    }
    if (gateway.loading.value) return NodesEmptyPanel.registryEmpty(loading: true);
    if (err != null && err.isNotEmpty) {
      return NodesEmptyPanel.registryError(message: err, gatewayUrl: gateway.gatewayUrl.value, onRetry: _refresh);
    }
    return NodesEmptyPanel.registryEmpty(onRetry: _refresh);
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

class _Header extends StatelessWidget {
  const _Header({required this.subtitle, required this.onClose, required this.onRefresh});
  final String subtitle;
  final VoidCallback onClose;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final gateway = Get.find<GatewayController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select node', style: grotesk(size: 18, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: mono(size: 11, weight: FontWeight.w400, color: AppColors.textMuted, letterSpacing: 11 * 0.04)),
            ],
          ),
          const Spacer(),
          Obx(() {
            final busy = gateway.loading.value;
            return GestureDetector(
              onTap: busy ? null : () => onRefresh(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: busy
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                    : const Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
              ),
            );
          }),
          SheetCloseButton(onTap: onClose),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.icon, required this.active, required this.onTap});
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withValues(alpha: 0.16) : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.accent.withValues(alpha: 0.5) : AppColors.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? AppColors.accent : AppColors.textTertiary),
            const SizedBox(width: 8),
            Text(label,
                style: mono(
                    size: 12,
                    weight: FontWeight.w600,
                    color: active ? AppColors.accent : AppColors.textTertiary,
                    letterSpacing: 12 * 0.05)),
          ],
        ),
      ),
    );
  }
}

/// A filter dimension: a horizontally-scrollable row of single-select chips.
class _Opt {
  const _Opt(this.value, this.label);
  final String? value;
  final String label;
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.options, required this.selected, required this.onSelect});
  final List<_Opt> options;
  final String? selected;
  final ValueChanged<String?> onSelect;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (final o in options)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Chip(label: o.label, active: selected == o.value, onTap: () => onSelect(o.value)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.accent.withValues(alpha: 0.5) : AppColors.strokeHi),
        ),
        child: Text(label,
            style: mono(
                size: 11,
                weight: FontWeight.w500,
                color: active ? AppColors.accent : AppColors.textTertiary,
                letterSpacing: 11 * 0.04)),
      ),
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.node,
    required this.selected,
    required this.onTap,
    this.clientPingMs,
    this.probing = false,
    this.showType = false,
  });
  final VpnNode node;
  final bool selected;
  final int? clientPingMs;
  final bool probing;
  final bool showType;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NodeCompactRow(display: d, metrics: NodeMetricsColumn(display: d, probing: probing)),
            if (showType && !node.deploymentProfile.toLowerCase().startsWith('erebrus')) ...[
              const SizedBox(height: 8),
              Row(children: [_TypeBadge(node: node)]),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.node});
  final VpnNode node;
  @override
  Widget build(BuildContext context) {
    final color = node.isSentinel ? AppColors.accent : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(node.isSentinel ? Icons.gpp_good : Icons.shield_outlined, size: 11, color: color),
          const SizedBox(width: 5),
          Text(node.nodeTypeLabel.toUpperCase(),
              style: mono(size: 9.5, weight: FontWeight.w600, color: color, letterSpacing: 9.5 * 0.06)),
        ],
      ),
    );
  }
}
