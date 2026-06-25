import 'dart:convert';
import 'dart:io';

import 'auth_config.dart';
import 'entitlement_state.dart';
import 'user_profile.dart';
import '../vpn/gateway_config.dart';
import '../vpn/gateway_http.dart';

/// Wallet auth + subscriptions against the Erebrus gateway (v2).
class GatewayAuthClient {
  GatewayAuthClient({String? gatewayUrl})
      : _base = GatewayHttp.normalizeBase(gatewayUrl ?? kGatewayUrl);

  final Uri _base;

  String get baseUrl {
    final port = _base.hasPort ? ':${_base.port}' : '';
    return '${_base.scheme}://${_base.host}$port';
  }

  /// Start wallet login — `GET /api/v2/auth`.
  Future<AuthChallenge> fetchAuthChallenge({
    required String walletAddress,
    String chain = kSolanaChain,
  }) async {
    final uri = _base.replace(
      path: '${_base.path}/api/v2/auth',
      queryParameters: {
        'wallet_address': walletAddress,
        'chain': chain,
      },
    );
    final map = await _getJson(uri);
    return AuthChallenge(
      challengeId: (map['flow_id'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
    );
  }

  /// Complete wallet login — `POST /api/v2/auth`.
  Future<AuthSession> authenticate({
    required String challengeId,
    required String signature,
    required String publicKey,
    String? referralCode,
  }) async {
    final body = <String, dynamic>{
      'flow_id': challengeId,
      'signature': signature,
      'public_key': publicKey,
    };
    final ref = referralCode?.trim();
    if (ref != null && ref.isNotEmpty) {
      body['ref'] = ref;
    }
    final map = await _postJson(
      _base.replace(path: '${_base.path}/api/v2/auth'),
      body,
    );
    return AuthSession(
      token: (map['token'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      role: (map['role'] ?? 'user').toString(),
      walletAddress: publicKey,
    );
  }

  /// `GET /api/v2/subscriptions` — requires bearer token.
  Future<EntitlementState> fetchSubscription(String bearerToken) async {
    final map = await _getJson(
      _base.replace(path: '${_base.path}/api/v2/subscriptions'),
      bearerToken: bearerToken,
    );
    return EntitlementState.fromJson(map);
  }

  /// `POST /api/v2/subscriptions/trial` — one-time free trial (7 days on pro).
  Future<EntitlementState> startTrial(String bearerToken) async {
    final map = await _postJson(
      _base.replace(path: '${_base.path}/api/v2/subscriptions/trial'),
      const {},
      bearerToken: bearerToken,
    );
    return EntitlementState.fromJson({
      'entitled': true,
      'status': map['status'],
      'plan_id': map['plan_id'],
      'source': map['source'] ?? 'trial',
      'current_period_end': map['current_period_end'],
      'trial_consumed': true,
    });
  }

  /// `GET /api/v2/account/profile`
  Future<UserProfile> fetchProfile(String bearerToken) async {
    final map = await _getJson(
      _base.replace(path: '${_base.path}/api/v2/account/profile'),
      bearerToken: bearerToken,
    );
    return UserProfile.fromJson(map);
  }

  /// `PATCH /api/v2/account/profile` — updates display name only.
  Future<UserProfile> patchProfile(String bearerToken, {required String name}) async {
    final map = await _patchJson(
      _base.replace(path: '${_base.path}/api/v2/account/profile'),
      {'name': name},
      bearerToken: bearerToken,
    );
    return UserProfile.fromJson(map);
  }

  /// `POST /api/v2/auth/email` — send OTP to link a recovery email.
  Future<void> startEmailLink(String bearerToken, String email) async {
    await _postJson(
      _base.replace(path: '${_base.path}/api/v2/auth/email'),
      {'email': email.trim()},
      bearerToken: bearerToken,
    );
  }

  /// `POST /api/v2/auth/email/verify` — verify OTP and link email.
  Future<UserProfile> verifyEmailLink(
    String bearerToken, {
    required String email,
    required String code,
  }) async {
    final map = await _postJson(
      _base.replace(path: '${_base.path}/api/v2/auth/email/verify'),
      {'email': email.trim(), 'code': code.trim()},
      bearerToken: bearerToken,
    );
    return UserProfile.fromJson(map);
  }

  /// `POST /api/v2/subscriptions/nft/refresh` — verify gating NFT, grant ~30d.
  Future<EntitlementState> refreshNftEntitlement(String bearerToken) async {
    final map = await _postJson(
      _base.replace(path: '${_base.path}/api/v2/subscriptions/nft/refresh'),
      const {},
      bearerToken: bearerToken,
    );
    return EntitlementState.fromJson({
      'entitled': true,
      'status': map['status'] ?? 'active',
      'plan_id': map['plan_id'],
      'source': map['source'] ?? 'nft',
      'current_period_end': map['current_period_end'],
      'trial_consumed': map['trial_consumed'],
      'nft_gating': true,
    });
  }

  Future<Map<String, dynamic>> _getJson(Uri uri, {String? bearerToken}) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      GatewayHttp.applyHeaders(req, bearerToken: bearerToken);
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AuthException(GatewayHttp.errorMessage(res.statusCode, text));
      }
      return Map<String, dynamic>.from(jsonDecode(text) as Map);
    } on SocketException catch (e) {
      throw AuthException('Cannot reach gateway ($baseUrl): ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _patchJson(
    Uri uri,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.patchUrl(uri);
      GatewayHttp.applyHeaders(req, bearerToken: bearerToken, jsonBody: true);
      final encoded = jsonEncode(body);
      req.contentLength = utf8.encode(encoded).length;
      req.write(encoded);
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AuthException(GatewayHttp.errorMessage(res.statusCode, text));
      }
      if (text.isEmpty) return const {};
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return const {};
    } on SocketException catch (e) {
      throw AuthException('Cannot reach gateway ($baseUrl): ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      GatewayHttp.applyHeaders(req, bearerToken: bearerToken, jsonBody: true);
      final encoded = jsonEncode(body);
      req.contentLength = utf8.encode(encoded).length;
      req.write(encoded);
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AuthException(GatewayHttp.errorMessage(res.statusCode, text));
      }
      if (text.isEmpty) return const {};
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return const {};
    } on SocketException catch (e) {
      throw AuthException('Cannot reach gateway ($baseUrl): ${e.message}');
    } finally {
      client.close(force: true);
    }
  }
}

class AuthChallenge {
  const AuthChallenge({required this.challengeId, required this.message});
  final String challengeId;
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