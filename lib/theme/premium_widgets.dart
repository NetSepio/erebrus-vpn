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

/// An uppercase, tracked section label (IBM Plex Mono).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.letterSpacing = 0.14 * 11, this.color});
  final String text;
  final double letterSpacing;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: mono(size: 11, weight: FontWeight.w600, color: color ?? AppColors.textMuted, letterSpacing: 1.5),
      );
}

/// The Erebrus brand mark — an orange square rotated 45° (placeholder logo).
class BrandDiamond extends StatelessWidget {
  const BrandDiamond({super.key, this.size = 14, this.color = AppColors.accent, this.radius = 2});
  final double size;
  final Color color;
  final double radius;
  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45°
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
      ),
    );
  }
}

/// Brand lockup: diamond + tracked "EREBRUS" wordmark.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandDiamond(size: 14),
        const SizedBox(width: 9),
        Text('EREBRUS', style: mono(size: 13, weight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: 13 * 0.22)),
      ],
    );
  }
}

/// A flat elevated surface with a hairline border (the design's card primitive).
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.radius = AppRadius.card,
    this.color = AppColors.surface,
    this.borderColor = AppColors.stroke,
    this.gradient,
    this.onTap,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final Color borderColor;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: box);
  }
}

/// The primary orange pill CTA: dark text, soft glow, optional trailing icon.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.trailingIcon,
    this.leadingIcon,
    this.expanded = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    this.radius = 30,
    this.fontSize = 15,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? trailingIcon;
  final IconData? leadingIcon;
  final bool expanded;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leadingIcon != null) ...[Icon(leadingIcon, size: 18, color: AppColors.onAccent), const SizedBox(width: 9)],
        Text(label,
            style: const TextStyle(
                fontFamily: AppFonts.display,
                color: AppColors.onAccent,
                fontWeight: FontWeight.w600,
                fontSize: 15).copyWith(fontSize: fontSize)),
        if (trailingIcon != null) ...[const SizedBox(width: 9), Icon(trailingIcon, size: 18, color: AppColors.onAccent)],
      ],
    );
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(color: AppColors.accent.withValues(alpha: 0.55), blurRadius: 24, spreadRadius: -8, offset: const Offset(0, 8)),
          ],
        ),
        child: row,
      ),
    );
  }
}

/// A compact monospace pill (PRIMARY / TRIAL / access labels).
class MonoChip extends StatelessWidget {
  const MonoChip({
    super.key,
    required this.label,
    required this.color,
    this.background,
    this.borderColor,
    this.letterSpacing = 0.1 * 10,
    this.fontSize = 10,
  });
  final String label;
  final Color color;
  final Color? background;
  final Color? borderColor;
  final double letterSpacing;
  final double fontSize;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Text(label, style: mono(size: fontSize, weight: FontWeight.w600, color: color, letterSpacing: letterSpacing)),
    );
  }
}

/// The 46×27 pill toggle from the spec (orange when on, white knob slides 19px).
class EreToggle extends StatelessWidget {
  const EreToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 27,
        decoration: BoxDecoration(
          color: value ? AppColors.accent : const Color(0xFF2A2A32),
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              width: 21,
              height: 21,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
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
