import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';

/// Premium settings screen.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool _autoConnect = false;
  bool _killSwitch = true;
  bool _telemetry = false;

  @override
  Widget build(BuildContext context) {
    final c = Get.isRegistered<VpnController>() ? Get.find<VpnController>() : Get.put(VpnController());

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
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
                  trailing: Obx(() => Text(c.mode.value.label,
                      style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700))),
                  onTap: () => _pickProtocol(context, c),
                ),
                const _Divider(),
                _SwitchRow(
                  icon: Icons.flash_on_outlined,
                  title: 'Auto-connect on launch',
                  value: _autoConnect,
                  onChanged: (v) => setState(() => _autoConnect = v),
                ),
                const _Divider(),
                _SwitchRow(
                  icon: Icons.block_outlined,
                  title: 'Kill switch',
                  subtitle: 'Block traffic if the tunnel drops',
                  value: _killSwitch,
                  onChanged: (v) => setState(() => _killSwitch = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          const SectionLabel('Privacy'),
          const SizedBox(height: AppSpace.md),
          GlassCard(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Column(
              children: [
                _SwitchRow(
                  icon: Icons.insights_outlined,
                  title: 'Anonymous diagnostics',
                  subtitle: 'Off by default — we keep no logs',
                  value: _telemetry,
                  onChanged: (v) => setState(() => _telemetry = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          const SectionLabel('About'),
          const SizedBox(height: AppSpace.md),
          GlassCard(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Column(
              children: const [
                _SettingRow(icon: Icons.description_outlined, title: 'Terms & privacy'),
                _Divider(),
                _SettingRow(icon: Icons.info_outline, title: 'Version', trailing: Text('2.0.0', style: TextStyle(color: AppColors.textMuted))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _pickProtocol(BuildContext context, VpnController c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ConnectMode.values.map((m) {
            return ListTile(
              title: Text(m.label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text(m.blurb, style: const TextStyle(color: AppColors.textMuted)),
              trailing: c.mode.value == m ? const Icon(Icons.check, color: AppColors.connected) : null,
              onTap: () {
                c.setMode(m);
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
  const _SettingRow({required this.icon, required this.title, this.trailing, this.onTap});
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: AppColors.textMuted) : null),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.icon, required this.title, this.subtitle, required this.value, required this.onChanged});
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
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
