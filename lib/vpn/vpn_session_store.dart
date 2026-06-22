import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'vpn_models.dart';

/// Persists the last active VPN session so the Flutter UI can be rebuilt when
/// the app process restarts while the native tunnel keeps running.
class VpnSessionStore {
  static const _key = 'vpn.session.snapshot';

  static Future<void> save({
    required VpnNode node,
    required Transport transport,
    required ConnectMode mode,
    required String profileName,
    bool killSwitchActive = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'node_id': node.id,
        'node_name': node.name,
        'region': node.region,
        'did': node.did,
        'protocols': node.protocols,
        'load_pct': node.loadPct,
        'transport': transport.name,
        'mode': mode.name,
        'profile_name': profileName,
        'kill_switch_active': killSwitchActive,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  static Future<VpnSessionSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return VpnSessionSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

class VpnSessionSnapshot {
  const VpnSessionSnapshot({
    required this.nodeId,
    required this.nodeName,
    required this.region,
    required this.did,
    required this.protocols,
    required this.loadPct,
    required this.transport,
    required this.mode,
    required this.profileName,
    required this.killSwitchActive,
    required this.savedAt,
  });

  final String nodeId;
  final String nodeName;
  final String region;
  final String did;
  final List<String> protocols;
  final double loadPct;
  final Transport transport;
  final ConnectMode mode;
  final String profileName;
  final bool killSwitchActive;
  final DateTime? savedAt;

  VpnNode toNode() => VpnNode(
        id: nodeId,
        name: nodeName,
        region: region,
        did: did,
        protocols: protocols,
        loadPct: loadPct,
      );

  factory VpnSessionSnapshot.fromJson(Map<String, dynamic> j) {
    Transport parseTransport(String? raw) => switch (raw) {
          'vlessReality' => Transport.vlessReality,
          'hysteria2' => Transport.hysteria2,
          _ => Transport.wireguard,
        };
    ConnectMode parseMode(String? raw) => switch (raw) {
          'stealth' => ConnectMode.stealth,
          'wireguard' => ConnectMode.wireguard,
          _ => ConnectMode.auto,
        };

    return VpnSessionSnapshot(
      nodeId: (j['node_id'] ?? '').toString(),
      nodeName: (j['node_name'] ?? 'Erebrus node').toString(),
      region: (j['region'] ?? '').toString(),
      did: (j['did'] ?? '').toString(),
      protocols: ((j['protocols'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      loadPct: (j['load_pct'] as num?)?.toDouble() ?? 0,
      transport: parseTransport(j['transport']?.toString()),
      mode: parseMode(j['mode']?.toString()),
      profileName: (j['profile_name'] ?? '').toString(),
      killSwitchActive: j['kill_switch_active'] == true,
      savedAt: DateTime.tryParse((j['saved_at'] ?? '').toString()),
    );
  }
}