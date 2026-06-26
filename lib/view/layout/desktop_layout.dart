import '../../platform/platform_capabilities.dart';

/// How wide the scrollable content column may grow on desktop.
enum DesktopContentLayout {
  /// VPN connect and settings — phone-width column.
  standard,

  /// In-app browser — wider but still bounded.
  browser,
}

/// Breakpoints and width caps for desktop window layouts.
class DesktopLayout {
  DesktopLayout._();

  static const double railBreakpoint = 980;

  static const double standardMaxWidth = 520;
  static const double browserMaxWidth = 1180;
  static const double horizontalPadding = 40;

  static bool useSideRail(double windowWidth) {
    return PlatformCapabilities.isDesktop && windowWidth >= railBreakpoint;
  }

  static double contentMaxWidth({
    required double windowWidth,
    DesktopContentLayout layout = DesktopContentLayout.standard,
  }) {
    final cap = switch (layout) {
      DesktopContentLayout.standard => standardMaxWidth,
      DesktopContentLayout.browser => browserMaxWidth,
    };
    final padded = windowWidth - horizontalPadding;
    if (padded <= 0) {
      return cap;
    }
    return padded < cap ? padded : cap;
  }
}