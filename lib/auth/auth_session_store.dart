import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/platform_capabilities.dart';
import '../platform/secure_storage.dart';

/// Persisted gateway session + optional Solana Mobile Wallet Adapter state.
///
/// Mobile uses Keychain/Keystore via [FlutterSecureStorage]. Desktop also mirrors
/// to SharedPreferences so `flutter run -d macos` works when Keychain entitlements
/// are missing (errSecMissingEntitlement / -34018 on ad-hoc signed debug builds).
class AuthSessionStore {
  AuthSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? ErebrusSecureStorage.instance;

  final FlutterSecureStorage _storage;

  static const kToken = 'erebrus_gateway_token';
  static const kWallet = 'erebrus_wallet_address';
  static const kUserId = 'erebrus_user_id';
  static const kRole = 'erebrus_user_role';
  static const kAuthMethod = 'erebrus_auth_method';
  static const kMwaToken = 'erebrus_mwa_auth_token';

  static const _prefsPrefix = 'erebrus_auth_';

  Future<StoredAuthSession?> read() async {
    // Unsigned desktop: never touch Keychain (avoids login-keychain password prompts).
    if (PlatformCapabilities.isDesktop) {
      return _readPrefs();
    }
    return _readSecure();
  }

  Future<void> write({
    required String token,
    required String walletAddress,
    required String userId,
    required String role,
    required String authMethod,
    String? mwaAuthToken,
  }) async {
    final session = StoredAuthSession(
      token: token,
      walletAddress: walletAddress,
      userId: userId,
      role: role,
      authMethod: authMethod,
      mwaAuthToken: mwaAuthToken,
    );

    if (PlatformCapabilities.isDesktop) {
      await _writePrefs(session);
      debugPrint('[Auth] session saved (desktop local store)');
      return;
    }

    final secureOk = await _writeSecure(session);
    if (!secureOk) {
      throw PlatformException(
        code: 'secure_storage_unavailable',
        message: 'Could not persist sign-in session',
      );
    }
  }

  Future<void> clear() async {
    if (PlatformCapabilities.isDesktop) {
      await _clearPrefs();
      return;
    }
    for (final key in [kToken, kWallet, kUserId, kRole, kAuthMethod, kMwaToken]) {
      try {
        await _storage.delete(key: key);
      } on PlatformException catch (e) {
        debugPrint('[Auth] secure storage delete failed for $key: ${e.message}');
      } catch (e) {
        debugPrint('[Auth] secure storage delete failed for $key: $e');
      }
    }
  }

  Future<StoredAuthSession?> _readSecure() async {
    try {
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
    } catch (e) {
      debugPrint('[Auth] secure storage read failed: $e');
      return null;
    }
  }

  Future<bool> _writeSecure(StoredAuthSession session) async {
    try {
      await _storage.write(key: kToken, value: session.token);
      await _storage.write(key: kWallet, value: session.walletAddress);
      await _storage.write(key: kUserId, value: session.userId);
      await _storage.write(key: kRole, value: session.role);
      await _storage.write(key: kAuthMethod, value: session.authMethod);
      if (session.mwaAuthToken != null && session.mwaAuthToken!.isNotEmpty) {
        await _storage.write(key: kMwaToken, value: session.mwaAuthToken);
      } else {
        await _storage.delete(key: kMwaToken);
      }
      return true;
    } on PlatformException catch (e) {
      debugPrint('[Auth] secure storage write failed: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[Auth] secure storage write failed: $e');
      return false;
    }
  }

  Future<StoredAuthSession?> _readPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('$_prefsPrefix$kToken');
      if (token == null || token.isEmpty) return null;
      return StoredAuthSession(
        token: token,
        walletAddress: prefs.getString('$_prefsPrefix$kWallet') ?? '',
        userId: prefs.getString('$_prefsPrefix$kUserId') ?? '',
        role: prefs.getString('$_prefsPrefix$kRole') ?? 'user',
        authMethod: prefs.getString('$_prefsPrefix$kAuthMethod') ?? 'web',
        mwaAuthToken: prefs.getString('$_prefsPrefix$kMwaToken'),
      );
    } catch (e) {
      debugPrint('[Auth] prefs session read failed: $e');
      return null;
    }
  }

  Future<void> _writePrefs(StoredAuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefsPrefix$kToken', session.token);
    await prefs.setString('$_prefsPrefix$kWallet', session.walletAddress);
    await prefs.setString('$_prefsPrefix$kUserId', session.userId);
    await prefs.setString('$_prefsPrefix$kRole', session.role);
    await prefs.setString('$_prefsPrefix$kAuthMethod', session.authMethod);
    final mwa = session.mwaAuthToken;
    if (mwa != null && mwa.isNotEmpty) {
      await prefs.setString('$_prefsPrefix$kMwaToken', mwa);
    } else {
      await prefs.remove('$_prefsPrefix$kMwaToken');
    }
  }

  Future<void> _clearPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [kToken, kWallet, kUserId, kRole, kAuthMethod, kMwaToken]) {
      await prefs.remove('$_prefsPrefix$key');
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