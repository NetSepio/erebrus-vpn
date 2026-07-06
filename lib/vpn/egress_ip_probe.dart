import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'vpn_models.dart';

/// Fetches the device's public egress IP through the tunnel when requested.
///
/// All endpoints are probed in parallel and the first plausible answer wins.
/// `1.1.1.1/cdn-cgi/trace` is first on purpose: it is an IP literal, so it
/// proves tunnel egress even when DNS through the tunnel is broken — the exact
/// failure mode of a half-up WireGuard endpoint.
class EgressIpProbe {
  static const _endpoints = [
    'https://1.1.1.1/cdn-cgi/trace',
    'https://api.ipify.org',
    'https://ifconfig.me/ip',
  ];

  static Future<String?> fetch({
    Duration timeout = const Duration(seconds: 8),
    bool useTunnelProxy = false,
  }) {
    final completer = Completer<String?>();
    var pending = _endpoints.length;
    for (final url in _endpoints) {
      unawaited(() async {
        String? ip;
        try {
          ip = await _get(url, timeout, useTunnelProxy: useTunnelProxy);
        } catch (e) {
          debugPrint('[VPN] egress probe $url failed: $e');
        }
        pending -= 1;
        if (ip != null && ip.isNotEmpty && _isPlausibleEgress(ip)) {
          if (!completer.isCompleted) completer.complete(ip);
        } else if (pending == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      }());
    }
    return completer.future;
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
      // One timeout over the whole attempt. Wrapping only `close()` (as before)
      // left the proxy CONNECT + TLS handshake inside `getUrl` unbounded, so a
      // dead tunnel turned a "5s" probe into ~10s.
      return await () async {
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set(HttpHeaders.userAgentHeader, 'ErebrusVPN/1.0');
        final res = await req.close();
        if (res.statusCode != 200) return null;
        final body = await res.transform(utf8.decoder).join();
        return _extractIp(url, body);
      }()
          .timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  /// `cdn-cgi/trace` returns `key=value` lines; the plain services return the IP.
  static String? _extractIp(String url, String body) {
    if (url.contains('cdn-cgi/trace')) {
      for (final line in const LineSplitter().convert(body)) {
        if (line.startsWith('ip=')) return line.substring(3).trim();
      }
      return null;
    }
    return body.trim();
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
