import 'dart:convert';

import 'package:x25519/x25519.dart';

/// Generates a WireGuard x25519 keypair locally (private key never leaves device).
///
/// This is **not** server registration — the gateway already receives only the
/// **public** key via `POST /api/v2/vpn/clients` during connect. The private key
/// must exist on-device before that call; Android uses native `genWgKeys`, desktop
/// uses this Dart fallback because Win/Linux plugins are not wired to libbox yet.
class WgKeygen {
  static ({String private, String public}) generate() {
    final kp = generateKeyPair();
    return (
      private: base64Encode(kp.privateKey),
      public: base64Encode(kp.publicKey),
    );
  }
}