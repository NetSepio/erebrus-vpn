import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts **persisted app secrets at rest** (gateway session token, stored WG
/// private key string, etc.). This is unrelated to WireGuard cryptography —
/// WG client keys are still generated as Curve25519 (x25519) via libbox
/// `genWgKeys` in `SingboxEngine.generateWireGuardKeyPair`.
///
/// AES-GCM here only wraps the Android Keystore blob that encrypts key-value
/// entries on disk, avoiding the legacy RSA KeyStore path (code-7 warnings).
class ErebrusSecureStorage {
  const ErebrusSecureStorage._();

  static const FlutterSecureStorage instance = FlutterSecureStorage(
    aOptions: AndroidOptions(
      keyCipherAlgorithm: KeyCipherAlgorithm.AES_GCM_NoPadding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
      resetOnError: true,
      migrateOnAlgorithmChange: true,
    ),
  );
}