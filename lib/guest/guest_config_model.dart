import 'dart:convert';

import '../vpn/vpn_models.dart';

/// A locally-imported VPN config for guest (non-authenticated) mode.
///
/// It wraps the same [CredentialBundle] shape the gateway returns, plus the
/// client WireGuard private key, which is needed because guest configs are not
/// provisioned on demand by this app.
class GuestVpnConfig {
  GuestVpnConfig({
    required this.id,
    required this.name,
    this.region,
    required this.bundle,
    this.clientPrivateKey,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? region;
  final CredentialBundle bundle;

  /// Client private key for WireGuard. If null/empty the app will fall back to
  /// locally-generated keys, but the server must already allow that public key.
  final String? clientPrivateKey;
  final DateTime createdAt;

  /// Synthesises a [VpnNode] from the bundle so the connection flow can treat
  /// guest configs the same way it treats gateway-discovered nodes.
  VpnNode toNode() {
    final protocols = <String>['wireguard'];
    if (bundle.vlessUri.isNotEmpty) protocols.add('vless-reality');
    if (bundle.hysteria2Uri.isNotEmpty) protocols.add('hysteria2');
    return VpnNode(
      id: id,
      name: name,
      region: region ?? 'Imported',
      did: '',
      protocols: protocols,
      loadPct: 0,
      acceptingClients: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (region != null) 'region': region,
        'bundle': bundle.toJson(),
        if (clientPrivateKey != null && clientPrivateKey!.isNotEmpty)
          'client_private_key': clientPrivateKey,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory GuestVpnConfig.fromJson(Map<String, dynamic> j) {
    final bundleMap = (j['bundle'] as Map?)?.cast<String, dynamic>();
    if (bundleMap == null) {
      throw FormatException('Guest config missing bundle: $j');
    }
    final regionRaw = (j['region'] ?? '').toString().trim();
    return GuestVpnConfig(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? 'Imported config').toString(),
      region: regionRaw.isEmpty ? null : regionRaw,
      bundle: CredentialBundle.fromJson(bundleMap),
      clientPrivateKey: (j['client_private_key'] ?? '').toString().isEmpty
          ? null
          : (j['client_private_key'] as String).trim(),
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ?? DateTime.now(),
    );
  }

  /// Parses either a JSON Erebrus bundle or a standard `wg-quick` .conf file.
  static GuestVpnConfig parse(String text, {String? name, String? region}) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{')) {
      return _fromErebrusJson(jsonDecode(trimmed) as Map<String, dynamic>, name: name, region: region);
    }
    return _fromWgQuick(trimmed, name: name, region: region);
  }

  static GuestVpnConfig _fromErebrusJson(
    Map<String, dynamic> j, {
    String? name,
    String? region,
  }) {
    final bundle = CredentialBundle.fromJson(j);
    final displayName = (name ?? j['name'] ?? 'Imported config').toString();
    final regionRaw = (region ?? '').isNotEmpty
        ? region!
        : (j['region'] ?? '').toString().trim();
    return GuestVpnConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: displayName,
      region: regionRaw.isEmpty ? null : regionRaw,
      bundle: bundle,
      clientPrivateKey: (j['client_private_key'] ?? '').toString().isEmpty
          ? null
          : (j['client_private_key'] as String).trim(),
      createdAt: DateTime.now(),
    );
  }

  static GuestVpnConfig _fromWgQuick(
    String text, {
    String? name,
    String? region,
  }) {
    String? section;
    final values = <String, String>{};
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).toLowerCase();
        continue;
      }
      final eq = line.indexOf('=');
      if (eq == -1 || section == null) continue;
      final key = line.substring(0, eq).trim().toLowerCase();
      final value = line.substring(eq + 1).trim();
      values['$section.$key'] = value;
    }

    final privateKey = values['interface.privatekey'];
    final address = values['interface.address'] ?? '';
    final dns = values['interface.dns'] ?? '1.1.1.1';
    final serverPublicKey = values['peer.publickey'] ?? '';
    final endpoint = values['peer.endpoint'] ?? '';

    if (privateKey == null || privateKey.isEmpty) {
      throw FormatException('WireGuard config is missing [Interface] PrivateKey');
    }
    if (serverPublicKey.isEmpty) {
      throw FormatException('WireGuard config is missing [Peer] PublicKey');
    }
    if (endpoint.isEmpty) {
      throw FormatException('WireGuard config is missing [Peer] Endpoint');
    }

    final bundle = CredentialBundle(
      serverPublicKey: serverPublicKey,
      endpoint: endpoint,
      address: address,
      dns: dns,
      vlessUri: '',
      hysteria2Uri: '',
      singboxProfile: const {},
    );

    return GuestVpnConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name ?? 'Imported config',
      region: region,
      bundle: bundle,
      clientPrivateKey: privateKey,
      createdAt: DateTime.now(),
    );
  }
}
