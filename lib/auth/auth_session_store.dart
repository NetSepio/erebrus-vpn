import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persisted gateway session + optional Solana Mobile Wallet Adapter state.
class AuthSessionStore {
  AuthSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const kToken = 'erebrus_gateway_token';
  static const kWallet = 'erebrus_wallet_address';
  static const kUserId = 'erebrus_user_id';
  static const kRole = 'erebrus_user_role';
  static const kAuthMethod = 'erebrus_auth_method';
  static const kMwaToken = 'erebrus_mwa_auth_token';

  Future<StoredAuthSession?> read() async {
    final token = await _storage.read(key: kToken);
    if (token == null || token.isEmpty) return null;
    return StoredAuthSession(
      token: token,
      walletAddress: await _storage.read(key: kWallet) ?? '',
      userId: await _storage.read(key: kUserId) ?? '',
      role: await _storage.read(key: kRole) ?? 'user',
      authMethod: await _storage.read(key: kAuthMethod) ?? 'reown',
      mwaAuthToken: await _storage.read(key: kMwaToken),
    );
  }

  Future<void> write({
    required String token,
    required String walletAddress,
    required String userId,
    required String role,
    required String authMethod,
    String? mwaAuthToken,
  }) async {
    await _storage.write(key: kToken, value: token);
    await _storage.write(key: kWallet, value: walletAddress);
    await _storage.write(key: kUserId, value: userId);
    await _storage.write(key: kRole, value: role);
    await _storage.write(key: kAuthMethod, value: authMethod);
    if (mwaAuthToken != null && mwaAuthToken.isNotEmpty) {
      await _storage.write(key: kMwaToken, value: mwaAuthToken);
    } else {
      await _storage.delete(key: kMwaToken);
    }
  }

  Future<void> clear() async {
    for (final key in [kToken, kWallet, kUserId, kRole, kAuthMethod, kMwaToken]) {
      await _storage.delete(key: key);
    }
  }
}

class StoredAuthSession {
  const StoredAuthSession({
    required this.token,
    required this.walletAddress,
    required this.userId,
    required this.role,
    required this.authMethod,
    this.mwaAuthToken,
  });

  final String token;
  final String walletAddress;
  final String userId;
  final String role;
  final String authMethod;
  final String? mwaAuthToken;
}