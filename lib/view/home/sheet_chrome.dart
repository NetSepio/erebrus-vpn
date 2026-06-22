import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Shared bottom-sheet chrome: a rounded-top raised surface with a grabber pill,
/// height-capped. Used by the server picker and diagnostics sheets. The slide-up
/// entrance is provided by [showModalBottomSheet].
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.child, this.maxHeightFactor = 0.8});
  final Widget child;
  final double maxHeightFactor;
  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * maxHeightFactor;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        border: Border(top: BorderSide(color: AppColors.strokeHi)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 5,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(3)),
          ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// The 34×34 rounded close button used in sheet headers.
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
      ),
    );
  }
}
