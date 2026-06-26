import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'gateway_config.dart';

/// Shared HTTP helpers for gateway discovery, VPN, and auth clients.
abstract final class GatewayHttp {
  static const _connectTimeout = Duration(seconds: 12);
  static const _lookupRetries = 3;
  static const _lookupRetryDelay = Duration(milliseconds: 350);

  /// Gateway [HttpClient] — DNS preflight only (do not use [HttpClient.connectionFactory]
  /// for HTTPS here; it breaks SNI and the gateway returns 404).
  static HttpClient createClient() {
    final client = HttpClient();
    client.connectionTimeout = _connectTimeout;
    client.idleTimeout = const Duration(seconds: 15);
    return client;
  }

  /// Warm system DNS before HTTPS — retries help on cold-start Android / Seeker.
  static Future<void> preflightHost(String host) async {
    if (host.isEmpty || InternetAddress.tryParse(host) != null) return;
    await resolveHost(host);
  }

  /// System DNS with backoff, then Google DNS-over-HTTPS (lookup only).
  static Future<List<InternetAddress>> resolveHost(String host) async {
    Object? lastError;
    for (var attempt = 0; attempt < _lookupRetries; attempt++) {
      try {
        final result = await InternetAddress.lookup(
          host,
          type: InternetAddressType.IPv4,
        ).timeout(const Duration(seconds: 6));
        if (result.isNotEmpty) return result;
      } catch (e) {
        lastError = e;
        if (attempt < _lookupRetries - 1) {
          await Future<void>.delayed(_lookupRetryDelay * (attempt + 1));
        }
      }
    }

    try {
      final viaDoh = await _resolveViaDoh(host);
      debugPrint('[Gateway] DNS fallback (DoH) resolved $host → ${viaDoh.first.address}');
      return viaDoh;
    } catch (e) {
      throw lastError ?? e;
    }
  }

  static Future<List<InternetAddress>> _resolveViaDoh(String host) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(
        Uri.https('dns.google', '/resolve', {'name': host, 'type': 'A'}),
      );
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw SocketException('DoH lookup failed (HTTP ${res.statusCode})');
      }
      final body = await utf8.decodeStream(res);
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException('DoH response');
      final answers = decoded['Answer'];
      if (answers is! List || answers.isEmpty) {
        throw SocketException('DoH returned no records for $host');
      }
      final out = <InternetAddress>[];
      for (final a in answers) {
        if (a is Map && a['type'] == 1) {
          final data = a['data']?.toString();
          if (data != null && data.isNotEmpty) {
            out.add(InternetAddress(data));
          }
        }
      }
      if (out.isEmpty) throw SocketException('DoH returned no IPv4 for $host');
      return out;
    } finally {
      client.close(force: true);
    }
  }

  static bool isTransientNetworkError(Object error) {
    if (error is! SocketException) return error is TimeoutException;
    final m = error.message.toLowerCase();
    return m.contains('failed host lookup') ||
        m.contains('no address associated') ||
        m.contains('network is unreachable') ||
        m.contains('connection timed out') ||
        m.contains('connection reset');
  }

  static void applyHeaders(
    HttpClientRequest req, {
    String? bearerToken,
    bool jsonBody = false,
  }) {
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set('X-Erebrus-Client', gatewayClientHeader());
    if (bearerToken != null && bearerToken.isNotEmpty) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    }
    if (jsonBody) {
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    }
  }

  static String errorMessage(int status, String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final msg = j['error'] ?? j['message'] ?? j['detail'];
        if (msg != null) return msg.toString();
      }
    } catch (_) {}
    return switch (status) {
      404 => 'Gateway registry not found (404)',
      401 => 'Gateway authentication failed (401)',
      403 => 'Gateway access denied (403)',
      _ => 'Gateway error ($status)',
    };
  }

  static Uri normalizeBase(String url) {
    final trimmed = url.trim();
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.parse(withScheme);
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.isEmpty || path == '/') {
      return uri.replace(path: '', query: null, fragment: null);
    }
    return uri.replace(path: path, query: null, fragment: null);
  }

  static Uri apiUri(
    Uri base, {
    required String path,
    Map<String, String>? query,
  }) {
    final segment = path.startsWith('/') ? path : '/$path';
    final root = base.path.isEmpty || base.path == '/' ? '' : base.path.replaceAll(RegExp(r'/+$'), '');
    return base.replace(path: '$root$segment', queryParameters: query);
  }
}