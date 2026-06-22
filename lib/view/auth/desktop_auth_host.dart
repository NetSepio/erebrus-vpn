import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/wallet_auth_controller.dart';

/// Wires desktop browser sign-in and `erebrusvpn://auth` deep-link callbacks.
class DesktopAuthHost extends StatefulWidget {
  const DesktopAuthHost({super.key, required this.child});
  final Widget child;

  @override
  State<DesktopAuthHost> createState() => _DesktopAuthHostState();
}

class _DesktopAuthHostState extends State<DesktopAuthHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Get.find<WalletAuthController>().initDesktopAuth();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}