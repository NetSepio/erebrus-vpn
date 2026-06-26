import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../platform/platform_capabilities.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../layout/desktop_layout.dart';
import 'privacy_view.dart';
import 'terms_view.dart';

/// NetSepio ethos, Erebrus capabilities, and legal links.
class AboutView extends StatelessWidget {
  const AboutView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Erebrus'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = PlatformCapabilities.isDesktop
              ? DesktopLayout.contentMaxWidth(windowWidth: constraints.maxWidth)
              : constraints.maxWidth;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.xxl),
        children: [
          const Center(
            child: BrandLogo(size: 72, radius: 18, showShadow: true),
          ),
          const SizedBox(height: AppSpace.lg),
          Center(
            child: Text(
              'Erebrus VPN',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text('by NetSepio', style: TextStyle(color: AppColors.textMuted)),
          ),
          const SizedBox(height: AppSpace.xl),
          const SectionLabel('Our ethos'),
          const SizedBox(height: AppSpace.md),
          GlassCard(
            child: Text(
              'NetSepio builds privacy infrastructure for a decentralized web. '
              'We believe connectivity should be sovereign: you choose where your '
              'traffic exits, who provisions your keys, and what data leaves your device.\n\n'
              'Erebrus is the client layer of that vision — a VPN that speaks to '
              'NetSepio gateways and community-operated nodes, not a closed pool of '
              'rented servers.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          const SectionLabel('What Erebrus can do'),
          const SizedBox(height: AppSpace.md),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _Bullet('Connect over WireGuard or Stealth (sing-box) through NetSepio gateways'),
                _Bullet('Provision credentials per device and reuse them on reconnect'),
                _Bullet('Browse community and premium nodes with live health signals'),
                _Bullet('Authenticate with wallet, email, or Seeker (Solana Mobile)'),
                _Bullet('Run on Android, iOS, macOS, Windows, and Linux from one codebase'),
                _Bullet('In-app browser routes through the tunnel when connected'),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          const SectionLabel('Legal'),
          const SizedBox(height: AppSpace.md),
          GlassCard(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Column(
              children: [
                _LegalRow(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  subtitle: 'What we collect and what we never log',
                  onTap: () => Get.to(() => const PrivacyView()),
                ),
                const _Divider(),
                _LegalRow(
                  icon: Icons.description_outlined,
                  title: 'Terms of Use',
                  subtitle: 'Acceptable use, disclaimers, and beta notice',
                  onTap: () => Get.to(() => const TermsView()),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          const Center(
            child: Text(
              'Erebrus © 2026 NetSepio LLC. All rights reserved.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
        ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  const _LegalRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: AppColors.stroke, indent: AppSpace.lg, endIndent: AppSpace.lg);
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppColors.cyan, fontSize: 14)),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}