import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/gateway_auth_client.dart';
import '../../auth/wallet_auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';

Future<void> showEmailLinkSheet(BuildContext context, WalletAuthController auth) async {
  if (!auth.isAuthenticated) {
    Get.snackbar('Sign in required', 'Connect your wallet first', snackPosition: SnackPosition.BOTTOM);
    return;
  }
  final emailCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  var step = 0;
  var pendingEmail = '';

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(22, 18, 22, 22 + MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (context, setState) {
            Future<void> sendCode() async {
              final email = emailCtrl.text.trim();
              if (email.isEmpty) return;
              try {
                await auth.startEmailLink(email);
                pendingEmail = email;
                setState(() => step = 1);
              } on AuthException catch (e) {
                Get.snackbar('Email', e.message, snackPosition: SnackPosition.BOTTOM);
              }
            }

            Future<void> verify() async {
              try {
                await auth.verifyEmailLink(email: pendingEmail, code: codeCtrl.text.trim());
                if (ctx.mounted) Navigator.of(ctx).pop();
                Get.snackbar('Email linked', pendingEmail, snackPosition: SnackPosition.BOTTOM);
              } on AuthException catch (e) {
                Get.snackbar('Verification failed', e.message, snackPosition: SnackPosition.BOTTOM);
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(step == 0 ? 'Link recovery email' : 'Enter verification code',
                    style: grotesk(size: 18, weight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  step == 0
                      ? 'We\'ll send a 6-digit code to verify ownership. Requires an active wallet session.'
                      : 'Code sent to $pendingEmail',
                  style: grotesk(size: 13, color: AppColors.textTertiary, height: 1.4),
                ),
                const SizedBox(height: 16),
                if (step == 0) ...[
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(hintText: 'you@example.com'),
                  ),
                  const SizedBox(height: 14),
                  Obx(() => GestureDetector(
                        onTap: auth.isLinkingEmail.value ? null : sendCode,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            auth.isLinkingEmail.value ? 'SENDING…' : 'SEND CODE',
                            style: mono(size: 13, weight: FontWeight.w600, color: AppColors.onAccent),
                          ),
                        ),
                      )),
                ] else ...[
                  TextField(
                    controller: codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(hintText: '123456'),
                  ),
                  const SizedBox(height: 14),
                  Obx(() => GestureDetector(
                        onTap: auth.isLinkingEmail.value ? null : verify,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            auth.isLinkingEmail.value ? 'VERIFYING…' : 'VERIFY & LINK',
                            style: mono(size: 13, weight: FontWeight.w600, color: AppColors.onAccent),
                          ),
                        ),
                      )),
                ],
              ],
            );
          },
        ),
      );
    },
  );
  emailCtrl.dispose();
  codeCtrl.dispose();
}

Future<void> showEditProfileSheet(BuildContext context, WalletAuthController auth) async {
  if (!auth.isAuthenticated) return;
  final nameCtrl = TextEditingController(text: auth.profileName.value);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(22, 18, 22, 22 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit profile', style: grotesk(size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Display name shown on leaderboards and referrals.',
                style: grotesk(size: 13, color: AppColors.textTertiary)),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Your name'),
            ),
            const SizedBox(height: 14),
            Obx(() => GestureDetector(
                  onTap: auth.isLoadingProfile.value
                      ? null
                      : () async {
                          try {
                            await auth.updateDisplayName(nameCtrl.text);
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          } on AuthException catch (e) {
                            Get.snackbar('Profile', e.message, snackPosition: SnackPosition.BOTTOM);
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      auth.isLoadingProfile.value ? 'SAVING…' : 'SAVE',
                      style: mono(size: 13, weight: FontWeight.w600, color: AppColors.onAccent),
                    ),
                  ),
                )),
          ],
        ),
      );
    },
  );
  nameCtrl.dispose();
}