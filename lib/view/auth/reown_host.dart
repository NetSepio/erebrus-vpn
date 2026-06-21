import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../auth/wallet_auth_controller.dart';

/// Initializes Reown AppKit once a [BuildContext] is available.
class ReownHost extends StatefulWidget {
  const ReownHost({super.key, required this.child});
  final Widget child;

  @override
  State<ReownHost> createState() => _ReownHostState();
}

class _ReownHostState extends State<ReownHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = Get.find<WalletAuthController>();
      if (!auth.usesReown) return;
      await auth.initReown(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}