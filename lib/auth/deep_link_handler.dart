import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'wallet_auth_controller.dart';

/// Forwards `erebrusvpn://` wallet callbacks into Reown AppKit.
class DeepLinkHandler {
  static const _methodChannel = MethodChannel('com.erebrus.vpn/methods');
  static const _eventChannel = EventChannel('com.erebrus.vpn/events');

  static WalletAuthController? _auth;

  static void initListener() {
    if (kIsWeb) return;
    try {
      _eventChannel.receiveBroadcastStream().listen(_onLink, onError: _onError);
    } catch (e) {
      debugPrint('[DeepLinkHandler] initListener $e');
    }
  }

  static void bind(WalletAuthController auth) {
    if (kIsWeb) return;
    _auth = auth;
  }

  static void checkInitialLink() {
    if (kIsWeb) return;
    try {
      _methodChannel.invokeMethod<void>('initialLink');
    } catch (e) {
      debugPrint('[DeepLinkHandler] checkInitialLink $e');
    }
  }

  static Future<void> _onLink(dynamic link) async {
    if (link == null) return;
    final url = link.toString();
    final modal = _auth?.appKitModal;
    if (modal == null) {
      debugPrint('[DeepLinkHandler] AppKit not ready for $url');
      return;
    }
    final handled = await modal.dispatchEnvelope(url);
    if (!handled) {
      debugPrint('[DeepLinkHandler] not handled: $url');
    }
  }

  static void _onError(dynamic error) {
    debugPrint('[DeepLinkHandler] $error');
  }
}