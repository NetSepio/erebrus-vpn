import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'desktop_prefs_storage.dart';
import 'platform_capabilities.dart';

/// Encrypts **persisted app secrets at rest** (gateway session token, stored WG
/// private key string, etc.). This is unrelated to WireGuard cryptography —
/// WG client keys are still generated as Curve25519 (x25519) via libbox
/// `genWgKeys` in `SingboxEngine.generateWireGuardKeyPair`.
///
/// On Android the plugin wraps an AES-GCM data key with an RSA key held in the
/// Android Keystore. macOS uses a non-data-protection Keychain for unsigned debug.
///
/// On desktop the helper tries the secure store first, then falls back to
/// `DesktopPrefsStorage` so unsigned dev builds without keychain entitlements
/// still work.
class ErebrusSecureStorage {
  const ErebrusSecureStorage._();

  static const FlutterSecureStorage instance = FlutterSecureStorage(
    aOptions: AndroidOptions(
      // The Keystore key cannot be exported, backed up or rebuilt, so once it
      // is gone the stored ciphertext is unreadable for good — and that is a
      // state real devices reach: a restore from backup carries the encrypted
      // preferences to a device whose Keystore has no matching key, and a
      // reinstall can land on a new uid whose key the old blob was not wrapped
      // with. Observed on a Seeker as "Failed to unwrap key" on every single
      // operation, which broke sign-in and left the app unusable.
      //
      // With this false the plugin threw for ever and nothing could clear it.
      // Resetting discards data that was already unreadable: the user signs in
      // again and the client re-provisions. Migration is not the answer here —
      // it preserves data across a deliberate cipher change, and cannot help
      // when the wrapping key itself is gone.
      resetOnError: true,
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