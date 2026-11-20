import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../auth/wallet_auth_controller.dart';
import '../onboarding/onboarding_view.dart';
import '../settings/app_settings_controller.dart';
import '../theme/app_theme.dart';
import '../theme/premium_widgets.dart';
import 'bottombar/main_shell.dart';

/// Top-level router: first-launch onboarding → sign-in → the app.
///
/// Onboarding shows only until the "seen" flag is persisted; thereafter an
/// unauthenticated user lands on login, and any authenticated session (wallet,
/// email, Google, or Apple) opens the dVPN tab. Logging out returns here.
class RootView extends StatelessWidget {
  const RootView({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<AppSettingsController>();
    final auth = Get.find<WalletAuthController>();

    return Obx(() {
      final Widget screen;
      if (!settings.onboardingSeen.value) {
        screen = OnboardingView(key: const ValueKey('onboarding'), onDone: settings.markOnboardingSeen);
      } else if (!auth.sessionReady.value) {
        screen = const _Splash(key: ValueKey('splash'));
      } else {
        screen = const MainShell(key: ValueKey('app'));
      }

      return PrivacyCover(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: screen,
        ),
      );
    });
  }
}

/// Covers the UI whenever the app is not frontmost, so the snapshot the OS
/// takes for the app switcher shows the brand rather than a node list, a
/// wallet balance or an open workspace.
///
/// Android gets this from `FLAG_SECURE` in `MainActivity`, which also blocks
/// screenshots and screen recording outright. Apple platforms have no such
/// flag, so this cover is the whole mechanism there — and it has to be up on
/// `inactive`, not `paused`, because that is the state the snapshot is taken
/// in.
class PrivacyCover extends StatefulWidget {
  const PrivacyCover({super.key, required this.child});

  final Widget child;

  /// Whether this platform needs the cover. Android is handled natively.
  static bool get applies =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  State<PrivacyCover> createState() => _PrivacyCoverState();
}

class _PrivacyCoverState extends State<PrivacyCover>
    with WidgetsBindingObserver {
  bool _covered = false;

  /// Whether this state registered as an observer. Recomputing the platform
  /// test at dispose time risks removing nothing after having added one, which
  /// leaves a dead observer taking lifecycle callbacks for ever.
  bool _observing = false;

  @override
  void initState() {
    super.initState();
    _observing = PrivacyCover.applies;
    if (_observing) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final cover = state != AppLifecycleState.resumed;
    if (cover != _covered) setState(() => _covered = cover);
  }

  @override
  Widget build(BuildContext context) {
    if (!PrivacyCover.applies) return widget.child;
    return Stack(
      children: [
        widget.child,
        if (_covered)
          const Positioned.fill(
            key: ValueKey('privacy-cover'),
            child: ColoredBox(
              color: AppColors.bg,
              child: Center(
                child: BrandLogo(size: 44, radius: 12, showShadow: false),
              ),
            ),
          ),
      ],
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandLogo(size: 44, radius: 12, showShadow: true),
            SizedBox(height: 22),
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
          ],
        ),
      ),
    );
  }
}
