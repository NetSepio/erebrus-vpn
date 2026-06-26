import 'dart:io';

import 'package:flutter/foundation.dart';

/// Routes Windows user HTTP/HTTPS traffic through the local sing-box mixed inbound.
class WindowsSystemProxy {
  WindowsSystemProxy._();

  static const _regPath = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  static Future<void> enable({
    String host = '127.0.0.1',
    int port = 10808,
  }) async {
    if (!Platform.isWindows) return;
    final server = 'http=$host:$port;https=$host:$port;socks=$host:$port';
    try {
      await _reg('ProxyEnable', 'REG_DWORD', '1');
      await _reg('ProxyServer', 'REG_SZ', server);
      await _reg('ProxyOverride', 'REG_SZ', '<local>');
      debugPrint('[Windows] system proxy enabled → $host:$port');
    } catch (e) {
      debugPrint('[Windows] system proxy enable failed: $e');
    }
  }

  static Future<void> disable() async {
    if (!Platform.isWindows) return;
    try {
      await _reg('ProxyEnable', 'REG_DWORD', '0');
      debugPrint('[Windows] system proxy disabled');
    } catch (e) {
      debugPrint('[Windows] system proxy disable failed: $e');
    }
  }

  static Future<void> _reg(String name, String type, String value) async {
    final r = await Process.run('reg', ['add', _regPath, '/v', name, '/t', type, '/d', value, '/f']);
    if (r.exitCode != 0) {
      throw StateError('reg add $name failed: ${r.stderr}');
    }
  }
}