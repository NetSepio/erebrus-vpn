import 'dart:convert';
import 'dart:io';

import 'gateway_config.dart';

/// Shared HTTP helpers for gateway discovery, VPN, and auth clients.
abstract final class GatewayHttp {
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
    // Strip trailing path segments so API paths are not doubled (e.g. /api + /api/v2/…).
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.isEmpty || path == '/') {
      return uri.replace(path: '', query: null, fragment: null);
    }
    return uri.replace(path: path, query: null, fragment: null);
  }

  /// Joins [base] with an API path like `/api/v2/nodes` without `//` or doubled prefixes.
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