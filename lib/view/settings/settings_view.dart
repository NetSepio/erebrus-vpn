import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../platform/platform_capabilities.dart';
import '../../auth/gateway_auth_client.dart';
import '../../auth/wallet_auth_controller.dart';
import '../../vpn/gateway_config.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';
import 'about_view.dart';
import 'account_sheets.dart';
import 'organization_sheets.dart';
import '../auth/login_view.dart';
import 'split_tunnel_sheet.dart';
import '../../vpn/gateway_controller.dart';

String _formatChainLabel(String chain) {
  if (chain.isEmpty) return 'Solana';
  switch (chain.toLowerCase()) {
    case 'solana':
      return 'Solana';
    case 'ethereum':
      return 'Ethereum';
    default:
      return chain[0].toUpperCase() + chain.substring(1).toLowerCase();
  }
}

String _formatMemberSinceLabel(DateTime? createdAt) {
  if (createdAt == null) return '—';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[createdAt.month - 1]} ${createdAt.year}';
}

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
      auth.refreshReferrals();
      Get.find<GatewayController>().refreshNodes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<WalletAuthController>();
    final settings = Get.find<AppSettingsController>();
    final vpn = Get.find<VpnController>();
    final gateway = Get.isRegistered<GatewayController>()
        ? Get.find<GatewayController>()
        : null;

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

            Obx(() => auth.isAuthenticated
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // profile
                      Obx(() => _ProfileCard(
                            walletAddress: auth.walletAddress.value,
                            authMethod: auth.authMethod.value,
                            displayName: auth.profileName.value,
                            chain: auth.profileChain.value,
                            email: auth.profileEmail.value,
                          )),
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
                              icon: Icons.edit_outlined,
                              title: 'Display name',
                              subtitle: auth.profileName.value.isEmpty ? 'Set a display name' : auth.profileName.value,
                              onTap: () => showEditProfileSheet(context, auth),
                              trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
                            ),
                            _RowDivider(),
                            _GroupRow(
                              icon: Icons.calendar_today_outlined,
                              title: 'Member since',
                              subtitle: _formatMemberSinceLabel(auth.profileCreatedAt.value),
                            ),
                            _RowDivider(),
                            _GroupRow(
                              icon: Icons.delete_outline,
                              title: 'Request account deletion',
                              titleColor: AppColors.danger,
                              iconColor: AppColors.danger,
                              onTap: () => showDeleteAccountSheet(context, auth),
                            ),
                          ])),
                      const SizedBox(height: 18),

                      // referrals — mirrors the webapp profile "Invite friends" card
                      _ReferralSection(auth: auth),

                      // organizations
                      const SectionLabel('ORGANIZATIONS'),
                      const SizedBox(height: 9),
                      Obx(() => _GroupCard(children: [
                            _GroupRow(
                              icon: Icons.business_outlined,
                              title: 'Organizations',
                              subtitle: 'Manage workspaces and invites',
                              onTap: () => showOrganizationsSheet(context, auth),
                              trailing: (gateway?.orgs.isNotEmpty ?? false)
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.accent.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: Text(
                                        '${gateway?.orgs.length ?? 0}',
                                        style: mono(size: 11, weight: FontWeight.w600, color: AppColors.accent),
                                      ),
                                    )
                                  : const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
                            ),
                            if (auth.accountOrgInvites.isNotEmpty) ...[
                              _RowDivider(),
                              _GroupRow(
                                icon: Icons.mail_outline,
                                title: 'Pending invites',
                                subtitle: '${auth.accountOrgInvites.length} invitation${auth.accountOrgInvites.length == 1 ? '' : 's'}',
                                onTap: () => showOrganizationsSheet(context, auth),
                                trailing: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ])),
                      const SizedBox(height: 18),
                    ],
                  )
                : const _GuestSignInCard()),
            const SizedBox(height: 18),

            // vpn & security
            const SectionLabel('VPN & SECURITY'),
            const SizedBox(height: 9),
            Obx(() => _GroupCard(children: [
                  _GroupRow(
                    icon: Icons.shield_outlined,
                    title: 'Default protocol',
                    subtitle: settings.defaultProtocol.value.blurb,
                    onTap: () => _pickProtocol(context, settings, vpn),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(settings.defaultProtocol.value.label.toUpperCase(),
                            style: mono(size: 12, weight: FontWeight.w500, color: AppColors.textTertiary)),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                  _RowDivider(),
                  _GroupRow(
                    icon: Icons.power_settings_new,
                    title: 'Auto-connect',
                    subtitle: 'Connect to your last server when the app opens',
                    trailing: EreToggle(value: settings.autoConnectOnLaunch.value, onChanged: settings.setAutoConnect),
                  ),
                  _RowDivider(),
                  _GroupRow(
                    icon: Icons.lock_outline,
                    title: 'Kill switch',
                    subtitle: 'Block internet if the VPN drops unexpectedly',
                    trailing: EreToggle(value: settings.killSwitchEnabled.value, onChanged: settings.setKillSwitch),
                  ),
                  _RowDivider(),
                  Obx(() => _GroupRow(
                    icon: Icons.dns_outlined,
                    title: 'DNS resolver',
                    subtitle: settings.dnsResolverLabel,
                    onTap: () => _pickDnsResolver(context, settings),
                    trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
                  )),
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
                        trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
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
                title: 'About',
                onTap: () => Get.to(() => const AboutView()),
                trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
              ),
            ]),
            const SizedBox(height: 22),

            // log out / sign in
            Obx(() => auth.isAuthenticated
                ? GestureDetector(
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
                  )
                : GestureDetector(
                    onTap: () => Get.to(() => const LoginView()),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Text('SIGN IN / REGISTER',
                          style: mono(size: 13, weight: FontWeight.w600, color: AppColors.onAccent, letterSpacing: 13 * 0.05)),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

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

  void _pickDnsResolver(BuildContext context, AppSettingsController settings) {
    final options = const {
      'system': 'System DNS',
      'cloudflare': 'Cloudflare DoH',
      'quad9': 'Quad9 DoH',
      'adguard': 'AdGuard DoH',
      'custom': 'Custom',
    };
    final customCtrl = TextEditingController();
    var selected = settings.dnsResolver.value;
    if (!options.containsKey(selected) && !selected.startsWith('https://')) {
      selected = 'system';
    }
    var customUrl = '';
    if (selected.startsWith('https://')) {
      customUrl = selected;
      selected = 'custom';
      customCtrl.text = customUrl;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.raised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DNS resolver', style: grotesk(size: 18, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Fallback used when system DNS fails', style: grotesk(size: 12, weight: FontWeight.w400, color: AppColors.textMuted)),
                const SizedBox(height: 12),
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (v) {
                    if (v == null) return;
                    setSheetState(() => selected = v);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: options.entries
                        .map((e) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Radio<String>(
                                value: e.key,
                                activeColor: AppColors.accent,
                              ),
                              title: Text(e.value, style: grotesk(size: 14.5, weight: FontWeight.w500)),
                              onTap: () => setSheetState(() => selected = e.key),
                            ))
                        .toList(),
                  ),
                ),
                if (selected == 'custom') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: customCtrl,
                    autocorrect: false,
                    onChanged: (v) => customUrl = v.trim(),
                    style: mono(size: 13, weight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'https://doh.example.com/dns-query',
                      hintStyle: mono(size: 13, weight: FontWeight.w400, color: AppColors.textMuted),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.strokeSoft)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    final value = selected == 'custom' ? customUrl : selected;
                    if (selected == 'custom' && !value.startsWith('https://')) {
                      Get.snackbar('Invalid URL', 'Custom resolver must be an https:// URL', snackPosition: SnackPosition.BOTTOM);
                      return;
                    }
                    settings.setDnsResolver(value);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                    child: Text('SAVE', style: mono(size: 13, weight: FontWeight.w600, color: AppColors.onAccent, letterSpacing: 13 * 0.05)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuestSignInCard extends StatelessWidget {
  const _GuestSignInCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
          Text('Unlock the full network', style: grotesk(size: 15, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Sign in or register to browse nodes, manage subscriptions, and earn rewards.',
              style: grotesk(size: 12.5, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.4)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => Get.to(() => const LoginView()),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
              child: Text('SIGN IN / REGISTER',
                  style: mono(size: 13, weight: FontWeight.w600, color: AppColors.onAccent, letterSpacing: 13 * 0.05)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({
    required this.walletAddress,
    required this.authMethod,
    required this.displayName,
    required this.chain,
    this.email = '',
  });
  final String walletAddress;
  final String authMethod;
  final String displayName;
  final String chain;
  final String email;
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
    final name = widget.displayName.trim();
    if (name.isNotEmpty) {
      final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
      }
      return name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
    }
    final a = widget.walletAddress.isNotEmpty ? widget.walletAddress : widget.email.trim();
    if (a.length < 2) return 'ER';
    return a.substring(0, 2).toUpperCase();
  }

  // Name > wallet > email — identity-login users shouldn't read "Not connected".
  String get _title {
    final name = widget.displayName.trim();
    if (name.isNotEmpty) return name;
    if (widget.walletAddress.isNotEmpty) return _short;
    final email = widget.email.trim();
    if (email.isNotEmpty) return email;
    return 'Erebrus account';
  }

  String get _subtitle {
    final name = widget.displayName.trim();
    if (name.isNotEmpty && widget.walletAddress.isNotEmpty) {
      return '${_formatChainLabel(widget.chain)} · $_short';
    }
    return widget.authMethod.isEmpty ? 'Solana wallet' : 'Signed in · ${widget.authMethod}';
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
                Text(_title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: grotesk(size: 16, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(_subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(size: 12, weight: FontWeight.w400, color: AppColors.textTertiary)),
              ],
            ),
          ),
          if (widget.walletAddress.isNotEmpty)
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
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        child: Row(
          children: [
            if (icon != null) ...[Icon(icon, size: 20, color: iconColor ?? AppColors.textSecondary), const SizedBox(width: 13)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: grotesk(size: 14.5, weight: FontWeight.w500, color: titleColor ?? AppColors.textPrimary)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: grotesk(size: 11.5, weight: FontWeight.w400, color: AppColors.textMuted)),
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

/// "Invite friends, earn XP" — the referral card from the webapp profile page.
/// Hidden until the summary loads (the gateway allocates the code lazily).
class _ReferralSection extends StatefulWidget {
  const _ReferralSection({required this.auth});
  final WalletAuthController auth;
  @override
  State<_ReferralSection> createState() => _ReferralSectionState();
}

class _ReferralSectionState extends State<_ReferralSection> {
  final _codeCtrl = TextEditingController();
  bool _copied = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _redeem() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty || widget.auth.isRedeemingReferral.value) return;
    FocusScope.of(context).unfocus();
    try {
      await widget.auth.redeemReferralCode(code);
      _codeCtrl.clear();
      Get.snackbar('Invite code applied', 'You both earn XP',
          snackPosition: SnackPosition.BOTTOM);
    } on AuthException catch (e) {
      Get.snackbar('Invite code', e.message, snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final sum = widget.auth.referral.value;
      if (sum == null || sum.code.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('REFERRALS'),
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accent.withValues(alpha: 0.10),
                  AppColors.accent.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invite friends, earn XP',
                    style: grotesk(size: 15, weight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  'Share your code — when a friend joins and starts their trial, '
                  'you both earn XP. Claim XP here for plan upgrades and to extend your free trial.',
                  style: grotesk(
                      size: 12, weight: FontWeight.w400, color: AppColors.textSecondary, height: 1.45),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(sum.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(
                                size: 15,
                                weight: FontWeight.w600,
                                color: AppColors.accentHi,
                                letterSpacing: 15 * 0.12)),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _copy(sum.code),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: (_copied ? AppColors.success : AppColors.accent)
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_copied ? 'COPIED' : 'COPY',
                              style: mono(
                                  size: 11,
                                  weight: FontWeight.w500,
                                  color: _copied ? AppColors.success : AppColors.accent,
                                  letterSpacing: 11 * 0.06)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _ReferralStat(value: sum.referredCount, label: 'invited'),
                    const SizedBox(width: 28),
                    _ReferralStat(value: sum.qualifiedCount, label: 'qualified'),
                  ],
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: AppColors.strokeSoft),
                const SizedBox(height: 12),
                if (sum.referredBy.isNotEmpty)
                  Text('Invited by ${sum.referredBy}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(size: 11, weight: FontWeight.w400, color: AppColors.textTertiary))
                else ...[
                  Text('Were you invited? Enter the code — you both earn XP.',
                      style: grotesk(
                          size: 12, weight: FontWeight.w400, color: AppColors.textSecondary)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeCtrl,
                          textCapitalization: TextCapitalization.characters,
                          autocorrect: false,
                          enableSuggestions: false,
                          onSubmitted: (_) => _redeem(),
                          style: mono(size: 13, weight: FontWeight.w500, letterSpacing: 13 * 0.1),
                          decoration: const InputDecoration(hintText: 'Invite code', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: widget.auth.isRedeemingReferral.value ? null : _redeem,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                              widget.auth.isRedeemingReferral.value ? 'APPLYING…' : 'APPLY',
                              style: mono(
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: AppColors.onAccent,
                                  letterSpacing: 12 * 0.05)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
      );
    });
  }
}

class _ReferralStat extends StatelessWidget {
  const _ReferralStat({required this.value, required this.label});
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: grotesk(size: 18, weight: FontWeight.w700)),
        const SizedBox(height: 1),
        Text(label, style: grotesk(size: 11, weight: FontWeight.w400, color: AppColors.textMuted)),
      ],
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
