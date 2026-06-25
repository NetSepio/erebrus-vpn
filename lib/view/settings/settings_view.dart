import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../platform/platform_capabilities.dart';
import '../../auth/wallet_auth_controller.dart';
import '../../vpn/gateway_config.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';
import 'about_view.dart';
import 'account_sheets.dart';
import 'split_tunnel_sheet.dart';
import '../../vpn/gateway_controller.dart';

/// The settings tab — account, subscription, VPN & security, about, log out.
/// All values are bound to the real controllers; the upgrade CTA is disabled
/// (trial-only for now) per product.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  @override
  void initState() {
    super.initState();
    final auth = Get.find<WalletAuthController>();
    if (auth.isAuthenticated) {
      auth.refreshProfile();
      Get.find<GatewayController>().refreshNodes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<WalletAuthController>();
    final settings = Get.find<AppSettingsController>();
    final vpn = Get.find<VpnController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          // Avoid Material ink handling scroll notifications after tab deactivation.
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
          children: [
            Text('Settings', style: grotesk(size: 24, weight: FontWeight.w600, letterSpacing: -0.48)),
            const SizedBox(height: 18),

            // profile
            Obx(() => _ProfileCard(walletAddress: auth.walletAddress.value, authMethod: auth.authMethod.value)),
            const SizedBox(height: 14),

            // subscription
            _SubscriptionCard(auth: auth),
            const SizedBox(height: 22),

            // account
            const SectionLabel('ACCOUNT'),
            const SizedBox(height: 9),
            Obx(() => _GroupCard(children: [
                  _EmailRow(auth: auth),
                  _RowDivider(),
                  _GroupRow(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Wallet',
                    subtitle: _walletSubtitle(auth.walletAddress.value),
                    subtitleMono: true,
                    trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
                  ),
                  _RowDivider(),
                  Obx(() => _GroupRow(
                    icon: Icons.edit_outlined,
                    title: 'Edit profile',
                    subtitle: auth.profileName.value.isEmpty ? 'Set a display name' : auth.profileName.value,
                    onTap: () => showEditProfileSheet(context, auth),
                    trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
                  )),
                ])),
            const SizedBox(height: 18),

            // vpn & security
            const SectionLabel('VPN & SECURITY'),
            const SizedBox(height: 9),
            Obx(() => _GroupCard(children: [
                  _GroupRow(
                    icon: Icons.shield_outlined,
                    title: 'Default protocol',
                    onTap: () => _pickProtocol(context, settings, vpn),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(settings.defaultProtocol.value.label.toUpperCase(),
                            style: mono(size: 12, weight: FontWeight.w500, color: AppColors.textTertiary)),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
                      ],
                    ),
                  ),
                  _RowDivider(),
                  _GroupRow(
                    icon: Icons.power_settings_new,
                    title: 'Auto-connect',
                    trailing: EreToggle(value: settings.autoConnectOnLaunch.value, onChanged: settings.setAutoConnect),
                  ),
                  _RowDivider(),
                  _GroupRow(
                    icon: Icons.lock_outline,
                    title: 'Kill switch',
                    trailing: EreToggle(value: settings.killSwitchEnabled.value, onChanged: settings.setKillSwitch),
                  ),
                  if (PlatformCapabilities.supportsSplitTunnel) ...[
                    _RowDivider(),
                    Obx(() {
                      final enabled = settings.splitTunnelEnabled.value;
                      final mode = settings.splitTunnelMode.value;
                      final count = settings.splitTunnelActivePackages.length;
                      final subtitle = enabled
                          ? mode.settingsSubtitle(count)
                          : 'Per-app VPN routing';
                      return _GroupRow(
                        icon: Icons.alt_route,
                        title: 'Split tunneling',
                        subtitle: subtitle,
                        onTap: () => showSplitTunnelSheet(context, settings),
                        trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
                      );
                    }),
                  ],
                ])),
            const SizedBox(height: 18),

            // about
            const SectionLabel('ABOUT'),
            const SizedBox(height: 9),
            _GroupCard(children: [
              _GroupRow(
                title: 'Version',
                trailing: const _VersionLabel(),
              ),
              _RowDivider(),
              _GroupRow(
                title: 'Help & support',
                onTap: () => Get.to(() => const AboutView()),
                trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
              ),
            ]),
            const SizedBox(height: 22),

            // log out
            GestureDetector(
              onTap: auth.signOut,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Text('Log out', style: grotesk(size: 14, weight: FontWeight.w600, color: AppColors.danger)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _walletSubtitle(String address) {
    if (address.isEmpty) return 'Not connected';
    return 'Solana · ${_short(address)}';
  }

  static String _short(String a) =>
      a.length < 10 ? a : '${a.substring(0, 4)}…${a.substring(a.length - 4)}';

  void _pickProtocol(BuildContext context, AppSettingsController settings, VpnController vpn) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.raised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ConnectMode.values.map((m) {
            return Obx(() => ListTile(
                  title: Text(m.label, style: grotesk(size: 15, weight: FontWeight.w600)),
                  subtitle: Text(m.blurb, style: grotesk(size: 12.5, weight: FontWeight.w400, color: AppColors.textMuted)),
                  trailing: settings.defaultProtocol.value == m
                      ? const Icon(Icons.check, color: AppColors.accent)
                      : null,
                  onTap: () {
                    settings.setDefaultProtocol(m);
                    vpn.setMode(m);
                    Navigator.pop(context);
                  },
                ));
          }).toList(),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.walletAddress, required this.authMethod});
  final String walletAddress;
  final String authMethod;
  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  bool _copied = false;

  String get _short {
    final a = widget.walletAddress;
    if (a.isEmpty) return 'Not connected';
    return a.length < 10 ? a : '${a.substring(0, 4)}…${a.substring(a.length - 4)}';
  }

  String get _initials {
    final a = widget.walletAddress;
    if (a.length < 2) return 'ER';
    return a.substring(0, 2);
  }

  void _copy() {
    if (widget.walletAddress.isEmpty) return;
    Clipboard.setData(ClipboardData(text: widget.walletAddress));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(14)),
            child: Text(_initials, style: mono(size: 16, weight: FontWeight.w600, color: AppColors.onAccent)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_short, style: grotesk(size: 16, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(widget.authMethod.isEmpty ? 'Solana wallet' : 'Signed in · ${widget.authMethod}',
                    style: mono(size: 12, weight: FontWeight.w400, color: AppColors.textTertiary)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _copy,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
              child: Icon(_copied ? Icons.check : Icons.copy_outlined,
                  size: 16, color: _copied ? AppColors.success : AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.auth});
  final WalletAuthController auth;

  @override
  Widget build(BuildContext context) {
    return Obx(() => _buildCard(context));
  }

  Widget _buildCard(BuildContext context) {
    final ent = auth.entitlement.value;
    final entitled = ent.entitled;
    final source = ent.source;
    final days = ent.daysRemaining;
    final busy = auth.isLoadingEntitlement.value ||
        auth.isStartingTrial.value ||
        auth.isRefreshingNft.value;

    final badge = switch (source) {
      'trial' => 'TRIAL',
      'nft' => 'NFT',
      'rank' => 'RANK',
      'admin' => 'ADMIN',
      _ => entitled ? 'ACTIVE' : 'FREE',
    };
    final title = entitled ? 'Erebrus Pro' : 'Erebrus Free';
    final sub = busy
        ? 'Checking subscription…'
        : entitled
            ? (days != null ? '$days of $kTrialPeriodDays days remaining' : 'Active')
            : ent.trialConsumed
                ? 'Trial ended — verify your gating NFT or renew on erebrus.io'
                : 'Start a free $kTrialPeriodDays-day trial to connect';
    final progress =
        entitled && days != null ? (days / kTrialPeriodDays).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent.withValues(alpha: 0.14), AppColors.accent.withValues(alpha: 0.04)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: grotesk(size: 15, weight: FontWeight.w600)),
              const Spacer(),
              MonoChip(label: badge, color: AppColors.accent, background: AppColors.accent.withValues(alpha: 0.16)),
            ],
          ),
          const SizedBox(height: 9),
          Text(sub, style: mono(size: 12, weight: FontWeight.w400, color: AppColors.textSecondary)),
          if (entitled) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
              ),
            ),
            const SizedBox(height: 14),
            _DisabledButton(label: 'UPGRADE · COMING SOON'),
          ] else if (!ent.trialConsumed) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: busy ? null : auth.startFreeTrial,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(11)),
                child: Text(busy ? 'STARTING…' : 'START FREE TRIAL',
                    style: mono(size: 13, weight: FontWeight.w600, color: AppColors.onAccent, letterSpacing: 13 * 0.05)),
              ),
            ),
          ] else if (ent.nftGatingEnabled) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: busy ? null : auth.refreshNftEntitlement,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
                ),
                child: Text(busy ? 'CHECKING…' : 'VERIFY GATING NFT',
                    style: mono(size: 13, weight: FontWeight.w600, color: AppColors.accent, letterSpacing: 13 * 0.05)),
              ),
            ),
          ],
          if (auth.entitlementError.value != null && auth.entitlementError.value!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(auth.entitlementError.value!, style: grotesk(size: 12, weight: FontWeight.w400, color: AppColors.danger)),
          ],
        ],
      ),
    );
  }
}

class _DisabledButton extends StatelessWidget {
  const _DisabledButton({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(11)),
      child: Text(label, style: mono(size: 13, weight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 13 * 0.05)),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(children: children),
    );
  }
}

class _RowDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(height: 1, color: AppColors.strokeSoft);
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    this.icon,
    required this.title,
    this.subtitle,
    this.subtitleMono = false,
    this.trailing,
    this.onTap,
  });
  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool subtitleMono;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        child: Row(
          children: [
            if (icon != null) ...[Icon(icon, size: 20, color: AppColors.textSecondary), const SizedBox(width: 13)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: grotesk(size: 14.5, weight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: subtitleMono
                            ? mono(size: 11.5, weight: FontWeight.w400, color: AppColors.textMuted)
                            : grotesk(size: 11.5, weight: FontWeight.w400, color: AppColors.textMuted)),
                  ],
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

class _EmailRow extends StatelessWidget {
  const _EmailRow({required this.auth});
  final WalletAuthController auth;
  @override
  Widget build(BuildContext context) {
    return Obx(() => _row(context));
  }

  Widget _row(BuildContext context) {
    if (!auth.isAuthenticated) {
      return const _GroupRow(
        icon: Icons.mail_outline,
        title: 'Email',
        subtitle: 'Sign in to link a recovery email',
      );
    }
    final linked = auth.profileEmailVerified.value;
    final email = auth.profileEmail.value;
    return _GroupRow(
      icon: Icons.mail_outline,
      title: 'Email',
      subtitle: linked && email.isNotEmpty ? email : 'Add a recovery email (OTP)',
      onTap: linked ? null : () => showEmailLinkSheet(context, auth),
      trailing: GestureDetector(
        onTap: linked ? null : () => showEmailLinkSheet(context, auth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: (linked ? AppColors.success : AppColors.accent).withValues(alpha: linked ? 0.14 : 0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(linked ? 'LINKED' : 'LINK',
              style: mono(size: 11, weight: FontWeight.w500, color: linked ? AppColors.success : AppColors.accent, letterSpacing: 11 * 0.06)),
        ),
      ),
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (_, snap) {
        final v = snap.data?.version ?? '1.0.0';
        return Text('$v · agentic', style: mono(size: 12, weight: FontWeight.w400, color: AppColors.textMuted));
      },
    );
  }
}
