import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/wallet_auth_controller.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../vpn/gateway_controller.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';
import '../browser/browser_view.dart';
import '../home/connect_view.dart';
import '../home/server_view.dart';
import '../profile/profile_view.dart';
import '../settings/settings_view.dart';

/// The v2 app shell: Connect / Browse / Servers / Account.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _autoConnectAttempted = false;
  Worker? _autoConnectWorker;

  void _go(int i) => setState(() => _index = i);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoConnectWorker = everAll(
      [
        Get.find<AppSettingsController>().autoConnectOnLaunch,
        Get.find<WalletAuthController>().sessionReady,
        Get.find<WalletAuthController>().entitlement,
        Get.find<VpnController>().selectedNode,
      ],
      (_) => _tryAutoConnect(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoConnect());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoConnectWorker?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final vpn = Get.find<VpnController>();
      final settings = Get.find<AppSettingsController>();
      unawaited(vpn.syncWithNative().then((_) {
        settings.pingDiagnosticsIfEnabled(vpn: vpn);
      }));
    }
  }

  void _tryAutoConnect() {
    if (_autoConnectAttempted) return;
    final settings = Get.find<AppSettingsController>();
    final auth = Get.find<WalletAuthController>();
    final vpn = Get.find<VpnController>();
    if (vpn.isConnected) {
      _autoConnectAttempted = true;
      return;
    }
    if (!settings.autoConnectOnLaunch.value) return;
    if (!auth.sessionReady.value || !auth.isEntitled) return;
    if (vpn.isConnected || vpn.isBusy || vpn.killSwitchBlocking.value) return;
    if (vpn.selectedNode.value == null) return;
    _autoConnectAttempted = true;
    vpn.connect();
  }

  @override
  Widget build(BuildContext context) {
    final gateway = Get.find<GatewayController>();
    final tabs = [
      ConnectView(onChooseNode: () => _go(2), onRequireAuth: () => _go(3)),
      const BrowserView(),
      Obx(() {
        final count = gateway.nodes.length;
        return ServerView(
          nodes: List<VpnNode>.from(gateway.nodes),
          gatewayUrl: gateway.gatewayUrl.value,
          loading: gateway.loading.value,
          error: gateway.error.value,
          warning: gateway.warning.value,
          nodeCount: count,
          onRefresh: gateway.refreshNodes,
          onSelected: () => _go(0),
        );
      }),
      Obx(() {
        final auth = Get.find<WalletAuthController>();
        final ent = auth.entitlement.value;
        final authed = auth.isAuthenticated;
        final entitled = auth.isEntitled;
        final trialBusy = auth.isStartingTrial.value;

        VoidCallback? onUnlock;
        String unlockLabel = 'Unlock access';
        if (!authed) {
          onUnlock = auth.openSignIn;
          unlockLabel = auth.isSolanaMobileDevice.value
              ? 'Sign in with Seed Vault'
              : 'Sign in';
        } else if (!entitled) {
          onUnlock = trialBusy ? null : auth.startFreeTrial;
          unlockLabel = trialBusy ? 'Starting trial…' : 'Start free trial';
        }

        return ProfileView(
          walletAddress: auth.walletAddress.value,
          planLabel: authed ? ent.planLabel : 'Free',
          entitlementSource: entitled ? ent.source : null,
          daysLeft: entitled ? ent.daysRemaining : null,
          onManagePlan: onUnlock,
          unlockLabel: unlockLabel,
          isLoadingEntitlement: auth.isLoadingEntitlement.value,
          isStartingTrial: trialBusy,
          entitlementError: auth.entitlementError.value,
          onOpenSettings: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsView()),
          ),
          onSignOut: authed ? auth.signOut : auth.openSignIn,
          signInLabel: authed
              ? 'Sign out'
              : (auth.isAuthenticating.value
                  ? 'Signing in…'
                  : (auth.isSolanaMobileDevice.value
                      ? 'Sign in with Seed Vault'
                      : 'Sign in')),
          authError: auth.authError.value,
        );
      }),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: _NavBar(index: _index, onTap: _go),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (icon: Icons.shield_outlined, active: Icons.shield, label: 'Connect'),
    (icon: Icons.language_outlined, active: Icons.language, label: 'Browse'),
    (icon: Icons.public_outlined, active: Icons.public, label: 'Servers'),
    (icon: Icons.person_outline, active: Icons.person, label: 'Account'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.lg),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.stroke),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_items.length, (i) {
          final it = _items[i];
          final active = i == index;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 10),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  gradient: active ? AppGradients.aurora : null,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(active ? it.active : it.icon, size: 20, color: active ? Colors.white : AppColors.textMuted),
                    if (active) ...[
                      const SizedBox(width: 6),
                      Text(it.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}