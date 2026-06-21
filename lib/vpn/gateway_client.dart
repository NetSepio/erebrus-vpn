import 'dart:convert';
import 'dart:io';

import 'vpn_models.dart';

/// Default Erebrus gateway for local / dev testing.
const kDefaultGatewayUrl = 'http://212.147.232.36:8080';

/// Last-known erebrus-nexus payload — used when the gateway registry is empty
/// but the node at :9080 is still running (dev / ops gap).
const kDevFallbackNodeJson = {
  'node_id': '59d52ecd-dfc3-41c2-90a4-0d2495a239e2',
  'name': 'erebrus-nexus',
  'did': 'did:erebrus:12D3KooWHqXFLdm2krcJ5ouyUMeBwfMCiEpKsSBhvJGm4u5tdeL5',
  'region': 'NO',
  'status': 'online',
  'protocols': ['wireguard', 'vless-reality', 'hysteria2'],
  'load_pct': 0.0,
};

/// Thin HTTP client for the Erebrus gateway discovery + provisioning APIs.
class GatewayClient {
  GatewayClient({String? baseUrl, String? bearerToken})
      : _base = _normalizeBase(baseUrl ?? kDefaultGatewayUrl),
        _bearerToken = bearerToken;

  final Uri _base;
  String? _bearerToken;

  void setBearerToken(String? token) => _bearerToken = token;

  String get baseUrl {
    final port = _base.hasPort ? ':${_base.port}' : '';
    return '${_base.scheme}://${_base.host}$port';
  }

  Future<List<VpnNode>> fetchNodes() async {
    final decoded = await _getJson('/api/v2/nodes');
    final list = decoded is List
        ? decoded
        : (decoded is Map ? (decoded['nodes'] as List?) : null) ?? const [];
    return list
        .map((e) => VpnNode.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((n) => n.id.isNotEmpty)
        .toList();
  }

  /// Shown when [fetchNodes] returns an empty registry (gateway up, no nodes).
  static List<VpnNode> devFallbackNodes() => [
        VpnNode.fromJson(kDevFallbackNodeJson),
      ];

  Future<CredentialBundle> provisionClient({
    required String nodeId,
    required String wgPublicKey,
    required String name,
  }) async {
    final decoded = await _postJson('/api/v2/vpn/clients', {
      'name': name,
      'node_id': nodeId,
      'wg_public_key': wgPublicKey,
    });
    return CredentialBundle.fromJson(_unwrapBundle(decoded));
  }

  static Map<String, dynamic> _unwrapBundle(dynamic decoded) {
    if (decoded is! Map) {
      throw GatewayException('Unexpected provision response shape');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map.containsKey('wireguard') || map.containsKey('singbox_profile')) return map;
    for (final key in const ['client', 'data', 'bundle', 'credentials']) {
      final nested = map[key];
      if (nested is Map) return Map<String, dynamic>.from(nested);
    }
    return map;
  }

  Future<dynamic> _getJson(String path) => _request('GET', path);

  Future<dynamic> _postJson(String path, Map<String, dynamic> body) =>
      _request('POST', path, body: body);

  Future<dynamic> _request(String method, String path, {Map<String, dynamic>? body}) async {
    final uri = _base.replace(path: '${_base.path}$path');
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (_bearerToken != null && _bearerToken!.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_bearerToken');
      }
      if (body != null) {
        final encoded = jsonEncode(body);
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        req.contentLength = utf8.encode(encoded).length;
        req.write(encoded);
      }
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw GatewayException(_errorMessage(res.statusCode, text));
      }
      if (text.isEmpty) return const {};
      return jsonDecode(text);
    } on SocketException catch (e) {
      throw GatewayException('Cannot reach gateway at $baseUrl (${e.message})');
    } on FormatException {
      throw GatewayException('Gateway returned invalid JSON');
    } finally {
      client.close(force: true);
    }
  }

  static String _errorMessage(int status, String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final msg = j['error'] ?? j['message'] ?? j['detail'];
        if (msg != null) return msg.toString();
      }
    } catch (_) {}
    return 'Gateway error ($status)';
  }

  static Uri _normalizeBase(String url) {
    final trimmed = url.trim();
    final withScheme =
        trimmed.contains('://') ? trimmed : 'http://$trimmed';
    return Uri.parse(withScheme);
  }
}

class GatewayException implements Exception {
  GatewayException(this.message);
  final String message;
  @override
  String toString() => message;
}