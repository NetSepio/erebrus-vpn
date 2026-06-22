import 'dart:io';

import 'package:flutter/foundation.dart';

/// Routes macOS system HTTP/HTTPS/SOCKS traffic through the local sing-box mixed inbound.
class MacosSystemProxy {
  MacosSystemProxy._();

  static const _fallbackServices = [
    'Wi-Fi',
    'Ethernet',
    'USB Ethernet',
    'Thunderbolt Ethernet',
  ];

  /// All enabled network services from `networksetup -listallnetworkservices`.
  static Future<List<String>> discoverNetworkServices() async {
    try {
      final r = await Process.run('networksetup', ['-listallnetworkservices']);
      if (r.exitCode != 0) return List<String>.from(_fallbackServices);
      final services = (r.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('*'))
          .toList();
      return services.isEmpty ? List<String>.from(_fallbackServices) : services;
    } catch (e) {
      debugPrint('[macOS] listallnetworkservices failed: $e');
      return List<String>.from(_fallbackServices);
    }
  }

  static Future<void> enable({
    String host = '127.0.0.1',
    int port = 10808,
  }) async {
    if (!Platform.isMacOS) return;
    final services = await discoverNetworkServices();
    var enabled = 0;
    for (final service in services) {
      if (await _setProxy(service, host, port, enabled: true)) {
        enabled++;
        debugPrint('[macOS] system proxy enabled on "$service" → $host:$port');
      }
    }
    if (enabled == 0) {
      debugPrint(
        '[macOS] could not enable system proxy — check System Settings → Network '
        '(services: ${services.join(", ")})',
      );
    }
  }

  static Future<void> disable() async {
    if (!Platform.isMacOS) return;
    final services = await discoverNetworkServices();
    for (final service in services) {
      await _setProxy(service, '127.0.0.1', 10808, enabled: false);
    }
    debugPrint('[macOS] system HTTP/SOCKS proxy disabled');
  }

  static Future<bool> _setProxy(
    String service,
    String host,
    int port, {
    required bool enabled,
  }) async {
    try {
      if (enabled) {
        final web = await Process.run('networksetup', [
          '-setwebproxy',
          service,
          host,
          '$port',
        ]);
        final secure = await Process.run('networksetup', [
          '-setsecurewebproxy',
          service,
          host,
          '$port',
        ]);
        final socks = await Process.run('networksetup', [
          '-setsocksfirewallproxy',
          service,
          host,
          '$port',
        ]);
        if (web.exitCode != 0 || secure.exitCode != 0 || socks.exitCode != 0) {
          return false;
        }
        await Process.run('networksetup', ['-setwebproxystate', service, 'on']);
        await Process.run('networksetup', ['-setsecurewebproxystate', service, 'on']);
        await Process.run('networksetup', ['-setsocksfirewallproxystate', service, 'on']);
      } else {
        await Process.run('networksetup', ['-setwebproxystate', service, 'off']);
        await Process.run('networksetup', ['-setsecurewebproxystate', service, 'off']);
        await Process.run('networksetup', ['-setsocksfirewallproxystate', service, 'off']);
      }
      return true;
    } catch (e) {
      debugPrint('[macOS] networksetup "$service" failed: $e');
      return false;
    }
  }
}