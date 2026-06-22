import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../platform/secure_storage.dart';
import 'vpn_models.dart';

/// Persists the last successful gateway credential bundle per node + WG pubkey.
class CredentialCache {
  CredentialCache({FlutterSecureStorage? storage})
      : _storage = storage ?? ErebrusSecureStorage.instance;

  final FlutterSecureStorage _storage;

  String _key(String nodeId, String wgPublicKey) =>
      'erebrus_bundle_${nodeId}_$wgPublicKey';

  Future<CredentialBundle?> read({
    required String nodeId,
    required String wgPublicKey,
  }) async {
    try {
      final raw = await _storage.read(key: _key(nodeId, wgPublicKey));
      if (raw == null || raw.isEmpty) return null;
      return CredentialBundle.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('[VPN] credential cache read failed: $e');
      return null;
    }
  }

  Future<void> write({
    required String nodeId,
    required String wgPublicKey,
    required CredentialBundle bundle,
  }) async {
    try {
      final json = jsonEncode({
        'wireguard': {
          'server_public_key': bundle.serverPublicKey,
          'endpoint': bundle.endpoint,
          'address': bundle.address,
          'dns': bundle.dns,
        },
        'vless_uri': bundle.vlessUri,
        'hysteria2_uri': bundle.hysteria2Uri,
        'singbox_profile': bundle.singboxProfile,
      });
      await _storage.write(key: _key(nodeId, wgPublicKey), value: json);
    } catch (e) {
      debugPrint('[VPN] credential cache write failed: $e');
    }
  }
}