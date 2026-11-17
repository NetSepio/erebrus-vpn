import 'package:flutter/material.dart';

import '../../platform/platform_capabilities.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../home/sheet_chrome.dart';

/// Shared building blocks for the in-app browser so every browser surface —
/// menus, tab switcher, link menu, empty/error states — uses the same sheet
/// chrome, rows and spacing as the rest of the app (diagnostics, server
/// picker).

/// Horizontal inset shared by every browser row (tab strip, address bar,
/// session status, start page, bottom bar) so their edges line up.
const double kBrowserGutter = 16;

/// Height of the mobile bottom browser bar (back/forward/home/tabs/menu).
const double kBrowserBarHeight = 59;

/// Presents [builder] in the app's standard bottom-sheet frame (raised surface,
/// grabber, dimmed barrier).
Future<T?> showBrowserSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxHeightFactor = 0.82,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => SheetFrame(
      maxHeightFactor: maxHeightFactor,
      child: SafeArea(top: false, child: builder(ctx)),
    ),
  );
}

/// Sheet title row: accent icon, title, optional extra action, close button.
class BrowserSheetHeader extends StatelessWidget {
  const BrowserSheetHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.count,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int? count;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 18, 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: grotesk(size: 18, weight: FontWeight.w600),
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 8),
                      MonoChip(
                        label: '$count',
                        color: AppColors.textSecondary,
                        background: AppColors.surface2,
                        borderColor: AppColors.stroke,
                      ),
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: mono(size: 11, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
          const SizedBox(width: 8),
          SheetCloseButton(onTap: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

/// A sheet action row: icon chip, title, optional subtitle and trailing widget.
class BrowserSheetTile extends StatelessWidget {
  const BrowserSheetTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.stroke),
                ),
                child: Icon(icon, size: 18, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: grotesk(size: 15, weight: FontWeight.w600),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: grotesk(size: 12, color: AppColors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Grouped list of [BrowserSheetTile]s on a surface card.
class BrowserSheetGroup extends StatelessWidget {
  const BrowserSheetGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SurfaceCard(
        padding: const EdgeInsets.all(6),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Full-area browser state (start-up, error, VPN required): icon badge,
/// title, message and an optional action — one look for every non-page state.
class BrowserStatePanel extends StatelessWidget {
  const BrowserStatePanel({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.tone = AppColors.textSecondary,
    this.loading = false,
    this.actionLabel,
    this.onAction,
    this.monoMessage = false,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// Render [message] in the monospace face (URLs, addresses).
  final bool monoMessage;
  final Color tone;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                child: loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tone,
                        ),
                      )
                    : Icon(icon, size: 24, color: tone),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: grotesk(size: 18, weight: FontWeight.w600),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: monoMessage
                      ? mono(size: 12, color: AppColors.textTertiary)
                      : grotesk(
                          size: 13.5,
                          color: AppColors.textSecondary,
                        ).copyWith(height: 1.45),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                PrimaryButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  fontSize: 14,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating snackbar in the app's surface style.
void showBrowserToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: grotesk(size: 13.5)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface3,
      // Snackbars render in the shell's root Scaffold, not the browser's, so
      // lift them over the mobile browser bar instead of covering it.
      margin: EdgeInsets.fromLTRB(
        kBrowserGutter,
        0,
        kBrowserGutter,
        PlatformCapabilities.isDesktop
            ? kBrowserGutter
            : kBrowserBarHeight + 10,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.strokeHi),
      ),
    ),
  );
}
