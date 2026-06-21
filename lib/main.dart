import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:reown_appkit/reown_appkit.dart';

import 'auth/deep_link_handler.dart';
import 'auth/wallet_auth_controller.dart';
import 'platform/desktop_shell.dart';
import 'platform/platform_capabilities.dart';
import 'theme/app_theme.dart';
import 'view/auth/reown_host.dart';
import 'view/bottombar/main_shell.dart';
import 'vpn/gateway_controller.dart';
import 'vpn/vpn_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DeepLinkHandler.initListener();
  if (PlatformCapabilities.isMobile) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  Get.put(VpnController(), permanent: true);
  final auth = WalletAuthController();
  Get.put(auth, permanent: true);
  await auth.detectDevice();
  await auth.loadPersistedSession();
  Get.put(GatewayController(), permanent: true);
  debugPrint(
    '[Erebrus] started — platform=${PlatformCapabilities.platformLabel} '
    'solanaMobile=${auth.isSolanaMobileDevice.value}, session restored',
  );
  runApp(ErebrusVpnApp(
    usesReown: auth.usesReown,
    useDesktopShell: PlatformCapabilities.supportsTray,
  ));
}

class ErebrusVpnApp extends StatelessWidget {
  const ErebrusVpnApp({
    super.key,
    required this.usesReown,
    required this.useDesktopShell,
  });

  final bool usesReown;
  final bool useDesktopShell;

  @override
  Widget build(BuildContext context) {
    final shell = usesReown ? const ReownHost(child: MainShell()) : const MainShell();
    final home = useDesktopShell ? DesktopShell(child: shell) : shell;

    final app = GetMaterialApp(
      title: 'Erebrus VPN',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: home,
    );

    if (!usesReown) return app;

    return ReownAppKitModalTheme(isDarkMode: true, child: app);
  }
}