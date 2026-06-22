import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/wallet_auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';

/// Branded sign-in launcher (RenownKit / Reown AppKit + Solana Mobile Wallet
/// Adapter). Each method opens the real auth flow; the provider is chosen in the
/// wallet/social modal, and a full-screen connecting overlay shows while the
/// gateway verifies the signed challenge. On success the auth session updates
/// and the app router routes to the dVPN tab.
class LoginView extends StatelessWidget {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<WalletAuthController>();
    // On Solana Mobile (Seeker / Saga) sign-in is wallet-only via Seed Vault /
    // Mobile Wallet Adapter — no Reown, email, or social providers.
    final solanaOnly = auth.isSolanaMobileDevice.value;

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
                    // header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 26, 0, 30),
                      child: Column(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: AppGradients.brand,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                    color: AppColors.accent.withValues(alpha: 0.6),
                                    blurRadius: 30,
                                    spreadRadius: -8,
                                    offset: const Offset(0, 12)),
                              ],
                            ),
                            child: const Center(child: BrandDiamond(size: 18, color: AppColors.onAccent, radius: 3)),
                          ),
                          const SizedBox(height: 18),
                          Text('Welcome to Erebrus',
                              textAlign: TextAlign.center,
                              style: grotesk(size: 26, weight: FontWeight.w600, letterSpacing: -0.52)),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 260,
                            child: Text(
                                solanaOnly
                                    ? 'Sign in with your Solana wallet to spin up your private internet.'
                                    : 'Sign in to spin up your private internet.',
                                textAlign: TextAlign.center,
                                style: grotesk(size: 14.5, weight: FontWeight.w400, color: AppColors.textTertiary, height: 1.4)),
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
                    ] else ...[
                      // email
                      _OutlinedAuthButton(
                        onTap: () => _signIn(auth),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.mail_outline, size: 20, color: AppColors.accent),
                            const SizedBox(width: 11),
                            Text('Continue with Email', style: grotesk(size: 15, weight: FontWeight.w600)),
                          ],
                        ),
                      ),

                      const _AuthDivider(label: 'OR CONTINUE WITH'),

                      // social row
                      Row(
                        children: [
                          Expanded(
                            child: _SocialButton(
                              onTap: () => _signIn(auth),
                              child: Text('G', style: mono(size: 19, weight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: 0)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SocialButton(
                              onTap: () => _signIn(auth),
                              child: const Icon(Icons.apple, size: 24, color: AppColors.textPrimary),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SocialButton(
                              onTap: () => _signIn(auth),
                              child: const _XMark(size: 18),
                            ),
                          ),
                        ],
                      ),

                      const _AuthDivider(label: 'CONNECT A WALLET'),

                      // Solana (primary)
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

                      // Ethereum (secondary)
                      _WalletButton(
                        onTap: () => _signIn(auth),
                        gradient: AppGradients.ethereum,
                        title: 'Ethereum',
                        subtitle: 'MetaMask · WalletConnect',
                        borderColor: Colors.white.withValues(alpha: 0.1),
                        background: const Color(0xFF131318),
                      ),
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
                if (!auth.isAuthenticating.value) return const SizedBox.shrink();
                return const _ConnectingOverlay();
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

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
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
  const _ConnectingOverlay();
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
            Text('Connecting your account', style: grotesk(size: 15, weight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text('verifying credentials…', style: mono(size: 12, weight: FontWeight.w400, color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }
}

/// The X (formerly Twitter) wordmark glyph, drawn as two crossing strokes.
class _XMark extends StatelessWidget {
  const _XMark({this.size = 18});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size), painter: _XPainter());
}

class _XPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.textPrimary
      ..strokeWidth = size.width * 0.13
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final inset = size.width * 0.12;
    canvas.drawLine(Offset(inset, inset), Offset(size.width - inset, size.height - inset), p);
    canvas.drawLine(Offset(size.width - inset, inset), Offset(inset, size.height - inset), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
