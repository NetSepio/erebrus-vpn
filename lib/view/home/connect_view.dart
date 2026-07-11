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
import 'node_ui_widgets.dart';

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
    // Tapping the dial mid-connect aborts the attempt (Stealth can take a while).
    if (_c.stage.value == VpnStage.connecting) {
      _c.cancelConnect();
      return;
    }
    final node = _c.selectedNode.value;
    if (node != null && !node.canAcceptClients) {
      _c.error.value = 'Selected server is at capacity — pick another node';
      return;
    }
    final auth = _auth;
    if (auth != null && !auth.canConnectVpn(node)) {
      final ent = auth.entitlement.value;
      _c.error.value = node?.isPrivateAccess == true && ent.orgMember == false
          ? 'Accept your workspace invite to connect to private org nodes'
          : ent.trialConsumed
              ? 'Trial ended — renew on erebrus.io with the same wallet'
              : 'Start your free trial in Settings to connect';
      widget.onGoSettings?.call();
      return;
    }
    _c.error.value = null;
    _c.toggle();
  }

  /// What the dial says while the tunnel is being established.
  String? _connectingLabel(VpnStage stage) {
    if (stage == VpnStage.disconnecting) return 'STOPPING…';
    if (stage != VpnStage.connecting) return null;
    return switch (_c.activeTransport.value) {
      null => 'SECURING…',
      Transport.wireguard => 'WIREGUARD HANDSHAKE…',
      Transport.vlessReality => 'STEALTH HANDSHAKE…',
      Transport.hysteria2 => 'QUIC HANDSHAKE…',
    };
  }

  void _setProtocol(ConnectMode m) {
    _c.setMode(m);
    if (Get.isRegistered<AppSettingsController>()) {
      Get.find<AppSettingsController>().setDefaultProtocol(m);
    }
  }

  /// Highlights the transport in use while connected/connecting; otherwise the
  /// user's saved preference (Auto / WireGuard / Stealth).
  ConnectMode _displayMode(VpnController c) {
    final stage = c.stage.value;
    final transport = c.activeTransport.value;
    if ((stage == VpnStage.connected || stage == VpnStage.connecting) &&
        transport != null) {
      return transport.connectMode;
    }
    return c.mode.value;
  }

  String _protocolBlurb(VpnController c) {
    final stage = c.stage.value;
    final transport = c.activeTransport.value;
    if (stage == VpnStage.connected && transport != null) {
      return 'In use · ${transport.label}';
    }
    if (stage == VpnStage.connecting && transport != null) {
      return transport.connectMode.blurb;
    }
    return c.mode.value.blurb;
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
                    healthy: _c.tunnelHealthy.value,
                    onDiagnostics: widget.onOpenDiagnostics,
                  )),
              const SizedBox(height: 16),
              // protocol segmented
              Obx(() => _ProtocolSegment(
                    mode: _displayMode(_c),
                    enabled: !_c.isConnected &&
                        !_c.isBusy &&
                        !_c.killSwitchBlocking.value,
                    onSelect: _setProtocol,
                  )),
              const SizedBox(height: 8),
              Obx(() => Center(
                    child: Text(
                      _protocolBlurb(_c),
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
                    final transport = _c.activeTransport.value;
                    final stealthWait = stage == VpnStage.connecting &&
                        transport != null &&
                        transport != Transport.wireguard;
                    final stalled = stage == VpnStage.connected && !_c.tunnelHealthy.value;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConnectDial(
                          stage: blocking ? VpnStage.error : stage,
                          durationLabel: _fmtDur(_elapsed),
                          connectingLabel: _connectingLabel(stage),
                          // Connecting stays tappable: it cancels. Only a
                          // disconnect in flight is uninterruptible.
                          onTap: stage == VpnStage.disconnecting ? null : _onDialTap,
                        ),
                        if (stealthWait) ...[
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'Disguising traffic — this can take up to a minute on strict networks.',
                              textAlign: TextAlign.center,
                              style: grotesk(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted),
                            ),
                          ),
                        ],
                        if (stalled) ...[
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'Tunnel is up but nothing is getting through — tap the dial to disconnect, then reconnect (try Stealth).',
                              textAlign: TextAlign.center,
                              style: grotesk(size: 12.5, weight: FontWeight.w500, color: AppColors.danger),
                            ),
                          ),
                        ],
                        if (err != null && err.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              err,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
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
                    : NodeDisplay.of(node, showActivity: true);
                // Reflect the selected node's source (public vs its org/workspace).
                final org = node?.org;
                final showScope = gw.orgs.isNotEmpty || org != null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showScope) ...[
                      _ScopeStrip(
                        label: org?.name ?? 'Public network',
                        isOrg: org != null,
                        verified: org?.verified ?? false,
                        onTap: widget.onOpenServers,
                      ),
                      const SizedBox(height: 8),
                    ],
                    _ServerCard(
                      display: display,
                      egressIp: _c.egressIp.value,
                      egressLoading: _c.egressIpLoading.value,
                      connected: _c.isConnected,
                      onTap: widget.onOpenServers,
                    ),
                  ],
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
  const _StatusHeader({
    required this.stage,
    required this.blocking,
    this.healthy = true,
    this.onDiagnostics,
  });
  final VpnStage stage;
  final bool blocking;
  final bool healthy;
  final VoidCallback? onDiagnostics;

  @override
  Widget build(BuildContext context) {
    final label = blocking
        ? 'TRAFFIC BLOCKED'
        : switch (stage) {
            VpnStage.connected => healthy ? 'PROTECTED' : 'TUNNEL STALLED',
            VpnStage.connecting => 'SECURING TUNNEL',
            VpnStage.disconnecting => 'DISCONNECTING',
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
              color: active ? AppColors.onAccent : AppColors.textSecondary,
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
  const ConnectDial({
    super.key,
    required this.stage,
    required this.durationLabel,
    this.connectingLabel,
    this.onTap,
  });
  final VpnStage stage;
  final String durationLabel;

  /// Status text while connecting/disconnecting (e.g. "STEALTH HANDSHAKE…").
  final String? connectingLabel;
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
            _CenterDisk(
              stage: widget.stage,
              durationLabel: widget.durationLabel,
              connectingLabel: widget.connectingLabel,
              cancellable: widget.stage == VpnStage.connecting && widget.onTap != null,
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterDisk extends StatelessWidget {
  const _CenterDisk({
    required this.stage,
    required this.durationLabel,
    this.connectingLabel,
    this.cancellable = false,
  });
  final VpnStage stage;
  final String durationLabel;
  final String? connectingLabel;
  final bool cancellable;

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
          Text(
            connectingLabel ?? 'SECURING…',
            textAlign: TextAlign.center,
            style: mono(size: 12, weight: FontWeight.w500, color: AppColors.accent, letterSpacing: 12 * 0.05),
          ),
          if (cancellable) ...[
            const SizedBox(height: 5),
            Text('TAP TO CANCEL', style: mono(size: 10, weight: FontWeight.w500, color: AppColors.textTertiary, letterSpacing: 10 * 0.08)),
          ],
        ],
      );
    } else {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.power_settings_new, size: 40, color: AppColors.textSecondary),
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
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.strokeSoft),
          bottom: BorderSide(color: AppColors.strokeSoft),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _TrafficStat(
                label: 'DOWNLOAD',
                arrow: '↓',
                value: connected ? fmtData(stats.rxBytes) : '0 KB',
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1, color: AppColors.strokeSoft),
            Expanded(
              child: _TrafficStat(
                label: 'UPLOAD',
                arrow: '↑',
                value: connected ? fmtData(stats.txBytes) : '0 KB',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrafficStat extends StatelessWidget {
  const _TrafficStat({required this.label, required this.arrow, required this.value});
  final String label;
  final String arrow;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(arrow, style: mono(size: 11, weight: FontWeight.w500, color: AppColors.textMuted)),
            const SizedBox(width: 4),
            Text(
              label,
              style: mono(size: 11, weight: FontWeight.w400, color: AppColors.textMuted, letterSpacing: 11 * 0.08),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          value,
          textAlign: TextAlign.center,
          style: mono(size: 15, weight: FontWeight.w600, color: AppColors.textPrimary),
        ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d.isPlaceholder) ...[
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.hub_outlined, size: 22, color: AppColors.accent.withValues(alpha: 0.9)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(size: 14, weight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    d.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: grotesk(size: 12, weight: FontWeight.w400, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ] else
            Expanded(
              child: NodeCompactRow(display: d, nameSize: 14),
            ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (d.isPlaceholder)
                TextActionChip(label: 'BROWSE', accent: true, onTap: onTap)
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (d.showLoad) ...[
                      Text(
                        d.loadLabel,
                        style: mono(size: 14, weight: FontWeight.w600, color: d.loadColor),
                      ),
                      const SizedBox(width: 8),
                    ],
                    VisibleIconButton(
                      icon: Icons.swap_horiz_rounded,
                      onTap: onTap,
                      color: AppColors.accent,
                      borderColor: AppColors.accent.withValues(alpha: 0.35),
                      backgroundColor: AppColors.accent.withValues(alpha: 0.14),
                    ),
                  ],
                ),
              if (connected) ...[
                const SizedBox(height: 6),
                Text(
                  egressLoading
                      ? 'Egress · …'
                      : (egressIp != null ? 'Egress · $egressIp' : 'Egress · —'),
                  style: mono(
                    size: 10,
                    weight: FontWeight.w500,
                    color: egressIp != null ? AppColors.success : AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact label above the server card showing which scope ("Public network"
/// or an organization) the picker is browsing. Tapping opens the picker.
class _ScopeStrip extends StatelessWidget {
  const _ScopeStrip({
    required this.label,
    required this.isOrg,
    required this.verified,
    this.onTap,
  });
  final String label;
  final bool isOrg;
  final bool verified;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = isOrg ? AppColors.accent : AppColors.textTertiary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(isOrg ? Icons.apartment_rounded : Icons.public,
              size: 13, color: accent),
          const SizedBox(width: 7),
          Text(
            'VPN SOURCE',
            style: mono(
              size: 10,
              weight: FontWeight.w500,
              color: AppColors.textMuted,
              letterSpacing: 10 * 0.06,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: grotesk(size: 12, weight: FontWeight.w600, color: accent),
            ),
          ),
          if (verified) ...[
            const SizedBox(width: 4),
            Icon(Icons.verified, size: 12, color: accent),
          ],
          const Spacer(),
          Text(
            'CHANGE',
            style: mono(
              size: 10,
              weight: FontWeight.w600,
              color: AppColors.accent,
              letterSpacing: 10 * 0.06,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right, size: 14, color: AppColors.accent),
        ],
      ),
    );
  }
}
