import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts **persisted app secrets at rest** (gateway session token, stored WG
/// private key string, etc.). This is unrelated to WireGuard cryptography —
/// WG client keys are still generated as Curve25519 (x25519) via libbox
/// `genWgKeys` in `SingboxEngine.generateWireGuardKeyPair`.
///
/// Android uses EncryptedSharedPreferences (avoids fragile RSA KeyStore keys on
/// some OEM builds). macOS uses a non-data-protection Keychain for unsigned debug.
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
}