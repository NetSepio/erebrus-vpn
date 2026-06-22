import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts **persisted app secrets at rest** (gateway session token, stored WG
/// private key string, etc.). This is unrelated to WireGuard cryptography —
/// WG client keys are still generated as Curve25519 (x25519) via libbox
/// `genWgKeys` in `SingboxEngine.generateWireGuardKeyPair`.
///
/// Uses the plugin's default cipher (RSA-OAEP key wrapping + AES-GCM data), which
/// is explicitly **non-biometric** — secrets read/write silently. We must NOT use
/// the `AES_GCM_NoPadding` *key* cipher: on biometric-capable hardware (e.g. the
/// Solana Seeker) that combo binds the KeyStore key to biometric auth, so every
/// read pops a fingerprint prompt and fails with "Authentication canceled" during
/// silent restore — which broke session/WG-key persistence and wallet sign-in.
class ErebrusSecureStorage {
  const ErebrusSecureStorage._();

  static const FlutterSecureStorage instance = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
      migrateOnAlgorithmChange: true,
    ),
    // macOS Keychain requires keychain-access-groups in Runner entitlements.
    // usesDataProtectionKeychain:false works for unsigned flutter run debug builds.
    mOptions: MacOsOptions(
      usesDataProtectionKeychain: false,
    ),
  );
}