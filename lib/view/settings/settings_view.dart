import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';
import 'about_view.dart';

/// Premium settings screen with persisted preferences.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<AppSettingsController>();
    final vpn = Get.find<VpnController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Obx(
        () => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.xxl),
          children: [
            const SectionLabel('Connection'),
            const SizedBox(height: AppSpace.md),
            GlassCard(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Column(
                children: [
                  _SettingRow(
                    icon: Icons.shield_moon_outlined,
                    title: 'Default protocol',
                    trailing: Text(
                      settings.defaultProtocol.value.label,
                      style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700),
                    ),
                    onTap: () => _pickProtocol(context, settings, vpn),
                  ),
                  const _Divider(),
                  _SwitchRow(
                    icon: Icons.flash_on_outlined,
                    title: 'Auto-connect on launch',
                    subtitle: 'Connect after sign-in when entitled',
                    value: settings.autoConnectOnLaunch.value,
                    onChanged: settings.setAutoConnect,
                  ),
                  const _Divider(),
                  _SwitchRow(
                    icon: Icons.block_outlined,
                    title: 'Kill switch',
                    subtitle: settings.killSwitchEnabled.value
                        ? 'Blocks traffic if the tunnel drops'
                        : 'Traffic may leak if the tunnel drops',
                    value: settings.killSwitchEnabled.value,
                    onChanged: settings.setKillSwitch,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            const SectionLabel('Privacy'),
            const SizedBox(height: AppSpace.md),
            GlassCard(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: _SwitchRow(
                icon: Icons.insights_outlined,
                title: 'Anonymous diagnostics',
                subtitle: settings.anonymousDiagnostics.value
                    ? (settings.diagnosticsStatus.value ?? 'Mock health beacons enabled')
                    : 'Off by default — no logs sent',
                value: settings.anonymousDiagnostics.value,
                onChanged: settings.setAnonymousDiagnostics,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            const SectionLabel('About'),
            const SizedBox(height: AppSpace.md),
            GlassCard(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: _SettingRow(
                icon: Icons.info_outline,
                title: 'About Erebrus',
                subtitle: 'Version, ethos, privacy & terms',
                onTap: () => Get.to(() => const AboutView()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickProtocol(BuildContext context, AppSettingsController settings, VpnController vpn) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ConnectMode.values.map((m) {
            return ListTile(
              title: Text(
                m.label,
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(m.blurb, style: const TextStyle(color: AppColors.textMuted)),
              trailing: settings.defaultProtocol.value == m
                  ? const Icon(Icons.check, color: AppColors.connected)
                  : null,
              onTap: () {
                settings.setDefaultProtocol(m);
                vpn.setMode(m);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: AppColors.textMuted) : null),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
      trailing: Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.connected),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: AppColors.stroke, indent: AppSpace.lg, endIndent: AppSpace.lg);
}