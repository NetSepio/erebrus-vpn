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
    return 'Gateway error ($status)';
  }

  static Uri normalizeBase(String url) {
    final trimmed = url.trim();
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    return Uri.parse(withScheme);
  }
}