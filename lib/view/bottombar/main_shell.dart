import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/wallet_auth_controller.dart';
import '../../theme/app_theme.dart';
import '../../vpn/gateway_controller.dart';
import '../../vpn/vpn_models.dart';
import '../home/connect_view.dart';
import '../home/server_view.dart';
import '../profile/profile_view.dart';
import '../settings/settings_view.dart';

/// The v2 app shell: Connect / Servers / Account.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final gateway = Get.find<GatewayController>();
    final tabs = [
      ConnectView(onChooseNode: () => _go(1), onRequireAuth: () => _go(2)),
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
        return ProfileView(
          walletAddress: auth.walletAddress.value,
          planLabel: auth.isAuthenticated ? 'Member' : 'Free',
          entitlementSource: auth.isAuthenticated ? 'trial' : null,
          onManagePlan: auth.isAuthenticated ? null : auth.openWalletModal,
          onOpenSettings: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsView()),
          ),
          onSignOut: auth.isAuthenticated ? auth.signOut : auth.openWalletModal,
          signInLabel: auth.isAuthenticated
              ? 'Sign out'
              : (auth.isAuthenticating.value ? 'Signing in…' : 'Connect Solana wallet'),
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