import 'dart:convert';
import 'dart:io';

import 'auth_config.dart';
import '../vpn/gateway_client.dart';

/// Wallet challenge + PASETO exchange against the Erebrus gateway (v2).
class GatewayAuthClient {
  GatewayAuthClient({String? gatewayUrl})
      : _base = GatewayClient(baseUrl: gatewayUrl).baseUrl;

  final String _base;

  Future<AuthChallenge> fetchFlowId({
    required String walletAddress,
    String chain = kSolanaChain,
  }) async {
    final uri = Uri.parse(
      '$_base/api/v2/auth/flowid?wallet_address=${Uri.encodeQueryComponent(walletAddress)}&chain=${Uri.encodeQueryComponent(chain)}',
    );
    final map = await _getJson(uri);
    return AuthChallenge(
      flowId: (map['flow_id'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
    );
  }

  Future<AuthSession> authenticate({
    required String flowId,
    required String signature,
    required String publicKey,
  }) async {
    final map = await _postJson(
      Uri.parse('$_base/api/v2/auth/authenticate'),
      {
        'flow_id': flowId,
        'signature': signature,
        'public_key': publicKey,
      },
    );
    return AuthSession(
      token: (map['token'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      role: (map['role'] ?? 'user').toString(),
      walletAddress: publicKey,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AuthException(_errorMessage(res.statusCode, text));
      }
      return Map<String, dynamic>.from(jsonDecode(text) as Map);
    } on SocketException catch (e) {
      throw AuthException('Cannot reach gateway ($_base): ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _postJson(Uri uri, Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      final encoded = jsonEncode(body);
      req.contentLength = utf8.encode(encoded).length;
      req.write(encoded);
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AuthException(_errorMessage(res.statusCode, text));
      }
      return Map<String, dynamic>.from(jsonDecode(text) as Map);
    } on SocketException catch (e) {
      throw AuthException('Cannot reach gateway ($_base): ${e.message}');
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
    return 'Authentication failed ($status)';
  }
}

class AuthChallenge {
  const AuthChallenge({required this.flowId, required this.message});
  final String flowId;
  final String message;
}

class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.role,
    required this.walletAddress,
  });
  final String token;
  final String userId;
  final String role;
  final String walletAddress;
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}