import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';

/// Premium server picker. Bind [nodes] to the gateway discovery list
/// (`GET /api/v2/nodes`); selecting one updates the shared [VpnController].
class ServerView extends StatelessWidget {
  const ServerView({super.key, required this.nodes, this.onSelected});

  final List<VpnNode> nodes;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final c = Get.isRegistered<VpnController>() ? Get.find<VpnController>() : Get.put(VpnController());

    return Scaffold(
      appBar: AppBar(title: const Text('Servers')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.xxl),
        children: [
          _SmartPick(onTap: () {
            c.selectedNode.value = null; // smart pick = let the app choose
            onSelected?.call();
          }),
          const SizedBox(height: AppSpace.xl),
          const SectionLabel('All locations'),
          const SizedBox(height: AppSpace.md),
          if (nodes.isEmpty)
            const _EmptyState()
          else
            ...nodes.map((n) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.md),
                  child: Obx(() => _NodeTile(
                        node: n,
                        selected: c.selectedNode.value?.id == n.id,
                        onTap: () {
                          c.selectNode(n);
                          onSelected?.call();
                        },
                      )),
                )),
        ],
      ),
    );
  }
}

class _SmartPick extends StatelessWidget {
  const _SmartPick({this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      borderColor: AppColors.indigo.withValues(alpha: 0.5),
      child: Row(
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(gradient: AppGradients.aurora, borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: const Icon(Icons.bolt, color: Colors.white),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Smart pick', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('Fastest server for your network', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({required this.node, required this.selected, this.onTap});
  final VpnNode node;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      borderColor: selected ? AppColors.connected.withValues(alpha: 0.6) : null,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(color: AppColors.surfaceHi, borderRadius: BorderRadius.circular(AppRadius.sm)),
            alignment: Alignment.center,
            child: Text(_flag(node.region), style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(node.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Row(children: [
                  if (node.supportsStealth) const _Chip(label: 'Stealth', color: AppColors.stealth),
                  if (node.protocols.contains('wireguard')) const _Chip(label: 'WireGuard', color: AppColors.cyan),
                ]),
              ],
            ),
          ),
          _LoadDot(loadPct: node.loadPct),
          if (selected) ...[
            const SizedBox(width: AppSpace.sm),
            const Icon(Icons.check_circle, color: AppColors.connected, size: 20),
          ],
        ],
      ),
    );
  }

  String _flag(String region) {
    if (region.length < 2) return '🌐';
    final base = 0x1F1E6;
    final cc = region.toUpperCase();
    try {
      return String.fromCharCode(base + cc.codeUnitAt(0) - 65) + String.fromCharCode(base + cc.codeUnitAt(1) - 65);
    } catch (_) {
      return '🌐';
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _LoadDot extends StatelessWidget {
  const _LoadDot({required this.loadPct});
  final double loadPct;
  @override
  Widget build(BuildContext context) {
    final color = loadPct < 50 ? AppColors.connected : (loadPct < 80 ? AppColors.connecting : AppColors.danger);
    return Column(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(height: 4),
        Text('${loadPct.toStringAsFixed(0)}%', style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
      child: Column(
        children: [
          const Icon(Icons.travel_explore, color: AppColors.textMuted, size: 40),
          const SizedBox(height: AppSpace.md),
          Text('No servers yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('Pull to refresh once you’re signed in', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
