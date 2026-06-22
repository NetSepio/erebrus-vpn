import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Runtime platform flags for auth routing and desktop shell behaviour.
class PlatformCapabilities {
  const PlatformCapabilities._();

  static bool get isWeb => kIsWeb;

  static bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  /// Menu bar / system tray quick controls (macOS, Windows, Linux).
  static bool get supportsTray => isDesktop;

  /// Solana Mobile Wallet Adapter — set after [detectSolanaMobileDevice].
  static bool isSolanaMobileDevice = false;

  /// Reown AppKit — Android / iOS only (not desktop, not Solana Mobile).
  static bool get usesReown => isMobile && !isSolanaMobileDevice;

  /// Browser sign-in via erebrus.io → PASETO callback (macOS / Windows / Linux).
  static bool get usesWebLogin => isDesktop;

  /// Short hint for the connect orb when the user is not signed in.
  static String get walletSignInHint {
    if (isSolanaMobileDevice) {
      return 'Sign in with Seed Vault in Account first';
    }
    if (isDesktop) return 'Sign in with your browser in Account first';
    return 'Connect your Solana wallet in Account first';
  }

  static String get platformLabel {
    if (kIsWeb) return 'web';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return defaultTargetPlatform.name;
  }
}