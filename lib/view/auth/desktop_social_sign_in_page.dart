import 'package:flutter/material.dart';
import 'package:reown_appkit/modal/constants/key_constants.dart';
import 'package:reown_appkit/modal/widgets/buttons/social_login_buttons_view.dart';
import 'package:reown_appkit/modal/widgets/navigation/navbar.dart';

/// Social/email-only Reown entry on desktop — no wallet list or "Continue with a wallet".
class DesktopSocialSignInPage extends StatelessWidget {
  const DesktopSocialSignInPage() : super(key: KeyConstants.walletListShortPageKey);

  @override
  Widget build(BuildContext context) {
    return const ModalNavbar(
      title: 'Sign in',
      safeAreaLeft: true,
      safeAreaRight: true,
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: SocialLoginButtonsView(),
      ),
    );
  }
}