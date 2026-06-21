import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';

/// Premium account screen: identity, entitlement (trial / NFT), org, settings.
/// Values are passed in so this stays presentation-only; wire to the gateway
/// (`/account/profile`, `/subscriptions`, `/orgs`) at the call site.
class ProfileView extends StatelessWidget {
  const ProfileView({
    super.key,
    this.walletAddress = '',
    this.planLabel = 'Free',
    this.entitlementSource, // 'trial' | 'nft' | null
    this.daysLeft,
    this.orgCount = 0,
    this.onManagePlan,
    this.unlockLabel = 'Unlock access',
    this.isLoadingEntitlement = false,
    this.isStartingTrial = false,
    this.entitlementError,
    this.onOpenOrgs,
    this.onOpenSettings,
    this.onSignOut,
    this.signInLabel = 'Sign out',
    this.authError,
  });

  final String walletAddress;
  final String planLabel;
  final String? entitlementSource;
  final int? daysLeft;
  final int orgCount;
  final VoidCallback? onManagePlan;
  final String unlockLabel;
  final bool isLoadingEntitlement;
  final bool isStartingTrial;
  final String? entitlementError;
  final VoidCallback? onOpenOrgs;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onSignOut;
  final String signInLabel;
  final String? authError;

  String get _shortWallet {
    if (walletAddress.length < 10) return walletAddress.isEmpty ? 'Not connected' : walletAddress;
    return '${walletAddress.substring(0, 6)}…${walletAddress.substring(walletAddress.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.xxl),
        children: [
          _Header(shortWallet: _shortWallet),
          if (authError != null && authError!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            _AuthError(message: authError!),
          ],
          const SizedBox(height: AppSpace.xl),
          _EntitlementCard(
            plan: planLabel,
            source: entitlementSource,
            daysLeft: daysLeft,
            onManage: onManagePlan,
            unlockLabel: unlockLabel,
            isLoading: isLoadingEntitlement,
            isStartingTrial: isStartingTrial,
            entitlementError: entitlementError,
          ),
          const SizedBox(height: AppSpace.lg),
          const SectionLabel('Workspace'),
          const SizedBox(height: AppSpace.md),
          _NavRow(icon: Icons.workspaces_outline, title: 'Organizations',
              subtitle: orgCount == 0 ? 'Create a team workspace' : '$orgCount workspace${orgCount == 1 ? "" : "s"}',
              onTap: onOpenOrgs),
          const SizedBox(height: AppSpace.lg),
          const SectionLabel('Preferences'),
          const SizedBox(height: AppSpace.md),
          _NavRow(icon: Icons.tune, title: 'Settings', subtitle: 'Protocol, kill switch, auto-connect', onTap: onOpenSettings),
          const SizedBox(height: AppSpace.xl),
          GradientButton(
            label: signInLabel,
            icon: walletAddress.isEmpty ? Icons.account_balance_wallet_outlined : Icons.logout,
            gradient: const LinearGradient(colors: [AppColors.surfaceHi, AppColors.surface]),
            onPressed: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.shortWallet});
  final String shortWallet;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 60,
          width: 60,
          decoration: const BoxDecoration(gradient: AppGradients.aurora, shape: BoxShape.circle),
          child: const Icon(Icons.person, color: Colors.white, size: 30),
        ),
        const SizedBox(width: AppSpace.lg),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(shortWallet, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.textPrimary)),
          ],
        ),
      ],
    );
  }
}

class _AuthError extends StatelessWidget {
  const _AuthError({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
    );
  }
}

class _EntitlementCard extends StatelessWidget {
  const _EntitlementCard({
    required this.plan,
    this.source,
    this.daysLeft,
    this.onManage,
    this.unlockLabel = 'Unlock access',
    this.isLoading = false,
    this.isStartingTrial = false,
    this.entitlementError,
  });
  final String plan;
  final String? source;
  final int? daysLeft;
  final VoidCallback? onManage;
  final String unlockLabel;
  final bool isLoading;
  final bool isStartingTrial;
  final String? entitlementError;

  @override
  Widget build(BuildContext context) {
    final entitled = source != null;
    final badge = switch (source) {
      'trial' => 'Trial',
      'nft' => 'NFT access',
      'crypto' => 'Subscriber',
      'admin' => 'Admin',
      _ => entitled ? 'Active' : 'Inactive',
    };
    final busy = isLoading || isStartingTrial;
    final subtitle = isLoading
        ? 'Checking subscription…'
        : entitled
            ? (daysLeft != null ? '$daysLeft days remaining' : 'Active')
            : 'Start a free 14-day trial to connect';
    final actionLabel = entitled ? 'Manage access' : unlockLabel;

    return GlassCard(
      borderColor: entitled ? AppColors.connected.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShaderMask(
                shaderCallback: (r) => AppGradients.protected.createShader(r),
                child: Text('Erebrus $plan',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
              ),
              const Spacer(),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (entitled ? AppColors.connected : AppColors.textMuted).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(badge,
                      style: TextStyle(
                          color: entitled ? AppColors.connected : AppColors.textMuted,
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          if (entitlementError != null && entitlementError!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(entitlementError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          if (!entitled) ...[
            const SizedBox(height: AppSpace.lg),
            GradientButton(
              label: actionLabel,
              onPressed: busy ? null : onManage,
              enabled: !busy && onManage != null,
            ),
          ],
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.title, required this.subtitle, this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
