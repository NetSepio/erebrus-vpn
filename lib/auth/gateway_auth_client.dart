import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'auth_config.dart';
import 'entitlement_state.dart';
import 'referral_summary.dart';
import 'user_profile.dart';
import 'user_org_invite.dart';
import '../vpn/gateway_config.dart';
import '../vpn/gateway_http.dart';
import '../vpn/vpn_models.dart';

export 'user_org_invite.dart';

/// Wallet auth + subscriptions against the Erebrus gateway (v2).
class GatewayAuthClient {
  GatewayAuthClient({String? gatewayUrl})
    : _base = GatewayHttp.normalizeBase(gatewayUrl ?? resolveGatewayUrl());

  static const _requestTimeout = Duration(seconds: 20);

  final Uri _base;

  String get baseUrl {
    final port = _base.hasPort ? ':${_base.port}' : '';
    return '${_base.scheme}://${_base.host}$port';
  }

  /// Quick DNS + HTTP probe before wallet sign-in (avoids failing mid-MWA).
  Future<void> checkReachability() async {
    final uri = GatewayHttp.apiUri(_base, path: '/healthz');
    await GatewayHttp.preflightHost(uri.host);
    final client = GatewayHttp.createClient();
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AuthException(
          'Gateway unreachable at $baseUrl (HTTP ${res.statusCode})',
        );
      }
      await res.drain();
    } on SocketException catch (e) {
      throw AuthException(_networkErrorMessage(e.message, gateway: baseUrl));
    } on IOException catch (e) {
      throw AuthException(_networkErrorMessage(e.toString(), gateway: baseUrl));
    } finally {
      client.close(force: true);
    }
  }

  static String _networkErrorMessage(
    String? detail, {
    required String gateway,
  }) {
    final d = (detail ?? '').toLowerCase();
    if (d.contains('failed host lookup') ||
        d.contains('no address associated')) {
      return 'No internet or DNS cannot resolve the gateway ($gateway). '
          'Check Wi‑Fi/mobile data, turn off Private DNS temporarily, and retry.';
    }
    if (d.contains('network is unreachable') ||
        d.contains('connection refused')) {
      return 'Cannot reach the gateway ($gateway). Check your network connection.';
    }
    return 'Cannot reach gateway ($gateway)${detail == null || detail.isEmpty ? '' : ': $detail'}';
  }

  /// Start wallet login — `GET /api/v2/auth`.
  Future<AuthChallenge> fetchAuthChallenge({
    required String walletAddress,
    String chain = kSolanaChain,
  }) async {
    final uri = GatewayHttp.apiUri(
      _base,
      path: '/api/v2/auth',
      query: {'wallet_address': walletAddress, 'chain': chain},
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
      GatewayHttp.apiUri(_base, path: '/api/v2/auth'),
      body,
    );
    return AuthSession(
      token: (map['token'] ?? '').toString(),
      userId: (map['user_id'] ?? '').toString(),
      role: (map['role'] ?? 'user').toString(),
      walletAddress: publicKey,
    );
  }

  /// `GET /api/v2/auth/methods` — which login methods the gateway has configured.
  Future<AuthMethods> fetchAuthMethods() async {
    final map = await _getJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/auth/methods'),
    );
    return AuthMethods(
      wallet: map['wallet'] != false,
      email: map['email'] == true,
      google: map['google'] == true,
      apple: map['apple'] == true,
    );
  }

  /// `POST /api/v2/auth/email/login/start` — send a login code to the email.
  Future<void> emailLoginStart(String email) async {
    await _postJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/auth/email/login/start'),
      {'email': email},
    );
  }

  /// `POST /api/v2/auth/email/login/verify` — verify the code, get a session.
  Future<AuthSession> emailLoginVerify({
    required String email,
    required String code,
  }) async {
    final normalizedCode = code.replaceAll(RegExp(r'\D'), '');
    final map = await _postJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/auth/email/login/verify'),
      {'email': email.trim(), 'code': normalizedCode},
    );
    return _identitySession(map);
  }

  /// `POST /api/v2/auth/google` — exchange a Google id_token for a session.
  Future<AuthSession> googleLogin(String idToken) async {
    final map = await _postJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/auth/google'),
      {'id_token': idToken},
    );
    return _identitySession(map);
  }

  /// `POST /api/v2/auth/apple` — exchange the complete Apple credential.
  Future<AuthSession> appleLogin({
    required String idToken,
    required String authorizationCode,
    required String nonce,
    required String state,
  }) async {
    final map = await _postJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/auth/apple'),
      appleLoginPayload(
        idToken: idToken,
        authorizationCode: authorizationCode,
        nonce: nonce,
        state: state,
      ),
    );
    return _identitySession(map);
  }

  static Map<String, String> appleLoginPayload({
    required String idToken,
    required String authorizationCode,
    required String nonce,
    required String state,
  }) => {
    'id_token': idToken,
    'authorization_code': authorizationCode,
    'nonce': nonce,
    'state': state,
  };

  AuthSession _identitySession(Map<String, dynamic> map) => AuthSession(
    token: (map['token'] ?? '').toString(),
    userId: (map['user_id'] ?? '').toString(),
    role: (map['role'] ?? 'user').toString(),
    walletAddress: '',
  );

  /// `GET /api/v2/subscriptions` — requires bearer token.
  Future<EntitlementState> fetchSubscription(String bearerToken) async {
    final map = await _getJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/subscriptions'),
      bearerToken: bearerToken,
    );
    return EntitlementState.fromJson(map);
  }

  /// `POST /api/v2/subscriptions/trial` — one-time free trial (7 days on pro).
  Future<EntitlementState> startTrial(String bearerToken) async {
    final map = await _postJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/subscriptions/trial'),
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
      GatewayHttp.apiUri(_base, path: '/api/v2/account/profile'),
      bearerToken: bearerToken,
    );
    return UserProfile.fromJson(map);
  }

  /// `PATCH /api/v2/account/profile` — updates display name only.
  Future<UserProfile> patchProfile(
    String bearerToken, {
    required String name,
  }) async {
    final map = await _patchJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/account/profile'),
      {'name': name},
      bearerToken: bearerToken,
    );
    return UserProfile.fromJson(map);
  }

  /// `GET /api/v2/referrals/me` — my invite code, referrer, recent referees.
  Future<ReferralSummary> fetchReferrals(String bearerToken) async {
    final map = await _getJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/referrals/me'),
      bearerToken: bearerToken,
    );
    return ReferralSummary.fromJson(map);
  }

  /// `POST /api/v2/referrals/redeem` — apply an invite code (one referrer,
  /// ever). Returns the refreshed summary, or null on the gateway's minimal
  /// `{bound:true}` fallback — refetch in that case.
  Future<ReferralSummary?> redeemReferralCode(
    String bearerToken,
    String code,
  ) async {
    final map = await _postJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/referrals/redeem'),
      {'code': code.trim().toUpperCase()},
      bearerToken: bearerToken,
    );
    if ((map['code'] ?? '').toString().isEmpty) return null;
    return ReferralSummary.fromJson(map);
  }

  /// `POST /api/v2/auth/email` — send OTP to link a recovery email.
  Future<void> startEmailLink(String bearerToken, String email) async {
    await _postJson(GatewayHttp.apiUri(_base, path: '/api/v2/auth/email'), {
      'email': email.trim(),
    }, bearerToken: bearerToken);
  }

  /// `POST /api/v2/auth/email/verify` — verify OTP and link email.
  Future<UserProfile> verifyEmailLink(
    String bearerToken, {
    required String email,
    required String code,
  }) async {
    final map = await _postJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/auth/email/verify'),
      {'email': email.trim(), 'code': code.trim()},
      bearerToken: bearerToken,
    );
    return UserProfile.fromJson(map);
  }

  /// `POST /api/v2/subscriptions/nft/refresh` — verify gating NFT, grant ~30d.
  Future<EntitlementState> refreshNftEntitlement(String bearerToken) async {
    final map = await _postJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/subscriptions/nft/refresh'),
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

  /// `POST /api/v2/account/deletion-request` — request account deletion.
  Future<String> requestAccountDeletion(String bearerToken) async {
    final map = await _postJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/account/deletion-request'),
      const {},
      bearerToken: bearerToken,
    );
    return (map['message'] ?? 'Deletion request submitted').toString();
  }

  /// `GET /api/v2/account/org-invites` — pending organization invites.
  Future<List<UserOrgInvite>> fetchAccountOrgInvites(String bearerToken) async {
    final decoded = await _getDecoded(
      GatewayHttp.apiUri(_base, path: '/api/v2/account/org-invites'),
      bearerToken: bearerToken,
    );
    final list = decoded is List
        ? decoded
        : (decoded is Map ? (decoded['invites'] as List?) : null) ?? const [];
    return list
        .map((e) => UserOrgInvite.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// `POST /api/v2/account/org-invites/:orgId/accept`.
  Future<void> acceptAccountOrgInvite(String bearerToken, String orgId) async {
    await _postJson(
      GatewayHttp.apiUri(
        _base,
        path: '/api/v2/account/org-invites/$orgId/accept',
      ),
      const {},
      bearerToken: bearerToken,
    );
  }

  /// `POST /api/v2/account/org-invites/:orgId/decline`.
  Future<void> declineAccountOrgInvite(String bearerToken, String orgId) async {
    await _postJson(
      GatewayHttp.apiUri(
        _base,
        path: '/api/v2/account/org-invites/$orgId/decline',
      ),
      const {},
      bearerToken: bearerToken,
    );
  }

  /// `POST /api/v2/orgs` — create a new organization.
  Future<VpnOrg> createOrg(
    String bearerToken, {
    required String name,
    required String slug,
  }) async {
    final map = await _postJson(
      GatewayHttp.apiUri(_base, path: '/api/v2/orgs'),
      {'name': name.trim(), 'slug': slug.trim().toLowerCase()},
      bearerToken: bearerToken,
    );
    return VpnOrg.fromJson(map);
  }

  Future<dynamic> _getDecoded(Uri uri, {String? bearerToken}) async {
    final client = GatewayHttp.createClient();
    try {
      final req = await client.getUrl(uri).timeout(_requestTimeout);
      GatewayHttp.applyHeaders(req, bearerToken: bearerToken);
      final res = await req.close().timeout(_requestTimeout);
      final text = await utf8.decodeStream(res).timeout(_requestTimeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AuthException(GatewayHttp.errorMessage(res.statusCode, text));
      }
      return jsonDecode(text);
    } on SocketException catch (e) {
      throw AuthException(_networkErrorMessage(e.message, gateway: baseUrl));
    } on TimeoutException {
      throw AuthException(
        'Gateway request timed out — check your connection and try again',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri, {String? bearerToken}) async {
    final decoded = await _getDecoded(uri, bearerToken: bearerToken);
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<Map<String, dynamic>> _patchJson(
    Uri uri,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) async {
    final client = GatewayHttp.createClient();
    try {
      final req = await client.patchUrl(uri).timeout(_requestTimeout);
      GatewayHttp.applyHeaders(req, bearerToken: bearerToken, jsonBody: true);
      final encoded = jsonEncode(body);
      req.contentLength = utf8.encode(encoded).length;
      req.write(encoded);
      final res = await req.close().timeout(_requestTimeout);
      final text = await utf8.decodeStream(res).timeout(_requestTimeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AuthException(GatewayHttp.errorMessage(res.statusCode, text));
      }
      if (text.isEmpty) return const {};
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return const {};
    } on SocketException catch (e) {
      throw AuthException(_networkErrorMessage(e.message, gateway: baseUrl));
    } on TimeoutException {
      throw AuthException(
        'Gateway request timed out — check your connection and try again',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) async {
    final client = GatewayHttp.createClient();
    try {
      final req = await client.postUrl(uri).timeout(_requestTimeout);
      GatewayHttp.applyHeaders(req, bearerToken: bearerToken, jsonBody: true);
      final encoded = jsonEncode(body);
      req.contentLength = utf8.encode(encoded).length;
      req.write(encoded);
      final res = await req.close().timeout(_requestTimeout);
      final text = await utf8.decodeStream(res).timeout(_requestTimeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw AuthException(GatewayHttp.errorMessage(res.statusCode, text));
      }
      if (text.isEmpty) return const {};
      final decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return const {};
    } on SocketException catch (e) {
      throw AuthException(_networkErrorMessage(e.message, gateway: baseUrl));
    } on TimeoutException {
      throw AuthException(
        'Gateway request timed out — check your connection and try again',
      );
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

/// Login methods the gateway has configured (`GET /api/v2/auth/methods`).
class AuthMethods {
  const AuthMethods({
    this.wallet = true,
    this.email = true,
    this.google = false,
    this.apple = false,
  });
  final bool wallet;
  final bool email;
  final bool google;
  final bool apple;

  /// Optimistic default before the gateway responds: wallet + email shown,
  /// social providers stay hidden until confirmed (they also need app config).
  static const unknown = AuthMethods();
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
