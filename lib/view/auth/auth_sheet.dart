import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';

/// Login options: Solana Mobile (Seeker/Saga), Reown wallets, and social via Reown.
class AuthSheet extends StatelessWidget {
  const AuthSheet({
    super.key,
    required this.showSolanaMobile,
    required this.onSolanaMobile,
    required this.onReown,
    this.busy = false,
  });

  final bool showSolanaMobile;
  final VoidCallback? onSolanaMobile;
  final VoidCallback? onReown;
  final bool busy;

  static Future<void> show(
    BuildContext context, {
    required bool showSolanaMobile,
    required VoidCallback? onSolanaMobile,
    required VoidCallback? onReown,
    bool busy = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => AuthSheet(
        showSolanaMobile: showSolanaMobile,
        onSolanaMobile: onSolanaMobile,
        onReown: onReown,
        busy: busy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sign in to Erebrus', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Connect a Solana wallet to provision VPN access and manage your trial.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpace.xl),
            if (showSolanaMobile) ...[
              GradientButton(
                label: busy ? 'Opening Seed Vault…' : 'Solana Mobile (Seeker / Saga)',
                icon: Icons.phone_android,
                onPressed: busy ? null : onSolanaMobile,
                enabled: !busy && onSolanaMobile != null,
              ),
              const SizedBox(height: AppSpace.md),
            ],
            GradientButton(
              label: busy ? 'Opening…' : 'Wallet or social login',
              icon: Icons.account_balance_wallet_outlined,
              gradient: const LinearGradient(colors: [AppColors.surfaceHi, AppColors.surface]),
              onPressed: busy ? null : onReown,
              enabled: !busy && onReown != null,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              'Google, Apple, email, and 300+ wallets via Reown',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}