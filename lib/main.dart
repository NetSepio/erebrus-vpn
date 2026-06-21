import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:reown_appkit/reown_appkit.dart';

import 'auth/deep_link_handler.dart';
import 'auth/wallet_auth_controller.dart';
import 'theme/app_theme.dart';
import 'view/auth/reown_host.dart';
import 'view/bottombar/main_shell.dart';
import 'vpn/gateway_controller.dart';
import 'vpn/vpn_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  DeepLinkHandler.initListener();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  Get.put(VpnController(), permanent: true);
  Get.put(WalletAuthController(), permanent: true);
  Get.put(GatewayController(), permanent: true);
  debugPrint('[Erebrus] started — gateway + Reown controllers registered');
  runApp(const ErebrusVpnApp());
}

class ErebrusVpnApp extends StatelessWidget {
  const ErebrusVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ReownAppKitModalTheme(
      isDarkMode: true,
      child: GetMaterialApp(
        title: 'Erebrus VPN',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const ReownHost(child: MainShell()),
      ),
    );
  }
}