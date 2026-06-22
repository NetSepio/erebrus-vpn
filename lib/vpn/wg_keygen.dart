import 'dart:convert';

import 'package:x25519/x25519.dart';

/// WireGuard-compatible x25519 keypair (base64), generated in Dart when native
/// `genWgKeys` is unavailable (Windows/Linux desktop stubs).
class WgKeygen {
  static ({String private, String public}) generate() {
    final kp = generateKeyPair();
    return (
      private: base64Encode(kp.privateKey),
      public: base64Encode(kp.publicKey),
    );
  }
}