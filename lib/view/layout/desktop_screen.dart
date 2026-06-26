import 'package:flutter/material.dart';

import '../../platform/platform_capabilities.dart';
import 'desktop_layout.dart';

/// Centers tab content on wide desktop windows with a bounded max width.
class DesktopScreen extends StatelessWidget {
  const DesktopScreen({
    super.key,
    required this.child,
    this.layout = DesktopContentLayout.standard,
  });

  final Widget child;
  final DesktopContentLayout layout;

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.isDesktop) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = DesktopLayout.contentMaxWidth(
          windowWidth: constraints.maxWidth,
          layout: layout,
        );
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}