import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/gateway_auth_client.dart';
import '../../auth/wallet_auth_controller.dart';
import '../../theme/app_theme.dart';

Future<void> showEmailLinkSheet(BuildContext context, WalletAuthController auth) async {
  if (!auth.isAuthenticated) {
    Get.snackbar('Sign in required', 'Connect your wallet first', snackPosition: SnackPosition.BOTTOM);
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => _EmailLinkSheet(auth: auth),
  );
}

class _EmailLinkSheet extends StatefulWidget {
  const _EmailLinkSheet({required this.auth});

  final WalletAuthController auth;

  @override
  State<_EmailLinkSheet> createState() => _EmailLinkSheetState();
}

class _EmailLinkSheetState extends State<_EmailLinkSheet> {
  late final TextEditingController _emailCtrl;
  late final TextEditingController _codeCtrl;
  var _step = 0;
  var _pendingEmail = '';

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController();
    _codeCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    try {
      await widget.auth.startEmailLink(email);
      setState(() {
        _pendingEmail = email;
        _step = 1;
      });
    } on AuthException catch (e) {
      Get.snackbar('Email', e.message, snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _verify() async {
    try {
      await widget.auth.verifyEmailLink(email: _pendingEmail, code: _codeCtrl.text.trim());
      if (mounted) Navigator.of(context).pop();
      Get.snackbar('Email linked', _pendingEmail, snackPosition: SnackPosition.BOTTOM);
    } on AuthException catch (e) {
      Get.snackbar('Verification failed', e.message, snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 18, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _step == 0 ? 'Link recovery email' : 'Enter verification code',
              style: grotesk(size: 18, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _step == 0
                  ? 'We\'ll send a 6-digit code to verify ownership. Requires an active wallet session.'
                  : 'Code sent to $_pendingEmail',
              style: grotesk(size: 13, color: AppColors.textTertiary, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (_step == 0) ...[
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(hintText: 'you@example.com'),
              ),
              const SizedBox(height: 14),
              Obx(() => GestureDetector(
                    onTap: widget.auth.isLinkingEmail.value ? null : _sendCode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.auth.isLinkingEmail.value ? 'SENDING…' : 'SEND CODE',
                        style: mono(size: 13, weight: FontWeight.w600, color: AppColors.onAccent),
                      ),
                    ),
                  )),
            ] else ...[
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(hintText: '123456'),
              ),
              const SizedBox(height: 14),
              Obx(() => GestureDetector(
                    onTap: widget.auth.isLinkingEmail.value ? null : _verify,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.auth.isLinkingEmail.value ? 'VERIFYING…' : 'VERIFY & LINK',
                        style: mono(size: 13, weight: FontWeight.w600, color: AppColors.onAccent),
                      ),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showEditProfileSheet(BuildContext context, WalletAuthController auth) async {
  if (!auth.isAuthenticated) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => _EditProfileSheet(auth: auth),
  );
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.auth});

  final WalletAuthController auth;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.auth.profileName.value);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await widget.auth.updateDisplayName(_nameCtrl.text);
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (e) {
      Get.snackbar('Profile', e.message, snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 18, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit profile', style: grotesk(size: 18, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Display name shown on leaderboards and referrals.',
              style: grotesk(size: 13, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Your name'),
            ),
            const SizedBox(height: 14),
            Obx(() => GestureDetector(
                  onTap: widget.auth.isLoadingProfile.value ? null : _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.auth.isLoadingProfile.value ? 'SAVING…' : 'SAVE',
                      style: mono(size: 13, weight: FontWeight.w600, color: AppColors.onAccent),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}