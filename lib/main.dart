import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'theme/app_theme.dart';
import 'view/bottombar/main_shell.dart';
import 'vpn/vpn_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // The single VPN engine controller lives for the app's lifetime.
  Get.put(VpnController(), permanent: true);
  runApp(const ErebrusVpnApp());
}

class ErebrusVpnApp extends StatelessWidget {
  const ErebrusVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Erebrus VPN',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const MainShell(),
    );
  }
}
