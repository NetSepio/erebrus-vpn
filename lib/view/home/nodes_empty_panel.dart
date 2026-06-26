import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Empty / error state for the node picker and connect server card.
class NodesEmptyPanel extends StatelessWidget {
  const NodesEmptyPanel({
    super.key,
    required this.title,
    required this.subtitle,
    this.detail,
    this.loading = false,
    this.onRetry,
    this.actionLabel,
  });

  final String title;
  final String subtitle;
  final String? detail;
  final bool loading;
  final VoidCallback? onRetry;
  final String? actionLabel;

  factory NodesEmptyPanel.registryEmpty({bool loading = false, VoidCallback? onRetry}) {
    return NodesEmptyPanel(
      title: loading ? 'Checking registry…' : 'No community nodes online',
      subtitle: loading
          ? 'Querying the Erebrus gateway for available servers'
          : 'Operators register nodes on the NetSepio network. Tap refresh when one comes online.',
      loading: loading,
      onRetry: onRetry,
    );
  }

  factory NodesEmptyPanel.registryError({
    required String message,
    String? gatewayUrl,
    VoidCallback? onRetry,
  }) {
    final is404 = message.contains('404') || message.toLowerCase().contains('not found');
    return NodesEmptyPanel(
      title: is404 ? 'Registry unavailable' : 'Could not load servers',
      subtitle: is404
          ? 'The gateway did not return a node list. Check your connection or try again.'
          : message,
      detail: gatewayUrl,
      onRetry: onRetry,
    );
  }

  factory NodesEmptyPanel.filteredEmpty({
    required String filter,
    required int totalOnline,
    VoidCallback? onShowAll,
  }) {
    return NodesEmptyPanel(
      title: 'No $filter nodes',
      subtitle: totalOnline == 0
          ? 'No community nodes are online right now.'
          : '$totalOnline node${totalOnline == 1 ? '' : 's'} online under ALL — switch filters to browse.',
      onRetry: onShowAll,
      actionLabel: 'SHOW ALL',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
            ),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                  )
                : Icon(
                    Icons.hub_outlined,
                    size: 26,
                    color: AppColors.accent.withValues(alpha: 0.85),
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: grotesk(size: 16, weight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: grotesk(size: 13.5, color: AppColors.textTertiary, height: 1.45),
          ),
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: mono(size: 11, color: AppColors.textMuted),
            ),
          ],
          if (onRetry != null && !loading) ...[
            const SizedBox(height: 18),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
                ),
                child: Text(
                  actionLabel ?? 'TRY AGAIN',
                  style: mono(size: 12, weight: FontWeight.w600, color: AppColors.accent, letterSpacing: 12 * 0.05),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}