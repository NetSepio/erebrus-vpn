import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';
import 'connect_view.dart' show fmtData;
import 'node_display.dart';
import 'sheet_chrome.dart';

/// Presents the network-diagnostics bottom sheet.
Future<void> showDiagnosticsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => const SheetFrame(maxHeightFactor: 0.8, child: _DiagnosticsSheet()),
  );
}

class _DiagnosticsSheet extends StatelessWidget {
  const _DiagnosticsSheet();

  @override
  Widget build(BuildContext context) {
    final vpn = Get.find<VpnController>();
    final settings = Get.isRegistered<AppSettingsController>() ? Get.find<AppSettingsController>() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
          child: Row(
            children: [
              const Icon(Icons.show_chart, size: 20, color: AppColors.accent),
              const SizedBox(width: 10),
              Text('Network diagnostics', style: grotesk(size: 18, weight: FontWeight.w600)),
              const Spacer(),
              SheetCloseButton(onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
        Flexible(
          child: Obx(() {
            final connected = vpn.isConnected;
            final node = vpn.selectedNode.value;
            final d = NodeDisplay.of(node);
            final stats = vpn.stats.value;
            final mode = vpn.mode.value;
            final transport = vpn.activeTransport.value;
            final protocolLabel = switch (mode) {
              ConnectMode.auto => 'Auto',
              ConnectMode.stealth => 'Stealth',
              ConnectMode.wireguard => 'WireGuard',
            };

            final rows = connected
                ? <_Row>[
                    _Row('Connection', d.name, AppColors.textPrimary),
                    _Row('Protocol', protocolLabel, AppColors.accent),
                    if (transport != null) _Row('Transport', transport.label, AppColors.textSecondary),
                    _Row('Network', '${d.network} · ${d.location}', AppColors.textSecondary),
                    _Row('Throughput', '↓ ${fmtData(stats.rxBytes)}   ↑ ${fmtData(stats.txBytes)}', AppColors.textSecondary),
                    _Row('Rate', '↓ ${_rate(stats.downlinkBps)}  ↑ ${_rate(stats.uplinkBps)}', AppColors.textSecondary),
                    _Row('DNS', 'Tunnel DNS → ${vpn.selectedNode.value != null ? "node resolver" : "upstream"}', AppColors.success),
                    const _Row('MTU', '1280', AppColors.textSecondary),
                    _Row('Kill switch', (settings?.killSwitchEnabled.value ?? true) ? 'On' : 'Off',
                        (settings?.killSwitchEnabled.value ?? true) ? AppColors.success : AppColors.textSecondary),
                  ]
                : <_Row>[
                    const _Row('Connection', 'Not connected', AppColors.danger),
                    _Row('Protocol', protocolLabel, AppColors.textSecondary),
                    _Row('Nearest node', d.name, AppColors.textSecondary),
                    const _Row('DNS', 'system default', AppColors.warn),
                  ];

            return ListView(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
              shrinkWrap: true,
              children: [
                _Banner(connected: connected),
                for (final r in rows) _KeyValueRow(row: r),
              ],
            );
          }),
        ),
      ],
    );
  }

  String _rate(int bps) {
    if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(1)} MB/s';
    if (bps >= 1000) return '${(bps / 1000).toStringAsFixed(0)} KB/s';
    return '$bps B/s';
  }
}

class _Row {
  const _Row(this.k, this.v, this.color);
  final String k;
  final String v;
  final Color color;
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.row});
  final _Row row;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.strokeSoft))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.k, style: grotesk(size: 13.5, weight: FontWeight.w400, color: AppColors.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(row.v,
                textAlign: TextAlign.right,
                style: mono(size: 12.5, weight: FontWeight.w500, color: row.color)),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.connected});
  final bool connected;
  @override
  Widget build(BuildContext context) {
    final color = connected ? AppColors.success : AppColors.danger;
    final label = connected ? 'TUNNEL ACTIVE · TRAFFIC ENCRYPTED' : 'UNPROTECTED · TRAFFIC EXPOSED';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          connected
              ? _BlinkDot(color: color)
              : Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 9),
          Text(label, style: mono(size: 12.5, weight: FontWeight.w600, color: color, letterSpacing: 0.2)),
        ],
      ),
    );
  }
}

class _BlinkDot extends StatefulWidget {
  const _BlinkDot({required this.color});
  final Color color;
  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.25).animate(_c),
      child: Container(width: 9, height: 9, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
    );
  }
}
