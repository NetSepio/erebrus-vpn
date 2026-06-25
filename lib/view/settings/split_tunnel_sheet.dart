import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../platform/android_split_tunnel.dart';
import '../../settings/app_settings_controller.dart';
import '../../settings/split_tunnel_config.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../../vpn/vpn_controller.dart';

Future<void> showSplitTunnelSheet(BuildContext context, AppSettingsController settings) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => _SplitTunnelSheet(settings: settings),
  );
}

class _SplitTunnelSheet extends StatefulWidget {
  const _SplitTunnelSheet({required this.settings});

  final AppSettingsController settings;

  @override
  State<_SplitTunnelSheet> createState() => _SplitTunnelSheetState();
}

class _SplitTunnelSheetState extends State<_SplitTunnelSheet> {
  final _searchCtrl = TextEditingController();
  var _query = '';
  var _loading = true;
  List<InstalledApp> _apps = const [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
    _loadApps();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    final apps = await AndroidSplitTunnel.listApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  void _notifyReconnectIfNeeded() {
    if (!Get.isRegistered<VpnController>()) return;
    final vpn = Get.find<VpnController>();
    if (vpn.isConnected || vpn.isBusy) {
      Get.snackbar(
        'Reconnect to apply',
        'Disconnect and connect again for split tunnel changes to take effect',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
      );
    }
  }

  List<InstalledApp> get _filtered {
    if (_query.isEmpty) return _apps;
    return _apps
        .where((a) => a.label.toLowerCase().contains(_query) || a.packageName.toLowerCase().contains(_query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.84;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 18, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Split tunneling', style: grotesk(size: 18, weight: FontWeight.w600))),
                Obx(() => EreToggle(
                      value: widget.settings.splitTunnelEnabled.value,
                      onChanged: (v) async {
                        await widget.settings.setSplitTunnelEnabled(v);
                        _notifyReconnectIfNeeded();
                      },
                    )),
              ],
            ),
            const SizedBox(height: 14),
            Obx(() {
              final enabled = widget.settings.splitTunnelEnabled.value;
              final mode = widget.settings.splitTunnelMode.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ModeSegment(
                    mode: mode,
                    enabled: enabled,
                    onChanged: (m) async {
                      await widget.settings.setSplitTunnelMode(m);
                      _notifyReconnectIfNeeded();
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    mode.hint,
                    style: grotesk(size: 13, color: AppColors.textTertiary, height: 1.35),
                  ),
                ],
              );
            }),
            const SizedBox(height: 14),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search apps',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            Obx(() {
              final count = widget.settings.splitTunnelActivePackages.length;
              final enabled = widget.settings.splitTunnelEnabled.value;
              if (!enabled || count == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text('$count selected', style: mono(size: 12, color: AppColors.textMuted)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () async {
                        await widget.settings.clearSplitTunnelSelection();
                        _notifyReconnectIfNeeded();
                      },
                      child: Text('Clear', style: grotesk(size: 13, weight: FontWeight.w500, color: AppColors.accent)),
                    ),
                  ],
                ),
              );
            }),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                  : _filtered.isEmpty
                      ? Center(
                          child: Text(
                            _query.isEmpty ? 'No apps found' : 'No matches for "$_query"',
                            style: grotesk(size: 13, color: AppColors.textMuted),
                          ),
                        )
                      : Obx(() {
                          final selected = widget.settings.splitTunnelActivePackages.toSet();
                          final enabled = widget.settings.splitTunnelEnabled.value;
                          return ListView.builder(
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) {
                              final app = _filtered[i];
                              final isOn = selected.contains(app.packageName);
                              final initial = app.label.isNotEmpty ? app.label[0].toUpperCase() : '?';
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: enabled
                                      ? () async {
                                          await widget.settings.toggleSplitTunnelApp(app.packageName, !isOn);
                                          _notifyReconnectIfNeeded();
                                        }
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: isOn
                                              ? AppColors.accent.withValues(alpha: 0.2)
                                              : Colors.white.withValues(alpha: 0.06),
                                          child: Text(
                                            initial,
                                            style: mono(
                                              size: 13,
                                              weight: FontWeight.w600,
                                              color: isOn ? AppColors.accent : AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(app.label, style: grotesk(size: 14.5, weight: FontWeight.w500)),
                                              Text(app.packageName, style: mono(size: 10.5, color: AppColors.textMuted)),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          isOn ? Icons.check_circle_rounded : Icons.circle_outlined,
                                          size: 22,
                                          color: isOn ? AppColors.accent : AppColors.textDim,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        }),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final SplitTunnelMode mode;
  final bool enabled;
  final ValueChanged<SplitTunnelMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.strokeSoft),
      ),
      child: Row(
        children: SplitTunnelMode.values.map((m) {
          final active = mode == m;
          return Expanded(
            child: GestureDetector(
              onTap: enabled ? () => onChanged(m) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? AppColors.accent.withValues(alpha: enabled ? 0.22 : 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  m.segmentLabel,
                  style: grotesk(
                    size: 13,
                    weight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active
                        ? (enabled ? AppColors.accent : AppColors.textMuted)
                        : AppColors.textTertiary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}