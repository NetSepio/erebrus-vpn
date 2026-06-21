import 'dart:convert';

/// User-facing connection modes shown in the UI.
enum ConnectMode { auto, stealth, wireguard }

extension ConnectModeX on ConnectMode {
  String get label => switch (this) {
        ConnectMode.auto => 'Auto',
        ConnectMode.stealth => 'Stealth',
        ConnectMode.wireguard => 'WireGuard',
      };

  String get blurb => switch (this) {
        ConnectMode.auto => 'Fastest path, falls back to stealth if blocked',
        ConnectMode.stealth => 'Disguises traffic as normal HTTPS / QUIC',
        ConnectMode.wireguard => 'Classic WireGuard — fastest, most detectable',
      };

  /// Ordered transports the controller tries for this mode.
  List<Transport> get transports => switch (this) {
        ConnectMode.auto => const [Transport.wireguard, Transport.vlessReality, Transport.hysteria2],
        ConnectMode.stealth => const [Transport.vlessReality, Transport.hysteria2],
        ConnectMode.wireguard => const [Transport.wireguard],
      };
}

/// Concrete transport the sing-box engine runs.
enum Transport { wireguard, vlessReality, hysteria2 }

extension TransportX on Transport {
  String get label => switch (this) {
        Transport.wireguard => 'WireGuard',
        Transport.vlessReality => 'VLESS · REALITY',
        Transport.hysteria2 => 'Hysteria2',
      };
}

/// A node from the gateway discovery list (`GET /api/v2/nodes`).
class VpnNode {
  VpnNode({
    required this.id,
    required this.name,
    required this.region,
    required this.did,
    required this.protocols,
    required this.loadPct,
  });

  final String id;
  final String name;
  final String region;
  final String did;
  final List<String> protocols;
  final double loadPct;

  bool get supportsStealth =>
      protocols.contains('vless-reality') || protocols.contains('hysteria2');

  factory VpnNode.fromJson(Map<String, dynamic> j) => VpnNode(
        id: (j['node_id'] ?? j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Erebrus node').toString(),
        region: (j['region'] ?? '').toString(),
        did: (j['did'] ?? '').toString(),
        protocols: ((j['protocols'] as List?) ?? const []).map((e) => e.toString()).toList(),
        loadPct: (j['load_pct'] as num?)?.toDouble() ?? 0,
      );
}

/// The unified credential bundle returned by the gateway when a VPN client is
/// provisioned (`POST /api/v2/vpn/clients`) — it is the node's bundle: a
/// WireGuard config plus carrier share URIs and a ready sing-box profile.
class CredentialBundle {
  CredentialBundle({
    required this.serverPublicKey,
    required this.endpoint,
    required this.address,
    required this.dns,
    required this.vlessUri,
    required this.hysteria2Uri,
    required this.singboxProfile,
  });

  final String serverPublicKey;
  final String endpoint; // host:port of the node's WireGuard listener
  final String address; // client tunnel address CIDR, e.g. 10.0.0.2/32
  final String dns;
  final String vlessUri;
  final String hysteria2Uri;
  final Map<String, dynamic> singboxProfile;

  factory CredentialBundle.fromJson(Map<String, dynamic> j) {
    final wg = (j['wireguard'] as Map?)?.cast<String, dynamic>() ?? const {};
    final profile = (j['singbox_profile'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    return CredentialBundle(
      serverPublicKey: (wg['server_public_key'] ?? '').toString(),
      endpoint: (wg['endpoint'] ?? '').toString(),
      address: (wg['address'] ?? '').toString(),
      dns: (wg['dns'] ?? '1.1.1.1').toString(),
      vlessUri: (j['vless_uri'] ?? '').toString(),
      hysteria2Uri: (j['hysteria2_uri'] ?? '').toString(),
      singboxProfile: profile,
    );
  }

  bool get hasStealth => singboxProfile.isNotEmpty && (vlessUri.isNotEmpty || hysteria2Uri.isNotEmpty);
}

/// Builds the sing-box configuration the on-device engine runs, from a
/// credential bundle, a chosen transport, and the client's locally-held
/// WireGuard private key. WireGuard is always the endpoint; stealth transports
/// wrap it (the node profile already encodes the carriers + REALITY params).
class SingboxConfigBuilder {
  static const String clientKeyPlaceholder = 'REPLACE_WITH_CLIENT_PRIVATE_KEY';
  static const String wgEndpointTag = 'wg-out';
  static const String carrierVlessTag = 'carrier-vless';
  static const String carrierHy2Tag = 'carrier-hysteria2';

  /// Returns a complete sing-box config map for [transport]. [clientPrivateKey]
  /// is the base64 WireGuard private key generated and stored on-device.
  static Map<String, dynamic> build({
    required CredentialBundle bundle,
    required Transport transport,
    required String clientPrivateKey,
  }) {
    // Deep copy the node-provided profile so we never mutate the cached bundle.
    final profile = jsonDecode(jsonEncode(bundle.singboxProfile)) as Map<String, dynamic>;

    final endpoints = (profile['endpoints'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (endpoints.isEmpty) {
      throw StateError('credential bundle has no sing-box endpoints');
    }
    final wg = endpoints.first;
    wg['private_key'] = clientPrivateKey;
    final peers = (wg['peers'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    switch (transport) {
      case Transport.wireguard:
        // Direct WireGuard: dial the node's real endpoint, no carrier detour.
        wg.remove('detour');
        if (peers.isNotEmpty) {
          final (host, port) = _splitHostPort(bundle.endpoint);
          peers.first['address'] = host;
          peers.first['port'] = port;
        }
        break;
      case Transport.vlessReality:
        wg['detour'] = carrierVlessTag; // peer endpoint stays node-loopback
        break;
      case Transport.hysteria2:
        wg['detour'] = carrierHy2Tag;
        break;
    }

    final dnsServer = bundle.dns.isNotEmpty ? bundle.dns : '1.1.1.1';

    // A tun inbound captures device traffic; route everything to the WG endpoint.
    return {
      'log': {'level': 'warn'},
      'dns': {
        'servers': [
          {
            'tag': 'dns-remote',
            'address': dnsServer,
            'detour': wgEndpointTag,
          },
        ],
        'final': 'dns-remote',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
          'auto_route': true,
          'strict_route': true,
          'stack': 'gvisor',
          'sniff': true,
          'sniff_override_destination': true,
        }
      ],
      'endpoints': endpoints,
      'outbounds': profile['outbounds'] ?? [
        {'type': 'direct', 'tag': 'direct'}
      ],
      'route': {
        'final': wgEndpointTag,
        'auto_detect_interface': false,
      },
    };
  }

  static (String, int) _splitHostPort(String hostPort) {
    final i = hostPort.lastIndexOf(':');
    if (i < 0) return (hostPort, 51820);
    final host = hostPort.substring(0, i);
    final port = int.tryParse(hostPort.substring(i + 1)) ?? 51820;
    return (host, port);
  }
}
