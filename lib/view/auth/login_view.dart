import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../auth/runtime_config.dart';
import '../../auth/wallet_auth_controller.dart';
import '../../platform/platform_capabilities.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';

/// Branded sign-in launcher (RenownKit / Reown AppKit + Solana Mobile Wallet
/// Adapter). Each method opens the real auth flow; the provider is chosen in the
/// wallet/social modal, and a full-screen connecting overlay shows while the
/// gateway verifies the signed challenge. On success the auth session updates
/// and the app router routes to the dVPN tab.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  Worker? _authWorker;

  @override
  void initState() {
    super.initState();
    // Re-discover gateway login methods on every visit: the app-start fetch is
    // best-effort, and a transient failure there would otherwise hide Google
    // sign-in until the app restarts.
    unawaited(Get.find<WalletAuthController>().loadAuthMethods());
    _authWorker = ever(
      Get.find<WalletAuthController>().sessionActive,
      (isActive) {
        if (isActive && mounted && Navigator.of(context).canPop()) {
          Get.back();
        }
      },
    );
  }

  @override
  void dispose() {
    _authWorker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<WalletAuthController>();
    // Seeker/Saga: MWA wallet-only. Desktop: browser sign-in at erebrus.io.
    final solanaOnly = auth.isSolanaMobileDevice.value;
    final webLogin = PlatformCapabilities.usesWebLogin;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.88),
            radius: 1.0,
            colors: [Color(0xFF1A1209), AppColors.bg],
            stops: [0.0, 0.5],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(30, 14, 30, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 26, 0, 30),
                      child: Column(
                        children: [
                          const BrandLogo(size: 56, radius: 16, showShadow: true),
                          const SizedBox(height: 18),
                          Text('Welcome to Erebrus',
                              textAlign: TextAlign.center,
                              style: grotesk(size: 26, weight: FontWeight.w600, letterSpacing: -0.52)),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 280,
                            child: Text(
                              'Sign in to enter your personal, private internet',
                              textAlign: TextAlign.center,
                              style: grotesk(size: 14.5, weight: FontWeight.w400, color: AppColors.textTertiary, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (solanaOnly) ...[
                      // Solana Mobile: wallet-only sign-in via Seed Vault / MWA.
                      _WalletButton(
                        onTap: () => _signIn(auth),
                        gradient: AppGradients.solana,
                        title: 'Connect Solana Wallet',
                        subtitle: 'Seed Vault · Phantom · Solflare · Backpack',
                        borderColor: AppColors.accent.withValues(alpha: 0.45),
                        background: AppColors.accent.withValues(alpha: 0.07),
                        trailing: MonoChip(
                          label: 'SEED VAULT',
                          color: AppColors.accent,
                          background: AppColors.accent.withValues(alpha: 0.14),
                          letterSpacing: 10 * 0.06,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_outline, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text('Your wallet signs you in — no passwords, no email.',
                                textAlign: TextAlign.center,
                                style: grotesk(size: 12.5, weight: FontWeight.w400, color: AppColors.textMuted, height: 1.4)),
                          ),
                        ],
                      ),
                    ] else if (webLogin) ...[
                      _OutlinedAuthButton(
                        onTap: () => _signIn(auth),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.open_in_browser, size: 20, color: AppColors.accent),
                            const SizedBox(width: 11),
                            Text('Sign in with browser', style: grotesk(size: 15, weight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Opens ${RuntimeConfig.erebrusWebOrigin} in your browser.\n'
                        'After you sign in, you\'ll return here automatically.',
                        textAlign: TextAlign.center,
                        style: grotesk(size: 12.5, weight: FontWeight.w400, color: AppColors.textMuted, height: 1.45),
                      ),
                    ] else ...[
                      Obx(() {
                        final emailOk = auth.emailLoginAvailable;
                        final googleOk = auth.googleLoginAvailable;
                        final appleOk = auth.appleLoginAvailable;
                        if (!emailOk && !googleOk && !appleOk) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (emailOk)
                              _OutlinedAuthButton(
                                onTap: () => _openEmailLogin(context, auth),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.mail_outline, size: 20, color: AppColors.accent),
                                    const SizedBox(width: 11),
                                    Text('Continue with Email', style: grotesk(size: 15, weight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            if (googleOk) ...[
                              const SizedBox(height: 11),
                              _SocialAuthButton(
                                label: 'Continue with Google',
                                icon: Icons.g_mobiledata_rounded,
                                onTap: auth.signInWithGoogle,
                              ),
                            ],
                            if (appleOk) ...[
                              const SizedBox(height: 11),
                              _SocialAuthButton(
                                label: 'Continue with Apple',
                                icon: Icons.apple,
                                onTap: auth.signInWithApple,
                              ),
                            ],
                            const _AuthDivider(label: 'CONNECT A WALLET'),
                          ],
                        );
                      }),
                      _WalletButton(
                        onTap: () => _signIn(auth),
                        gradient: AppGradients.solana,
                        title: 'Solana',
                        subtitle: 'Phantom · Solflare · Backpack',
                        borderColor: AppColors.accent.withValues(alpha: 0.45),
                        background: AppColors.accent.withValues(alpha: 0.07),
                        trailing: MonoChip(
                          label: 'PRIMARY',
                          color: AppColors.accent,
                          background: AppColors.accent.withValues(alpha: 0.14),
                          letterSpacing: 10 * 0.08,
                        ),
                      ),
                      const SizedBox(height: 11),
                      _WalletButton(
                        onTap: () => _signIn(auth),
                        gradient: AppGradients.ethereum,
                        title: 'Ethereum',
                        subtitle: 'MetaMask · WalletConnect',
                        borderColor: Colors.white.withValues(alpha: 0.1),
                        background: const Color(0xFF131318),
                      ),
                    ],

                    if (webLogin) ...[
                      const SizedBox(height: 22),
                      const _PasteTokenSection(),
                    ],

                    const SizedBox(height: 26),
                    Obx(() {
                      final err = auth.authError.value;
                      if (err == null || err.isEmpty) {
                        return Text(
                          "By continuing you agree to Erebrus's\nTerms of Service & Privacy Policy.",
                          textAlign: TextAlign.center,
                          style: grotesk(size: 11.5, weight: FontWeight.w400, color: AppColors.textDim, height: 1.5),
                        );
                      }
                      return Text(err,
                          textAlign: TextAlign.center,
                          style: grotesk(size: 12.5, weight: FontWeight.w500, color: AppColors.danger, height: 1.4));
                    }),
                  ],
                ),
              ),

              // connecting overlay
              Obx(() {
                if (!auth.isAuthenticating.value && !auth.awaitingWebCallback.value) {
                  return const SizedBox.shrink();
                }
                return _ConnectingOverlay(
                  waitingForBrowser: auth.awaitingWebCallback.value && !auth.isAuthenticating.value,
                  onPasteFromClipboard: () => auth.signInFromClipboard(),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _signIn(WalletAuthController auth) {
    auth.openSignIn();
  }

  void _openEmailLogin(BuildContext context, WalletAuthController auth) {
    auth.authError.value = null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: const _EmailLoginSheet(),
      ),
    );
  }
}

class _SocialAuthButton extends StatelessWidget {
  const _SocialAuthButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return _OutlinedAuthButton(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: AppColors.textPrimary),
          const SizedBox(width: 11),
          Text(label, style: grotesk(size: 15, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _EmailLoginSheet extends StatefulWidget {
  const _EmailLoginSheet();
  @override
  State<_EmailLoginSheet> createState() => _EmailLoginSheetState();
}

class _EmailLoginSheetState extends State<_EmailLoginSheet> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _send(WalletAuthController auth) async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() => _busy = true);
    final ok = await auth.requestEmailLoginCode(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _codeSent = true;
    });
  }

  Future<void> _verify(WalletAuthController auth) async {
    setState(() => _busy = true);
    await auth.verifyEmailLoginCode(email: _emailCtrl.text.trim(), code: _codeCtrl.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (auth.isAuthenticated) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<WalletAuthController>();
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.strokeHi, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text(_codeSent ? 'Enter your code' : 'Sign in with email',
              style: grotesk(size: 19, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            _codeSent
                ? 'We sent a 6-digit code to ${_emailCtrl.text.trim()}'
                : "We'll email you a one-time code — no password.",
            style: grotesk(size: 13, color: AppColors.textTertiary, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (!_codeSent) ...[
            _SheetField(controller: _emailCtrl, hint: 'you@example.com', keyboardType: TextInputType.emailAddress, autofocus: true),
            const SizedBox(height: 14),
            _SheetPrimaryButton(label: 'Send code', busy: _busy, onTap: () => _send(auth)),
          ] else ...[
            _SheetField(controller: _codeCtrl, hint: '6-digit code', keyboardType: TextInputType.number, autofocus: true, letterSpacing: 6),
            const SizedBox(height: 14),
            _SheetPrimaryButton(label: 'Verify & sign in', busy: _busy, onTap: () => _verify(auth)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _busy ? null : () => setState(() { _codeSent = false; _codeCtrl.clear(); }),
              child: Text('← use a different email',
                  textAlign: TextAlign.center, style: mono(size: 12, color: AppColors.textMuted)),
            ),
          ],
          const SizedBox(height: 14),
          Obx(() {
            final err = auth.authError.value;
            if (err == null || err.isEmpty) return const SizedBox.shrink();
            return Text(err,
                textAlign: TextAlign.center,
                style: grotesk(size: 12.5, weight: FontWeight.w500, color: AppColors.danger));
          }),
        ],
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.autofocus = false,
    this.letterSpacing,
  });
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final bool autofocus;
  final double? letterSpacing;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.stroke),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        autofocus: autofocus,
        style: grotesk(size: 15, weight: FontWeight.w500, letterSpacing: letterSpacing ?? 0),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: grotesk(size: 15, color: AppColors.textMuted),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}

class _SheetPrimaryButton extends StatelessWidget {
  const _SheetPrimaryButton({required this.label, required this.busy, required this.onTap});
  final String label;
  final bool busy;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(14)),
        child: busy
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onAccent))
            : Text(label, style: grotesk(size: 15, weight: FontWeight.w600, color: AppColors.onAccent)),
      ),
    );
  }
}

class _OutlinedAuthButton extends StatelessWidget {
  const _OutlinedAuthButton({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: child,
      ),
    );
  }
}

class _WalletButton extends StatelessWidget {
  const _WalletButton({
    required this.onTap,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.borderColor,
    required this.background,
    this.trailing,
  });
  final VoidCallback onTap;
  final Gradient gradient;
  final String title;
  final String subtitle;
  final Color borderColor;
  final Color background;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(9)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: grotesk(size: 15, weight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(subtitle, style: mono(size: 11, weight: FontWeight.w400, color: AppColors.textTertiary)),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _AuthDivider extends StatelessWidget {
  const _AuthDivider({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.08)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(label, style: mono(size: 11, weight: FontWeight.w500, color: AppColors.textDim, letterSpacing: 11 * 0.15)),
          ),
          line,
        ],
      ),
    );
  }
}

class _ConnectingOverlay extends StatelessWidget {
  const _ConnectingOverlay({
    this.waitingForBrowser = false,
    this.onPasteFromClipboard,
  });
  final bool waitingForBrowser;
  final VoidCallback? onPasteFromClipboard;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xFF08080B).withValues(alpha: 0.86),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.accent),
            ),
            const SizedBox(height: 22),
            Text(
              waitingForBrowser ? 'Waiting for browser sign-in' : 'Connecting your account',
              style: grotesk(size: 15, weight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              waitingForBrowser
                  ? 'complete sign-in in your browser…'
                  : 'verifying credentials…',
              style: mono(size: 12, weight: FontWeight.w400, color: AppColors.textTertiary),
            ),
            if (waitingForBrowser && PlatformCapabilities.usesWebLogin && onPasteFromClipboard != null) ...[
              const SizedBox(height: 28),
              Text(
                'Redirect didn\'t work?',
                style: grotesk(size: 13, weight: FontWeight.w500, color: AppColors.textMuted),
              ),
              const SizedBox(height: 10),
              _PasteFromClipboardButton(onTap: onPasteFromClipboard!),
            ],
          ],
        ),
      ),
    );
  }
}

class _PasteTokenSection extends StatefulWidget {
  const _PasteTokenSection();

  @override
  State<_PasteTokenSection> createState() => _PasteTokenSectionState();
}

class _PasteTokenSectionState extends State<_PasteTokenSection> {
  final _controller = TextEditingController();
  var _expanded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard(WalletAuthController auth) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      _controller.text = text;
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<WalletAuthController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _AuthDivider(label: 'OR PASTE TOKEN'),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.content_paste_go_outlined, size: 18, color: AppColors.textTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Paste sign-in token from browser',
                    style: grotesk(size: 14, weight: FontWeight.w500, color: AppColors.textSecondary),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 10),
          Text(
            'Copy the PASETO from the browser sign-in page, then paste here if the app didn\'t open automatically.',
            style: grotesk(size: 12, weight: FontWeight.w400, color: AppColors.textMuted, height: 1.45),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 2,
              style: mono(size: 11, weight: FontWeight.w400, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'PASETO token or erebrusvpn://auth?token=…',
                hintStyle: mono(size: 11, color: AppColors.textDim),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _OutlinedAuthButton(
                  onTap: () => _pasteFromClipboard(auth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.content_paste, size: 16, color: AppColors.textTertiary),
                      const SizedBox(width: 8),
                      Text('Paste', style: grotesk(size: 14, weight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () {
                    final text = _controller.text.trim();
                    if (text.isEmpty) {
                      auth.authError.value = 'Paste a PASETO token first';
                      return;
                    }
                    auth.signInWithPastedCredential(text);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppGradients.brand,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text('Sign in', style: grotesk(size: 14, weight: FontWeight.w600, color: AppColors.onAccent)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PasteFromClipboardButton extends StatelessWidget {
  const _PasteFromClipboardButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.content_paste_go_outlined, size: 16, color: AppColors.accent),
            const SizedBox(width: 8),
            Text('Paste token from clipboard', style: grotesk(size: 13, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}


