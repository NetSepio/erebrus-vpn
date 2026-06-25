import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/wallet_auth_controller.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../../vpn/gateway_controller.dart';
import '../../vpn/singbox_engine.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';
import 'node_display.dart';

/// The dVPN tab — connect/disconnect the tunnel, pick protocol, watch live
/// stats, and open diagnostics / the server picker. Binds to [VpnController];
/// the dial reflects the real tunnel stage and the readout shows real
/// throughput. Sheets are hosted by the shell via the callbacks.
class ConnectView extends StatefulWidget {
  const ConnectView({
    super.key,
    this.onOpenServers,
    this.onOpenDiagnostics,
    this.onGoSettings,
  });

  final VoidCallback? onOpenServers;
  final VoidCallback? onOpenDiagnostics;
  final VoidCallback? onGoSettings;

  @override
  State<ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends State<ConnectView> {
  VpnController get _c => Get.find<VpnController>();
  WalletAuthController? get _auth =>
      Get.isRegistered<WalletAuthController>() ? Get.find<WalletAuthController>() : null;

  Timer? _ticker;
  DateTime? _connectedAt;
  Duration _elapsed = Duration.zero;
  Worker? _stageWorker;

  @override
  void initState() {
    super.initState();
    _stageWorker = ever<VpnStage>(_c.stage, _onStage);
    if (_c.isConnected) _startTimer();
  }

  void _onStage(VpnStage s) {
    if (s == VpnStage.connected) {
      _startTimer();
    } else {
      _stopTimer();
    }
  }

  void _startTimer() {
    _connectedAt ??= DateTime.now();
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_connectedAt!));
    });
  }

  void _stopTimer() {
    _ticker?.cancel();
    _ticker = null;
    _connectedAt = null;
    if (mounted) setState(() => _elapsed = Duration.zero);
  }

  @override
  void dispose() {
    _stageWorker?.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  void _onDialTap() {
    final auth = _auth;
    if (auth != null && !auth.isEntitled) {
      final ent = auth.entitlement.value;
      _c.error.value = ent.trialConsumed
          ? 'Trial ended — renew on erebrus.io with the same wallet'
          : 'Start your free trial in Settings to connect';
      widget.onGoSettings?.call();
      return;
    }
    _c.error.value = null;
    _c.toggle();
  }

  void _setProtocol(ConnectMode m) {
    _c.setMode(m);
    if (Get.isRegistered<AppSettingsController>()) {
      Get.find<AppSettingsController>().setDefaultProtocol(m);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // header
              Obx(() => _StatusHeader(
                    stage: _c.stage.value,
                    blocking: _c.killSwitchBlocking.value,
                    onDiagnostics: widget.onOpenDiagnostics,
                  )),
              const SizedBox(height: 16),
              // protocol segmented
              Obx(() => _ProtocolSegment(
                    mode: _c.mode.value,
                    enabled: !_c.isConnected && !_c.killSwitchBlocking.value,
                    onSelect: _setProtocol,
                  )),
              const SizedBox(height: 8),
              Obx(() => Center(
                    child: Text(
                      _c.mode.value.blurb,
                      textAlign: TextAlign.center,
                      style: mono(size: 11, weight: FontWeight.w400, color: AppColors.textMuted),
                    ),
                  )),
              // dial
              Expanded(
                child: Center(
                  child: Obx(() {
                    final stage = _c.stage.value;
                    final blocking = _c.killSwitchBlocking.value;
                    final err = _c.error.value;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConnectDial(
                          stage: blocking ? VpnStage.error : stage,
                          durationLabel: _fmtDur(_elapsed),
                          onTap: _c.isBusy ? null : _onDialTap,
                        ),
                        if (err != null && err.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              err,
                              textAlign: TextAlign.center,
                              style: grotesk(size: 12.5, weight: FontWeight.w500, color: AppColors.danger),
                            ),
                          ),
                        ],
                      ],
                    );
                  }),
                ),
              ),
              // data readout
              Obx(() => _DataReadout(stats: _c.stats.value, connected: _c.isConnected)),
              const SizedBox(height: 14),
              // server card
              Obx(() {
                final gw = Get.find<GatewayController>();
                final node = _c.selectedNode.value;
                final registryEmpty = gw.nodes.isEmpty;
                final display = registryEmpty
                    ? NodeDisplay.placeholder(registryError: gw.error.value != null)
                    : NodeDisplay.of(node);
                return _ServerCard(
                  display: display,
                  egressIp: _c.egressIp.value,
                  egressLoading: _c.egressIpLoading.value,
                  connected: _c.isConnected,
                  onTap: widget.onOpenServers,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmtDur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Formats a byte count using the spec's KB/MB/GB scale.
String fmtData(int bytes) {
  final kb = bytes ~/ 1024;
  if (kb < 1024) return '$kb KB';
  final mb = bytes / (1024 * 1024);
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.stage, required this.blocking, this.onDiagnostics});
  final VpnStage stage;
  final bool blocking;
  final VoidCallback? onDiagnostics;

  @override
  Widget build(BuildContext context) {
    final label = blocking
        ? 'TRAFFIC BLOCKED'
        : switch (stage) {
            VpnStage.connected => 'PROTECTED',
            VpnStage.connecting => 'SECURING TUNNEL',
            VpnStage.disconnecting => 'SECURING TUNNEL',
            VpnStage.error => 'NOT CONNECTED',
            _ => 'NOT CONNECTED',
          };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('STATUS', style: mono(size: 11, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 11 * 0.16)),
            const SizedBox(height: 2),
            Text(label, style: grotesk(size: 18, weight: FontWeight.w600, letterSpacing: -0.18)),
          ],
        ),
        const Spacer(),
        GestureDetector(
          onTap: onDiagnostics,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.show_chart, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 7),
                Text('DIAGNOSTICS',
                    style: mono(size: 11, weight: FontWeight.w500, color: AppColors.textSecondary, letterSpacing: 11 * 0.06)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProtocolSegment extends StatelessWidget {
  const _ProtocolSegment({required this.mode, required this.enabled, required this.onSelect});
  final ConnectMode mode;
  final bool enabled;
  final ValueChanged<ConnectMode> onSelect;

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
          _seg('AUTO', mode == ConnectMode.auto, () => onSelect(ConnectMode.auto)),
          const SizedBox(width: 4),
          _seg('WIREGUARD', mode == ConnectMode.wireguard, () => onSelect(ConnectMode.wireguard)),
          const SizedBox(width: 4),
          _seg('STEALTH', mode == ConnectMode.stealth, () => onSelect(ConnectMode.stealth)),
        ],
      ),
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: mono(
              size: 12,
              weight: FontWeight.w600,
              color: active ? AppColors.onAccent : AppColors.textTertiary,
              letterSpacing: 12 * 0.05,
            ),
          ),
        ),
      ),
    );
  }
}

/// The 240×240 connect dial with offline / connecting / connected states.
class ConnectDial extends StatefulWidget {
  const ConnectDial({super.key, required this.stage, required this.durationLabel, this.onTap});
  final VpnStage stage;
  final String durationLabel;
  final VoidCallback? onTap;

  @override
  State<ConnectDial> createState() => _ConnectDialState();
}

class _ConnectDialState extends State<ConnectDial> with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  bool get _connecting => widget.stage == VpnStage.connecting || widget.stage == VpnStage.disconnecting;
  bool get _connected => widget.stage == VpnStage.connected;

  @override
  Widget build(BuildContext context) {
    const size = 240.0;
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // base ring
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1.5),
              ),
            ),
            // connecting arc
            if (_connecting)
              AnimatedBuilder(
                animation: _spin,
                builder: (_, _) => Transform.rotate(
                  angle: _spin.value * 2 * math.pi,
                  child: CustomPaint(size: const Size(size, size), painter: _ArcRingPainter()),
                ),
              ),
            // connected pulse rings + solid glow ring
            if (_connected) ...[
              _PulseRing(controller: _pulse, phase: 0.0),
              _PulseRing(controller: _pulse, phase: 0.5),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 2),
                  boxShadow: [
                    BoxShadow(color: AppColors.accent.withValues(alpha: 0.7), blurRadius: 50, spreadRadius: -6),
                  ],
                ),
              ),
            ],
            // center disk
            _CenterDisk(stage: widget.stage, durationLabel: widget.durationLabel),
          ],
        ),
      ),
    );
  }
}

class _CenterDisk extends StatelessWidget {
  const _CenterDisk({required this.stage, required this.durationLabel});
  final VpnStage stage;
  final String durationLabel;

  @override
  Widget build(BuildContext context) {
    final connected = stage == VpnStage.connected;
    final connecting = stage == VpnStage.connecting || stage == VpnStage.disconnecting;

    final gradient = connected
        ? const RadialGradient(center: Alignment(0, -0.3), colors: [Color(0xFF2A1709), Color(0xFF140D08)])
        : connecting
            ? const RadialGradient(center: Alignment(0, -0.3), colors: [Color(0xFF1D150F), Color(0xFF0D0D11)])
            : const RadialGradient(center: Alignment(0, -0.3), colors: [Color(0xFF18181E), Color(0xFF0D0D11)]);

    Widget content;
    if (connected) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_user, size: 38, color: AppColors.accent),
          const SizedBox(height: 4),
          Text(durationLabel, style: mono(size: 25, weight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text('PROTECTED', style: mono(size: 11, weight: FontWeight.w500, color: AppColors.accent, letterSpacing: 11 * 0.12)),
        ],
      );
    } else if (connecting) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.power_settings_new, size: 40, color: AppColors.accent),
          const SizedBox(height: 9),
          Text('SECURING…', style: mono(size: 12, weight: FontWeight.w500, color: AppColors.accent, letterSpacing: 12 * 0.05)),
        ],
      );
    } else {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.power_settings_new, size: 40, color: AppColors.textDim),
          const SizedBox(height: 9),
          Text('TAP TO CONNECT', style: mono(size: 12, weight: FontWeight.w500, color: AppColors.textTertiary, letterSpacing: 12 * 0.05)),
        ],
      );
    }

    return Container(
      width: 172,
      height: 172,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
      child: content,
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.controller, required this.phase});
  final AnimationController controller;
  final double phase;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final t = (controller.value + phase) % 1.0;
        final scale = 0.8 + (1.75 - 0.8) * t;
        final opacity = t < 0.8 ? 0.55 * (1 - t / 0.8) : 0.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accent.withValues(alpha: opacity), width: 2),
            ),
          ),
        );
      },
    );
  }
}

class _ArcRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2 - 1.5;
    // top arc, bright
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2 - 0.5,
      1.0,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = AppColors.accent,
    );
    // right arc, dim
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0.2,
      0.9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = AppColors.accent.withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DataReadout extends StatelessWidget {
  const _DataReadout({required this.stats, required this.connected});
  final VpnStats stats;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.strokeSoft),
          bottom: BorderSide(color: AppColors.strokeSoft),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: _col('↓ DOWNLOAD', connected ? fmtData(stats.rxBytes) : '0 KB')),
          Container(width: 1, height: 34, color: AppColors.strokeSoft),
          Expanded(child: _col('↑ UPLOAD', connected ? fmtData(stats.txBytes) : '0 KB')),
        ],
      ),
    );
  }

  Widget _col(String label, String value) {
    return Column(
      children: [
        Text(label, style: mono(size: 11, weight: FontWeight.w400, color: AppColors.textMuted, letterSpacing: 11 * 0.08)),
        const SizedBox(height: 3),
        Text(value, style: mono(size: 15, weight: FontWeight.w600, color: AppColors.textPrimary)),
      ],
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.display,
    this.egressIp,
    this.egressLoading = false,
    this.connected = false,
    this.onTap,
  });
  final NodeDisplay display;
  final String? egressIp;
  final bool egressLoading;
  final bool connected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = display;
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      color: d.isPlaceholder ? AppColors.surface2 : AppColors.surface,
      borderColor: d.isPlaceholder && d.name.contains('unavailable')
          ? AppColors.warn.withValues(alpha: 0.35)
          : AppColors.stroke,
      child: Row(
        children: [
          if (d.isPlaceholder)
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.hub_outlined, size: 22, color: AppColors.accent.withValues(alpha: 0.9)),
            )
          else
            Text(d.flag, style: const TextStyle(fontSize: 26, height: 1)),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, style: mono(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(d.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: grotesk(size: 12, weight: FontWeight.w400, color: AppColors.textTertiary)),
                    ),
                    const SizedBox(width: 8),
                    Container(width: 5, height: 5, decoration: BoxDecoration(color: d.networkColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(d.network, style: mono(size: 11, weight: FontWeight.w400, color: AppColors.textTertiary)),
                  ],
                ),
                if (connected) ...[
                  const SizedBox(height: 6),
                  Text(
                    egressLoading
                        ? 'Egress IP · checking…'
                        : (egressIp != null
                            ? 'Egress IP · $egressIp'
                            : 'Egress IP · unavailable (see Diagnostics)'),
                    style: mono(
                      size: 11,
                      weight: FontWeight.w500,
                      color: egressIp != null ? AppColors.success : AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(d.loadLabel, style: mono(size: 14, weight: FontWeight.w600, color: d.loadColor)),
              const SizedBox(height: 2),
              Text(
                d.isPlaceholder ? 'BROWSE ›' : 'CHANGE ›',
                style: mono(size: 10, weight: FontWeight.w400, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
