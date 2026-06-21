import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/wallet_auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../../vpn/singbox_engine.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';

/// The premium home / connect screen for Erebrus v2.
class ConnectView extends StatelessWidget {
  const ConnectView({super.key, this.onChooseNode, this.onRequireAuth});

  /// Invoked when the user taps the node card to pick a server.
  final VoidCallback? onChooseNode;
  final VoidCallback? onRequireAuth;

  @override
  Widget build(BuildContext context) {
    final c = Get.isRegistered<VpnController>() ? Get.find<VpnController>() : Get.put(VpnController());
    final auth = Get.isRegistered<WalletAuthController>()
        ? Get.find<WalletAuthController>()
        : null;

    return Scaffold(
      body: Stack(
        children: [
          const _AuroraBackdrop(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
              child: Column(
                children: [
                  const _TopBar(),
                  const Spacer(flex: 2),
                  Obx(() {
                    final authed = auth?.isAuthenticated ?? false;
                    final entitled = auth?.isEntitled ?? false;
                    return ConnectOrb(
                      stage: c.stage.value,
                      transport: c.activeTransport.value,
                      onTap: c.isBusy
                          ? null
                          : () {
                              if (auth != null && !authed) {
                                c.error.value =
                                    'Connect your Solana wallet in Account first';
                                onRequireAuth?.call();
                                return;
                              }
                              if (auth != null && !entitled) {
                                c.error.value =
                                    'Start a free trial in Account to connect';
                                onRequireAuth?.call();
                                return;
                              }
                              c.toggle();
                            },
                    );
                  }),
                  const SizedBox(height: AppSpace.xl),
                  Obx(() => _StatusText(stage: c.stage.value, error: c.error.value)),
                  const Spacer(flex: 2),
                  Obx(() => _ModeSelector(selected: c.mode.value, onSelect: c.setMode, enabled: !c.isConnected)),
                  const SizedBox(height: AppSpace.lg),
                  Obx(() => _NodeCard(node: c.selectedNode.value, onTap: onChooseNode)),
                  const SizedBox(height: AppSpace.lg),
                  Obx(() => _StatsBar(stats: c.stats.value, connected: c.isConnected)),
                  const SizedBox(height: AppSpace.xl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (r) => AppGradients.aurora.createShader(r),
            child: Text('Erebrus',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white)),
          ),
          const Spacer(),
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.stroke),
            ),
            child: const Icon(Icons.person_outline, color: AppColors.textSecondary, size: 20),
          ),
        ],
      ),
    );
  }
}

/// The big animated power orb. Pulses while connecting, glows while protected.
class ConnectOrb extends StatefulWidget {
  const ConnectOrb({super.key, required this.stage, required this.onTap, this.transport});
  final VpnStage stage;
  final VoidCallback? onTap;
  final Transport? transport;

  @override
  State<ConnectOrb> createState() => _ConnectOrbState();
}

class _ConnectOrbState extends State<ConnectOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Gradient get _gradient => switch (widget.stage) {
        VpnStage.connected => AppGradients.protected,
        VpnStage.connecting || VpnStage.disconnecting => const LinearGradient(colors: [AppColors.connecting, AppColors.violet]),
        _ => widget.transport == Transport.wireguard ? AppGradients.aurora : AppGradients.stealth,
      };

  Color get _glow => switch (widget.stage) {
        VpnStage.connected => AppColors.connected,
        VpnStage.connecting => AppColors.connecting,
        VpnStage.error => AppColors.danger,
        _ => AppColors.indigo,
      };

  @override
  Widget build(BuildContext context) {
    final busy = widget.stage == VpnStage.connecting || widget.stage == VpnStage.disconnecting;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = busy ? _ctrl.value : (widget.stage == VpnStage.connected ? 0.6 + _ctrl.value * 0.4 : 0.5);
          return Container(
            width: 232,
            height: 232,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _glow.withValues(alpha: 0.10 + t * 0.30), blurRadius: 60 + t * 50, spreadRadius: 4 + t * 16),
              ],
            ),
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: _gradient),
          padding: const EdgeInsets.all(4),
          child: Container(
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.bgElevated),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                  : Icon(Icons.power_settings_new_rounded,
                      size: 76, color: widget.stage == VpnStage.connected ? AppColors.connected : Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.stage, this.error});
  final VpnStage stage;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final (title, sub, color) = switch (stage) {
      VpnStage.connected => ('Protected', 'Your traffic is encrypted', AppColors.connected),
      VpnStage.connecting => ('Connecting…', 'Negotiating a secure path', AppColors.connecting),
      VpnStage.disconnecting => ('Disconnecting…', '', AppColors.connecting),
      VpnStage.error => ('Not protected', error ?? 'Something went wrong', AppColors.danger),
      _ => ('Not protected', 'Tap to connect', AppColors.textSecondary),
    };
    return Column(
      children: [
        Text(title,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(sub, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.selected, required this.onSelect, required this.enabled});
  final ConnectMode selected;
  final ValueChanged<ConnectMode> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: ConnectMode.values.map((m) {
          final active = m == selected;
          return Expanded(
            child: GestureDetector(
              onTap: enabled ? () => onSelect(m) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: active ? AppGradients.aurora : null,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(m.label,
                    style: TextStyle(
                      color: active ? Colors.white : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node, this.onTap});
  final VpnNode? node;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              gradient: AppGradients.aurora,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.public, color: Colors.white, size: 22),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(node?.name ?? 'Choose a server',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  node == null
                      ? 'Smart pick by latency'
                      : '${node!.region}  ·  ${node!.supportsStealth ? "Stealth ready" : "WireGuard"}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.stats, required this.connected});
  final VpnStats stats;
  final bool connected;

  String _rate(int bps) {
    if (!connected) return '—';
    if (bps >= 1000000) return '${(bps / 1000000).toStringAsFixed(1)} MB/s';
    if (bps >= 1000) return '${(bps / 1000).toStringAsFixed(0)} KB/s';
    return '$bps B/s';
  }

  String _total(int bytes) {
    if (!connected) return '—';
    if (bytes >= 1000000000) return '${(bytes / 1000000000).toStringAsFixed(2)} GB';
    if (bytes >= 1000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
    if (bytes >= 1000) return '${(bytes / 1000).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: AppSpace.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          StatTile(label: 'Download', value: _rate(stats.downlinkBps), icon: Icons.south_rounded, color: AppColors.connected),
          StatTile(label: 'Upload', value: _rate(stats.uplinkBps), icon: Icons.north_rounded, color: AppColors.cyan),
          StatTile(label: 'Session', value: _total(stats.rxBytes + stats.txBytes), icon: Icons.data_usage_rounded),
        ],
      ),
    );
  }
}

/// A soft aurora glow behind the orb.
class _AuroraBackdrop extends StatelessWidget {
  const _AuroraBackdrop();
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.bg),
        child: Align(
          alignment: const Alignment(0, -0.35),
          child: Container(
            width: 360,
            height: 360,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.indigo.withValues(alpha: 0.25),
                AppColors.bg.withValues(alpha: 0.0),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
