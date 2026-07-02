import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'node_display.dart';

/// Compact node row — flag column, inline org, chain + pills, tight metrics.
class NodeCompactRow extends StatelessWidget {
  const NodeCompactRow({
    super.key,
    required this.display,
    this.nameSize = 13.5,
    this.metrics,
  });

  final NodeDisplay display;
  final double nameSize;
  final Widget? metrics;

  @override
  Widget build(BuildContext context) {
    final d = display;
    return Row(
      // `start` avoids tight cross-axis constraints on [Expanded] children when a
      // sibling (e.g. the flag column) is shorter than the main text/metrics block.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NodeFlagColumn(flag: d.flag, regionLabel: d.regionCompact),
        const SizedBox(width: 13),
        Expanded(child: _NodeMainColumn(display: d, nameSize: nameSize, metrics: metrics)),
      ],
    );
  }
}

class NodeFlagColumn extends StatelessWidget {
  const NodeFlagColumn({super.key, required this.flag, required this.regionLabel});

  final String flag;
  final String regionLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 42,
            child: Text(
              flag,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, height: 1),
            ),
          ),
          if (regionLabel.isNotEmpty) ...[
            const SizedBox(height: 3),
            SizedBox(
              width: 42,
              child: Text(
                regionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: mono(size: 10, weight: FontWeight.w500, color: AppColors.textTertiary, height: 1.1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NodeMainColumn extends StatelessWidget {
  const _NodeMainColumn({required this.display, required this.nameSize, this.metrics});
  final NodeDisplay display;
  final double nameSize;
  final Widget? metrics;

  @override
  Widget build(BuildContext context) {
    final d = display;
    final orgName = d.orgNameLine;
    final nameStyle = mono(size: nameSize, weight: FontWeight.w600, color: AppColors.textPrimary);
    final orgStyle = grotesk(size: 10.5, weight: FontWeight.w500, color: AppColors.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: d.name, style: nameStyle),
              if (d.org != null && orgName != null) ...[
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: NodeOrgKindIcon(kind: d.org!.kind, size: 12),
                  ),
                ),
                TextSpan(text: ' $orgName', style: orgStyle),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: NodeVerifiedIcon(verified: d.org!.verified, size: 13),
                  ),
                ),
              ],
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            if (d.showSolanaBadge) ...[
              const SolanaLogoMark(size: 14),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Wrap(
                spacing: 5,
                runSpacing: 3,
                children: [
                  NodeAccessPill(label: d.network, color: d.networkColor),
                  NodeAccessPill(label: d.accessLabel, color: d.accessColor),
                  if (d.tierLabel != null) NodeAccessPill(label: d.tierLabel!, color: AppColors.warn),
                ],
              ),
            ),
          ],
        ),
        if (metrics != null) ...[
          const SizedBox(height: 4),
          metrics!,
        ],
      ],
    );
  }
}

class NodeVerifiedIcon extends StatelessWidget {
  const NodeVerifiedIcon({super.key, required this.verified, this.size = 13});
  final bool verified;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      verified ? Icons.verified : Icons.verified_outlined,
      size: size,
      color: verified ? AppColors.success : AppColors.textMuted.withValues(alpha: 0.45),
    );
  }
}

class NodeMetricsColumn extends StatelessWidget {
  const NodeMetricsColumn({
    super.key,
    required this.display,
    this.probing = false,
  });

  final NodeDisplay display;
  final bool probing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            NodeMetricCell(
              label: 'PING',
              value: display.pingLabel(probing: probing),
              valueColor: display.pingColor(probing: probing),
            ),
            NodeMetricCell(
              label: 'LOAD',
              value: display.loadLabel,
              valueColor: display.loadColor,
            ),
            if (display.showActivity && display.activityTime != null)
              NodeActivityDot(time: display.activityTime!, live: display.activityLive),
            if (display.showNodeSpeedtest) ...[
              NodeMetricCell(label: '↓', value: display.downloadLabel),
              NodeMetricCell(label: '↑', value: display.uploadLabel),
              const NodeUnitPill(label: 'Mbps'),
            ],
          ],
        ),
      ],
    );
  }
}

class NodeActivityDot extends StatelessWidget {
  const NodeActivityDot({super.key, required this.time, required this.live});
  final String time;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: live ? AppColors.success : AppColors.danger,
            boxShadow: live
                ? [BoxShadow(color: AppColors.success.withValues(alpha: 0.45), blurRadius: 4)]
                : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          time,
          style: mono(
            size: 10,
            weight: FontWeight.w500,
            color: live ? AppColors.textSecondary : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class NodeOrgKindIcon extends StatelessWidget {
  const NodeOrgKindIcon({super.key, required this.kind, this.size = 12});
  final String? kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = (kind ?? '').toLowerCase();
    final icon = switch (k) {
      'individual' => Icons.person_outline,
      'company' => Icons.business_outlined,
      'family' => Icons.home_outlined,
      _ => Icons.groups_outlined,
    };
    return Icon(icon, size: size, color: AppColors.textSecondary);
  }
}

class SolanaLogoMark extends StatelessWidget {
  const SolanaLogoMark({super.key, this.size = 14});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Solana',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: AppGradients.solana,
        ),
        child: CustomPaint(painter: _SolanaBarsPainter(), size: Size.square(size)),
      ),
    );
  }
}

class _SolanaBarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.95);
    final w = size.width;
    final h = size.height;
    final barH = h * 0.11;
    final gap = h * 0.09;
    final left = w * 0.22;
    final right = w * 0.78;
    var y = h * 0.24;
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(left, y, right, y + barH), Radius.circular(barH / 2)),
        paint,
      );
      y += barH + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class NodeAccessPill extends StatelessWidget {
  const NodeAccessPill({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), border: Border.all(color: color)),
      child: Text(label, style: mono(size: 9.5, weight: FontWeight.w400, color: color)),
    );
  }
}

class NodeUnitPill extends StatelessWidget {
  const NodeUnitPill({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.stroke),
        color: AppColors.surface2,
      ),
      child: Text(
        label,
        style: mono(size: 9, weight: FontWeight.w500, color: AppColors.textMuted),
      ),
    );
  }
}

class NodeMetricCell extends StatelessWidget {
  const NodeMetricCell({super.key, required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(label, style: mono(size: 9, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 0.4, height: 1)),
        const SizedBox(width: 3),
        Text(
          value,
          style: mono(size: 11.5, weight: FontWeight.w600, color: valueColor ?? AppColors.textPrimary, height: 1),
        ),
      ],
    );
  }
}