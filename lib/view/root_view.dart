import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../auth/wallet_auth_controller.dart';
import '../onboarding/onboarding_view.dart';
import '../settings/app_settings_controller.dart';
import '../theme/app_theme.dart';
import '../theme/premium_widgets.dart';
import 'auth/login_view.dart';
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
      } else if (!auth.isAuthenticated) {
        screen = const LoginView(key: ValueKey('login'));
      } else {
        screen = const MainShell(key: ValueKey('app'));
      }

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: screen,
      );
    });
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
