import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'desktop_prefs_storage.dart';
import 'platform_capabilities.dart';

/// Encrypts **persisted app secrets at rest** (gateway session token, stored WG
/// private key string, etc.). This is unrelated to WireGuard cryptography —
/// WG client keys are still generated as Curve25519 (x25519) via libbox
/// `genWgKeys` in `SingboxEngine.generateWireGuardKeyPair`.
///
/// Android uses EncryptedSharedPreferences (avoids fragile RSA KeyStore keys on
/// some OEM builds). macOS uses a non-data-protection Keychain for unsigned debug.
///
/// On desktop the helper tries the secure store first, then falls back to
/// `DesktopPrefsStorage` so unsigned dev builds without keychain entitlements
/// still work.
class ErebrusSecureStorage {
  const ErebrusSecureStorage._();

  static const FlutterSecureStorage instance = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateOnAlgorithmChange: false,
    ),
    mOptions: MacOsOptions(
      usesDataProtectionKeychain: false,
    ),
  );

  static Future<String?> read(String key) async {
    try {
      final value = await instance.read(key: key);
      if (value != null && value.isNotEmpty) return value;
    } catch (e) {
      debugPrint('[SecureStorage] read failed for $key: $e');
    }

    if (PlatformCapabilities.isDesktop) {
      try {
        return await DesktopPrefsStorage.read(key);
      } catch (e) {
        debugPrint('[SecureStorage] desktop fallback read failed for $key: $e');
      }
    }

    return null;
  }

  static Future<void> write(String key, String value) async {
    try {
      await instance.write(key: key, value: value);
      return;
    } catch (e) {
      debugPrint('[SecureStorage] write failed for $key: $e');
    }

    if (PlatformCapabilities.isDesktop) {
      try {
        await DesktopPrefsStorage.write(key, value);
      } catch (e) {
        debugPrint('[SecureStorage] desktop fallback write failed for $key: $e');
      }
    }
  }

  static Future<void> delete(String key) async {
    try {
      await instance.delete(key: key);
    } catch (e) {
      debugPrint('[SecureStorage] delete failed for $key: $e');
    }

    if (PlatformCapabilities.isDesktop) {
      try {
        await DesktopPrefsStorage.delete(key);
      } catch (e) {
        debugPrint('[SecureStorage] desktop fallback delete failed for $key: $e');
      }
    }
  }
}