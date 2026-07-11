import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/secure_storage.dart';
import 'vpn_models.dart';

/// Persists the last successful gateway credential bundle per node + WG pubkey.
class CredentialCache {
  CredentialCache();

  static const _indexKey = 'erebrus_bundle_index';

  String _key(String nodeId, String wgPublicKey) =>
      'erebrus_bundle_${nodeId}_$wgPublicKey';

  Future<CredentialBundle?> read({
    required String nodeId,
    required String wgPublicKey,
  }) async {
    try {
      final cacheKey = _key(nodeId, wgPublicKey);
      final raw = await ErebrusSecureStorage.read(cacheKey);
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
      final cacheKey = _key(nodeId, wgPublicKey);
      await ErebrusSecureStorage.write(cacheKey, json);
      await _rememberKey(cacheKey);
    } catch (e) {
      debugPrint('[VPN] credential cache write failed: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getStringList(_indexKey) ?? const <String>[];
      for (final cacheKey in keys) {
        await ErebrusSecureStorage.delete(cacheKey);
      }
      await prefs.remove(_indexKey);
      debugPrint('[VPN] credential cache cleared (${keys.length} entries)');
    } catch (e) {
      debugPrint('[VPN] credential cache clear failed: $e');
    }
  }

  Future<void> _rememberKey(String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = List<String>.from(prefs.getStringList(_indexKey) ?? const []);
    if (!keys.contains(cacheKey)) {
      keys.add(cacheKey);
      await prefs.setStringList(_indexKey, keys);
    }
  }
}