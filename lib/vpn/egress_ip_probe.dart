import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'vpn_models.dart';

/// Fetches the device's public egress IP through the tunnel when requested.
class EgressIpProbe {
  static const _endpoints = [
    'https://api.ipify.org',
    'https://ifconfig.me/ip',
  ];

  static Future<String?> fetch({
    Duration timeout = const Duration(seconds: 12),
    bool useTunnelProxy = false,
  }) async {
    for (final url in _endpoints) {
      try {
        final ip = await _get(
          url,
          timeout,
          useTunnelProxy: useTunnelProxy,
        );
        if (ip != null && ip.isNotEmpty && _isPlausibleEgress(ip)) return ip;
      } catch (e, st) {
        debugPrint('[VPN] egress probe $url failed: $e');
        debugPrint('$st');
        continue;
      }
    }
    return null;
  }

  static Future<String?> _get(
    String url,
    Duration timeout, {
    required bool useTunnelProxy,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    if (useTunnelProxy) {
      final proxy = '${SingboxConfigBuilder.localProxyHost}:${SingboxConfigBuilder.localProxyPort}';
      client.findProxy = (_) => 'PROXY $proxy';
    }
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'ErebrusVPN/1.0');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      return body.trim();
    } finally {
      client.close(force: true);
    }
  }

  /// Rejects TUN-internal and other non-public addresses.
  static bool _isPlausibleEgress(String ip) {
    if (ip.startsWith('172.19.')) return false;
    if (ip.startsWith('10.')) return false;
    if (ip.startsWith('192.168.')) return false;
    if (ip.startsWith('127.')) return false;
    if (ip.startsWith('169.254.')) return false;
    final parts = ip.split('.');
    if (parts.length == 4) {
      final first = int.tryParse(parts[0]);
      if (first == 172) {
        final second = int.tryParse(parts[1]);
        if (second != null && second >= 16 && second <= 31) return false;
      }
    }
    return true;
  }
}