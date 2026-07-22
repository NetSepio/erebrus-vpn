import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../guest/guest_config_model.dart';
import '../../guest/guest_config_store.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../../vpn/singbox_engine.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';
import '../home/connect_dial.dart';
import 'guest_scan_view.dart';

/// The guest VPN home screen.
///
/// Users can import a configuration from a file or QR code, select one of the
/// persisted imports, and connect/disconnect. Node selection is not needed.
class GuestConnectView extends StatefulWidget {
  const GuestConnectView({super.key});

  @override
  State<GuestConnectView> createState() => _GuestConnectViewState();
}

class _GuestConnectViewState extends State<GuestConnectView> {
  final _guest = Get.find<GuestConfigController>();
  final _vpn = Get.find<VpnController>();
  final _settings = Get.find<AppSettingsController>();

  Timer? _ticker;
  DateTime? _connectedAt;
  Duration _elapsed = Duration.zero;
  Worker? _stageWorker;

  @override
  void initState() {
    super.initState();
    _stageWorker = ever(_vpn.stage, _onStageChanged);
    _onStageChanged(_vpn.stage.value);
    _maybeResetMode();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stageWorker?.dispose();
    super.dispose();
  }

  void _onStageChanged(VpnStage stage) {
    if (stage == VpnStage.connected) {
      _connectedAt ??= DateTime.now();
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed = DateTime.now().difference(_connectedAt!));
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
      _connectedAt = null;
      if (mounted) setState(() => _elapsed = Duration.zero);
    }
  }

  void _maybeResetMode() {
    final config = _guest.selected;
    if (config != null &&
        !config.bundle.hasStealth &&
        _vpn.mode.value == ConnectMode.stealth) {
      _vpn.setMode(ConnectMode.wireguard);
    }
  }

  String _connectingLabel(VpnStage stage) {
    final mode = _vpn.mode.value;
    if (stage == VpnStage.disconnecting) return 'DISCONNECTING…';
    if (mode == ConnectMode.stealth) return 'STEALTH HANDSHAKE…';
    if (mode == ConnectMode.auto) return 'AUTO SELECT…';
    return 'WIREGUARD HANDSHAKE…';
  }

  Future<void> _onDialTap() async {
    final stage = _vpn.stage.value;
    if (stage == VpnStage.connected || stage == VpnStage.disconnecting) {
      await _vpn.disconnect();
      return;
    }
    if (stage == VpnStage.connecting) {
      await _vpn.disconnect();
      return;
    }
    final config = _guest.selected;
    if (config == null) {
      HapticFeedback.lightImpact();
      Get.snackbar(
        'No config selected',
        'Import a configuration file or scan a QR code first.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final node = config.toNode();
    _vpn.selectNode(node);
    await _vpn.connect(
      node: node,
      providedBundle: config.bundle,
      clientPrivateKey: config.clientPrivateKey,
    );
  }

  static const _kAllowedExtensions = ['conf', 'json', 'txt'];

  Future<void> _importFromFile() async {
    try {
      // Use FileType.any with manual extension validation. FileType.custom
      // relies on OS-level MIME/UTI filters that Android and iOS often fail
      // to map for .conf and sometimes .json, so the files appear grayed out.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final ext = (file.extension ?? '').toLowerCase();
      if (!_kAllowedExtensions.contains(ext)) {
        Get.snackbar(
          'Unsupported file type',
          'Please choose a .conf, .json, or .txt config file.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      String text;
      if (file.path != null) {
        text = await File(file.path!).readAsString();
      } else if (file.bytes != null) {
        text = utf8.decode(file.bytes!);
      } else {
        throw FormatException('Selected file has no readable content');
      }
      final name = file.name;
      final config = GuestVpnConfig.parse(text, name: name);
      await _guest.add(config);
      _maybeResetMode();
      HapticFeedback.lightImpact();
    } catch (e) {
      Get.snackbar(
        'Import failed',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _importFromQr() async {
    final raw = await Get.to<String>(() => const GuestScanView());
    if (raw == null || raw.isEmpty) return;
    try {
      final config = GuestVpnConfig.parse(raw, name: 'Scanned config');
      await _guest.add(config);
      _maybeResetMode();
      HapticFeedback.lightImpact();
    } catch (e) {
      Get.snackbar(
        'QR import failed',
        e.toString(),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _deleteConfig(GuestVpnConfig config) async {
    if (_guest.selectedId.value == config.id && _vpn.isConnected) {
      await _vpn.disconnect();
    }
    await _guest.delete(config);
  }

  String _protocolLabel(GuestVpnConfig c) {
    if (c.bundle.hasStealth) return 'WireGuard / Stealth';
    return 'WireGuard only';
  }

  @override
  Widget build(BuildContext context) {
    final stage = _vpn.stage.value;
    final blocking = _vpn.killSwitchBlocking.value;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 700;
            final sectionGap = compact ? 12.0 : 16.0;
            final importGap = compact ? 10.0 : 14.0;
            final contentGap = compact ? 12.0 : 18.0;
            final dialGap = compact ? 10.0 : 14.0;
            final dialSize = (constraints.maxHeight - (compact ? 350 : 430))
                .clamp(170.0, 240.0);

            return ListView(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 22,
                compact ? 12 : 20,
                compact ? 16 : 22,
                compact ? 16 : 34,
              ),
              children: [
                _Header(),
                SizedBox(height: sectionGap),
                _ImportRow(onUpload: _importFromFile, onScan: _importFromQr),
                SizedBox(height: importGap),
                Obx(
                  () => _ConfigList(
                    configs: _guest.configs,
                    selectedId: _guest.selectedId.value,
                    protocolLabel: _protocolLabel,
                    onSelect: (c) {
                      _guest.select(c);
                      _maybeResetMode();
                    },
                    onDelete: _deleteConfig,
                  ),
                ),
                SizedBox(height: contentGap),
                Obx(() {
                  final config = _guest.selected;
                  if (config == null) {
                    return SizedBox(height: compact ? 4 : 6);
                  }
                  return Column(
                    children: [
                      _ConfigSummaryCard(
                        config: config,
                        protocolLabel: _protocolLabel(config),
                      ),
                      SizedBox(height: contentGap),
                    ],
                  );
                }),
                Obx(() {
                  final config = _guest.selected;
                  return _ModeRow(
                    mode: _vpn.mode.value,
                    enabled: config != null,
                    stealthAvailable: config?.bundle.hasStealth ?? false,
                    onChanged: (m) {
                      _vpn.setMode(m);
                      _settings.setDefaultProtocol(m);
                    },
                  );
                }),
                SizedBox(height: dialGap),
                Center(
                  child: SizedBox.square(
                    dimension: dialSize,
                    child: FittedBox(
                      child: Obx(
                        () => ConnectDial(
                          stage: blocking ? VpnStage.error : stage,
                          durationLabel: fmtDuration(_elapsed),
                          connectingLabel: _connectingLabel(stage),
                          onTap: _onDialTap,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: dialGap),
                Obx(
                  () => _StatsReadout(
                    stats: _vpn.stats.value,
                    connected: _vpn.stage.value == VpnStage.connected,
                    egressIp: _vpn.egressIp.value,
                    egressLoading: _vpn.egressIpLoading.value,
                    protocol:
                        _vpn.activeTransport.value?.label ??
                        _vpn.mode.value.label,
                  ),
                ),
                if (_vpn.error.value != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _vpn.error.value!,
                    textAlign: TextAlign.center,
                    style: grotesk(
                      size: 13,
                      weight: FontWeight.w500,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Erebrus VPN',
                style: grotesk(
                  size: 24,
                  weight: FontWeight.w600,
                  letterSpacing: -0.48,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Import a config to connect to Erebrus VPN.',
                style: grotesk(
                  size: 13,
                  weight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImportRow extends StatelessWidget {
  const _ImportRow({required this.onUpload, required this.onScan});
  final VoidCallback onUpload;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ImportButton(
            icon: Icons.upload_file_outlined,
            label: 'Upload .conf',
            onTap: onUpload,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ImportButton(
            icon: Icons.qr_code_scanner,
            label: 'Scan QR',
            onTap: onScan,
          ),
        ),
      ],
    );
  }
}

class _ImportButton extends StatelessWidget {
  const _ImportButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.stroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: grotesk(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigList extends StatelessWidget {
  const _ConfigList({
    required this.configs,
    required this.selectedId,
    required this.protocolLabel,
    required this.onSelect,
    required this.onDelete,
  });

  final List<GuestVpnConfig> configs;
  final String? selectedId;
  final String Function(GuestVpnConfig) protocolLabel;
  final ValueChanged<GuestVpnConfig> onSelect;
  final ValueChanged<GuestVpnConfig> onDelete;

  @override
  Widget build(BuildContext context) {
    if (configs.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 24,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No imported configs yet',
                    style: grotesk(size: 14, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Upload a config or scan a QR code to get started.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: grotesk(
                      size: 11.5,
                      weight: FontWeight.w400,
                      color: AppColors.textSecondary,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'IMPORTED CONFIGS',
          style: mono(
            size: 11,
            weight: FontWeight.w500,
            color: AppColors.textMuted,
            letterSpacing: 11 * 0.12,
          ),
        ),
        const SizedBox(height: 9),
        ...configs.map((c) {
          final selected = c.id == selectedId;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.surface : AppColors.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.5)
                    : AppColors.stroke,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => onSelect(c),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 20,
                              color: selected
                                  ? AppColors.accent
                                  : AppColors.textTertiary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: grotesk(
                                      size: 14,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${c.region ?? 'Imported'} · ${protocolLabel(c)}',
                                    style: mono(
                                      size: 11.5,
                                      weight: FontWeight.w400,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onDelete(c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: AppColors.danger.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _ConfigSummaryCard extends StatelessWidget {
  const _ConfigSummaryCard({required this.config, required this.protocolLabel});
  final GuestVpnConfig config;
  final String protocolLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SELECTED',
            style: mono(
              size: 10,
              weight: FontWeight.w500,
              color: AppColors.textMuted,
              letterSpacing: 10 * 0.12,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  config.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: grotesk(size: 15, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              if (config.bundle.hasStealth)
                MonoChip(
                  label: 'STEALTH',
                  color: AppColors.accent,
                  background: AppColors.accent.withValues(alpha: 0.16),
                )
              else
                MonoChip(
                  label: 'WIREGUARD',
                  color: AppColors.textTertiary,
                  background: AppColors.textTertiary.withValues(alpha: 0.12),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            protocolLabel,
            style: grotesk(
              size: 12.5,
              weight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.mode,
    required this.enabled,
    required this.stealthAvailable,
    required this.onChanged,
  });
  final ConnectMode mode;
  final bool enabled;
  final bool stealthAvailable;
  final ValueChanged<ConnectMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: [
          _ModeChip(
            label: 'Auto',
            active: mode == ConnectMode.auto,
            enabled: enabled,
            onTap: () => onChanged(ConnectMode.auto),
          ),
          _ModeChip(
            label: 'WireGuard',
            active: mode == ConnectMode.wireguard,
            enabled: enabled,
            onTap: () => onChanged(ConnectMode.wireguard),
          ),
          if (stealthAvailable)
            _ModeChip(
              label: 'Stealth',
              active: mode == ConnectMode.stealth,
              enabled: enabled,
              onTap: () => onChanged(ConnectMode.stealth),
            ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active && enabled ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: grotesk(
              size: 12.5,
              weight: FontWeight.w600,
              color: !enabled
                  ? AppColors.textMuted.withValues(alpha: 0.55)
                  : active
                  ? AppColors.onAccent
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsReadout extends StatelessWidget {
  const _StatsReadout({
    required this.stats,
    required this.connected,
    this.egressIp,
    this.egressLoading = false,
    required this.protocol,
  });
  final VpnStats stats;
  final bool connected;
  final String? egressIp;
  final bool egressLoading;
  final String protocol;

  @override
  Widget build(BuildContext context) {
    final egressValue = connected
        ? (egressLoading
              ? '…'
              : (egressIp?.isNotEmpty == true ? egressIp! : '—'))
        : '—';
    final protocolValue = connected ? protocol : '—';
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.strokeSoft),
          bottom: BorderSide(color: AppColors.strokeSoft),
        ),
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _StatBox(
                    label: 'DOWNLOAD',
                    value: connected ? fmtData(stats.rxBytes) : '0 KB',
                  ),
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.strokeSoft,
                ),
                Expanded(
                  child: _StatBox(
                    label: 'UPLOAD',
                    value: connected ? fmtData(stats.txBytes) : '0 KB',
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.strokeSoft),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _StatBox(label: 'EGRESS IP', value: egressValue),
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppColors.strokeSoft,
                ),
                Expanded(
                  child: _StatBox(label: 'PROTOCOL', value: protocolValue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '↓',
              style: mono(
                size: 10,
                weight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: mono(
                size: 10,
                weight: FontWeight.w400,
                color: AppColors.textMuted,
                letterSpacing: 10 * 0.08,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: mono(
            size: 17,
            weight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
