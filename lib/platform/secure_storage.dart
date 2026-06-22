import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App-wide secure storage. Uses AES-GCM key wrapping on Android so we never
/// touch the legacy RSA KeyStore path (avoids KeyStore code-7 warnings on
/// reinstall / OEM builds). Existing RSA-encrypted data is migrated once.
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