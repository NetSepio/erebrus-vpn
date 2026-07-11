import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'vpn_models.dart';

/// Fetches the device's public egress IP through the tunnel when requested.
///
/// A randomized subset of endpoints is probed in parallel and the first
/// plausible answer wins. The `1.1.1.1` IP literal is always included so it
/// proves tunnel egress even when DNS through the tunnel is broken — the exact
/// failure mode of a half-up WireGuard endpoint.
class EgressIpProbe {
  /// Always include this IP literal as a DNS-dead fallback.
  static const _ipLiteralEndpoint = 'https://1.1.1.1/cdn-cgi/trace';

  static const _hostEndpoints = [
    'https://api.ipify.org',
    'https://api64.ipify.org',
    'https://icanhazip.com',
    'https://ident.me',
    'https://ipinfo.io/ip',
    'https://checkip.amazonaws.com',
    'https://ifconfig.me/ip',
    'https://www.cloudflare.com/cdn-cgi/trace',
    'https://ipecho.net/plain',
  ];

  static final _rng = Random.secure();

  static const _genericUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static Future<String?> fetch({
    Duration timeout = const Duration(seconds: 8),
    bool useTunnelProxy = false,
  }) {
    // Always include the IP literal, plus a randomized sample of hostnames.
    final hostPool = List<String>.of(_hostEndpoints)..shuffle(_rng);
    final endpoints = [
      _ipLiteralEndpoint,
      ...hostPool.take(3),
    ];

    final completer = Completer<String?>();
    var pending = endpoints.length;
    for (final url in endpoints) {
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
        req.headers.set(HttpHeaders.userAgentHeader, _genericUserAgent);
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
