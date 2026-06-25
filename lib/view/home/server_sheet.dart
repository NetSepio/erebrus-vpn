import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../theme/app_theme.dart';
import '../../vpn/gateway_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';
import 'node_display.dart';
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

  @override
  Widget build(BuildContext context) {
    final gateway = Get.find<GatewayController>();
    final vpn = Get.find<VpnController>();

    return Obx(() {
      final nodes = gateway.nodes
          .where((n) => _filter == 'all' || NodeDisplay.of(n).access == _filter)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // header
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select node', style: grotesk(size: 18, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${nodes.length} NODES AVAILABLE',
                        style: mono(size: 11, weight: FontWeight.w400, color: AppColors.textMuted, letterSpacing: 11 * 0.04)),
                  ],
                ),
                const Spacer(),
                Obx(() {
                  final busy = gateway.loading.value;
                  return GestureDetector(
                    onTap: busy ? null : gateway.refreshNodes,
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
          // search (decorative)
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
          // filter chips
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
          // node rows
          Flexible(
            child: nodes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        _filter == 'all'
                            ? 'No nodes available yet'
                            : 'No $_filter nodes for this wallet',
                        style: grotesk(size: 13.5, weight: FontWeight.w400, color: AppColors.textMuted),
                      ),
                    ),
                  )
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

  void _select(VpnController vpn, VpnNode node) {
    Navigator.of(context).pop();
    if (vpn.isConnected) {
      // Changing node while connected triggers a reconnect.
      vpn.connect(node: node);
    } else {
      vpn.selectNode(node);
    }
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({required this.node, required this.selected, required this.onTap});
  final VpnNode node;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = NodeDisplay.of(node);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withValues(alpha: 0.08) : AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.accent.withValues(alpha: 0.55) : AppColors.stroke),
        ),
        child: Row(
          children: [
            Text(d.flag, style: const TextStyle(fontSize: 24, height: 1)),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.name, style: mono(size: 13.5, weight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 7,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(d.location, style: grotesk(size: 11.5, weight: FontWeight.w400, color: AppColors.textTertiary)),
                      Container(width: 4, height: 4, decoration: BoxDecoration(color: d.networkColor, shape: BoxShape.circle)),
                      Text(d.network, style: mono(size: 10.5, weight: FontWeight.w400, color: AppColors.textTertiary)),
                      _AccessPill(label: d.accessLabel, color: d.accessColor),
                      if (d.tierLabel != null)
                        _AccessPill(label: d.tierLabel!, color: AppColors.warn),
                      if (d.supportsStealth)
                        Text('stealth', style: mono(size: 10.5, weight: FontWeight.w400, color: AppColors.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(d.loadLabel, style: mono(size: 13, weight: FontWeight.w600, color: d.loadColor)),
                const SizedBox(height: 2),
                Text('load', style: mono(size: 10, weight: FontWeight.w400, color: AppColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessPill extends StatelessWidget {
  const _AccessPill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), border: Border.all(color: color)),
      child: Text(label, style: mono(size: 10, weight: FontWeight.w400, color: color)),
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

