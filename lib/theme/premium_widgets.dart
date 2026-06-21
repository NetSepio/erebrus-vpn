import 'dart:ui';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// A frosted-glass surface: subtle blur, hairline stroke, soft top sheen.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.radius = AppRadius.lg,
    this.onTap,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: AppGradients.glass,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor ?? AppColors.stroke, width: 1),
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: card,
    );
  }
}

/// A primary CTA with a gradient fill and a soft glow.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.gradient,
    this.icon,
    this.expanded = true,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Gradient? gradient;
  final IconData? icon;
  final bool expanded;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final g = gradient ?? AppGradients.aurora;
    final child = Container(
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: enabled ? g : null,
        color: enabled ? null : AppColors.surfaceHi,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: enabled
            ? [BoxShadow(color: AppColors.indigo.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: Colors.white), const SizedBox(width: AppSpace.sm)],
          Text(label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.2)),
        ],
      ),
    );
    final tappable = GestureDetector(onTap: enabled ? onPressed : null, child: child);
    return expanded ? SizedBox(width: double.infinity, child: tappable) : tappable;
  }
}

/// An uppercase, tracked section label.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall);
}

/// A compact metric tile (used in the live-stats row).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon, this.color});
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color ?? AppColors.textMuted), const SizedBox(width: 4)],
          Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        ]),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
      ],
    );
  }
}
