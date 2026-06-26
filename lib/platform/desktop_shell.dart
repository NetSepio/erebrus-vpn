import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../auth/wallet_auth_controller.dart';
import '../vpn/singbox_engine.dart';
import '../vpn/vpn_controller.dart';
import '../vpn/vpn_models.dart';
import 'desktop_system_proxy.dart';
import 'platform_capabilities.dart';

/// Menu bar / system tray wrapper for macOS, Windows, and Linux.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> with TrayListener, WindowListener {
  @override
  void initState() {
    super.initState();
    if (!PlatformCapabilities.supportsTray) return;
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initDesktop();
  }

  Future<void> _initDesktop() async {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(420, 780),
      minimumSize: Size(380, 640),
      center: true,
      title: 'Erebrus VPN',
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);

    await trayManager.setIcon('assets/icons/tray_icon.png');
    await _syncTrayMenu();
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'connect':
        _toggleConnection();
      case 'open':
        windowManager.show();
        windowManager.focus();
      case 'minimize':
        windowManager.hide();
      case 'quit':
        _quit();
    }
  }

  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  void onWindowMinimize() {
    windowManager.hide();
  }

  Future<void> _toggleConnection() async {
    if (!Get.isRegistered<VpnController>()) return;
    final vpn = Get.find<VpnController>();
    if (vpn.isBusy) return;
    final auth = Get.isRegistered<WalletAuthController>()
        ? Get.find<WalletAuthController>()
        : null;
    if (auth != null && !auth.isAuthenticated) {
      await windowManager.show();
      await auth.openSignIn();
      return;
    }
    await vpn.toggle();
    await _syncTrayMenu();
  }

  Future<void> _quit() async {
    if (Get.isRegistered<VpnController>()) {
      final vpn = Get.find<VpnController>();
      if (vpn.isConnected) await vpn.disconnect();
    }
    await DesktopSystemProxy.disable();
    await trayManager.destroy();
    await windowManager.destroy();
  }

  Future<void> _syncTrayMenu() async {
    if (!Get.isRegistered<VpnController>()) return;
    final vpn = Get.find<VpnController>();
    final stage = vpn.stage.value;
    final transport = vpn.activeTransport.value?.label;
    final statusLabel = switch (stage) {
      VpnStage.connected => 'Connected${transport != null ? ' · $transport' : ''}',
      VpnStage.connecting => 'Connecting…',
      VpnStage.disconnecting => 'Disconnecting…',
      VpnStage.error => 'Error',
      _ => 'Disconnected',
    };
    final actionLabel = stage == VpnStage.connected ? 'Disconnect' : 'Connect';

    await trayManager.setToolTip('Erebrus VPN — $statusLabel');
    await trayManager.setContextMenu(Menu(
      items: [
        MenuItem(key: 'status', label: statusLabel, disabled: true),
        MenuItem.separator(),
        MenuItem(key: 'connect', label: actionLabel),
        MenuItem(key: 'open', label: 'Open dashboard'),
        MenuItem(key: 'minimize', label: 'Minimize to tray'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit Erebrus'),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.supportsTray) return widget.child;

    return Obx(() {
      if (Get.isRegistered<VpnController>()) {
        Get.find<VpnController>().stage.value;
        Get.find<VpnController>().activeTransport.value;
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncTrayMenu());
      }
      return widget.child;
    });
  }
}