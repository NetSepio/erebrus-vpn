import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/wallet_auth_controller.dart';
import '../../guest/guest_config_store.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../vpn/vpn_controller.dart';
import '../browser/browser_controller.dart';
import '../browser/browser_view.dart';
import '../guest/guest_connect_view.dart';
import '../home/connect_view.dart';
import '../home/diagnostics_sheet.dart';
import '../home/server_sheet.dart';
import '../layout/desktop_layout.dart';
import '../layout/desktop_screen.dart';
import '../settings/settings_view.dart';

/// The authenticated app shell: VPN / BROWSER / SETTINGS, with the design's
/// frosted bottom tab bar. The server picker and diagnostics open as sheets.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _autoConnectAttempted = false;
  Worker? _autoConnectWorker;
  late final List<Widget> _tabs;

  void _go(int i) {
    if (_index == i) return;
    setState(() => _index = i);
    if (Get.isRegistered<BrowserController>()) {
      Get.find<BrowserController>().setShellTabVisible(i == 1);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = [
      const DesktopScreen(child: _HomeTab()),
      const DesktopScreen(child: BrowserView()),
      const DesktopScreen(child: SettingsView()),
    ];
    _autoConnectWorker = everAll(
      [
        Get.find<AppSettingsController>().autoConnectOnLaunch,
        Get.find<WalletAuthController>().sessionReady,
        Get.find<WalletAuthController>().entitlement,
        Get.find<GuestConfigController>().selectedId,
        Get.find<VpnController>().selectedNode,
      ],
      (_) => _tryAutoConnect(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoConnect());
    if (Get.isRegistered<BrowserController>()) {
      Get.find<BrowserController>().setShellTabVisible(false);
    }
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
    final guest = Get.find<GuestConfigController>();
    if (vpn.isConnected) {
      _autoConnectAttempted = true;
      return;
    }
    if (!settings.autoConnectOnLaunch.value) return;
    if (vpn.isConnected || vpn.isBusy || vpn.killSwitchBlocking.value) return;

    if (auth.isAuthenticated) {
      if (!auth.sessionReady.value || !auth.canConnectVpn(vpn.selectedNode.value)) return;
      if (vpn.selectedNode.value == null) return;
      _autoConnectAttempted = true;
      vpn.connect();
    } else {
      final config = guest.selected;
      if (config == null) return;
      final node = config.toNode();
      vpn.selectNode(node);
      _autoConnectAttempted = true;
      vpn.connect(
        node: node,
        providedBundle: config.bundle,
        clientPrivateKey: config.clientPrivateKey,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final useSideRail = DesktopLayout.useSideRail(
      MediaQuery.sizeOf(context).width,
    );

    return Scaffold(
      extendBody: false,
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          if (useSideRail) ...[
            _DesktopNavRail(index: _index, onTap: _go),
            const VerticalDivider(width: 1, color: AppColors.stroke),
          ],
          Expanded(
            child: IndexedStack(index: _index, children: _tabs),
          ),
        ],
      ),
      bottomNavigationBar: useSideRail
          ? null
          : _NavBar(index: _index, onTap: _go),
    );
  }
}

/// Home tab router: stable widget so [MainShell] does not rebuild it on every
/// bottom-nav tap. Switches between authenticated and guest UIs reactively.
class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final auth = Get.find<WalletAuthController>();
      return auth.isAuthenticated
          ? ConnectView(
              onOpenServers: () => showServerSheet(context),
              onOpenDiagnostics: () => showDiagnosticsSheet(context),
              onGoSettings: () {
                final shell = context.findAncestorStateOfType<_MainShellState>();
                shell?._go(2);
              },
            )
          : const GuestConnectView();
    });
  }
}

class _DesktopNavRail extends StatelessWidget {
  const _DesktopNavRail({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (icon: Icons.shield, label: 'VPN'),
    (icon: Icons.explore, label: 'Browser'),
    (icon: Icons.tune, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: index,
      onDestinationSelected: onTap,
      labelType: NavigationRailLabelType.all,
      backgroundColor: AppColors.bg,
      indicatorColor: AppColors.accent.withValues(alpha: 0.18),
      selectedIconTheme: const IconThemeData(color: AppColors.accent),
      selectedLabelTextStyle: mono(
        size: 11,
        weight: FontWeight.w700,
        color: AppColors.accent,
      ),
      unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
      unselectedLabelTextStyle: mono(
        size: 11,
        weight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      destinations: [
        for (final item in _items)
          NavigationRailDestination(
            icon: Icon(item.icon),
            label: Text(item.label),
          ),
      ],
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (icon: Icons.shield, label: 'VPN'),
    (icon: Icons.explore, label: 'BROWSER'),
    (icon: Icons.tune, label: 'SETTINGS'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.only(top: 12, bottom: bottomInset > 0 ? bottomInset : 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0C).withValues(alpha: 0.94),
            border: const Border(top: BorderSide(color: AppColors.stroke)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              final it = _items[i];
              final active = i == index;
              final color = active ? AppColors.accent : AppColors.textSecondary;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(it.icon, size: 22, color: color),
                      const SizedBox(height: 5),
                      Text(it.label, style: mono(size: 10, weight: FontWeight.w500, color: color, letterSpacing: 10 * 0.05)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
