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
    // Gateway may put the WG endpoint at wireguard.endpoint or transports[0].uri.
    var endpoint = (wg['endpoint'] ?? '').toString();
    if (endpoint.isEmpty) {
      final transports = (j['transports'] as List?) ?? const [];
      for (final t in transports) {
        if (t is Map && (t['kind'] ?? '').toString().contains('wireguard')) {
          endpoint = (t['uri'] ?? '').toString();
          break;
        }
      }
    }
    return CredentialBundle(
      serverPublicKey: (wg['server_public_key'] ?? '').toString(),
      endpoint: endpoint,
      address: (wg['address'] ?? '').toString(),
      dns: (wg['dns'] ?? '1.1.1.1').toString(),
      vlessUri: (j['vless_uri'] ?? '').toString(),
      hysteria2Uri: (j['hysteria2_uri'] ?? '').toString(),
      singboxProfile: profile,
    );
  }

  bool get hasWireGuard =>
      serverPublicKey.isNotEmpty && endpoint.isNotEmpty && address.isNotEmpty;

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

  /// sing-box TUN address; DNS hijack lands on [.tunDnsAddress] inside this /30.
  static const String tunAddress = '172.19.0.1/30';
  static const String tunDnsAddress = '172.19.0.2';

  /// Local mixed inbound so the app UID (excluded from system TUN) can still
  /// reach the tunnel via 127.0.0.1.
  static const String localProxyHost = '127.0.0.1';
  static const int localProxyPort = 10808;
  static const String localMixedInboundTag = 'mixed-in';

  /// Enables the local Clash API so the app can read live traffic stats.
  static Map<String, dynamic> _withClashApi(Map<String, dynamic> config) {
    final out = Map<String, dynamic>.from(config);
    final experimental = Map<String, dynamic>.from(
      (out['experimental'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    experimental['clash_api'] = {
      'external_controller': '127.0.0.1:9090',
      'secret': '',
    };
    out['experimental'] = experimental;
    return out;
  }

  /// Returns a complete sing-box config map for [transport]. [clientPrivateKey]
  /// is the base64 WireGuard private key generated and stored on-device.
  static Map<String, dynamic> build({
    required CredentialBundle bundle,
    required Transport transport,
    required String clientPrivateKey,
  }) {
    if (!bundle.hasWireGuard) {
      throw StateError('credential bundle is missing wireguard fields');
    }
    if (transport == Transport.wireguard) {
      return _buildDirectWireGuard(bundle: bundle, clientPrivateKey: clientPrivateKey);
    }
    return _buildStealth(bundle: bundle, transport: transport, clientPrivateKey: clientPrivateKey);
  }

  /// Direct UDP WireGuard — mirrors the gateway's `client_conf` / wg-quick layout.
  static Map<String, dynamic> _buildDirectWireGuard({
    required CredentialBundle bundle,
    required String clientPrivateKey,
  }) {
    final (host, port) = _splitHostPort(bundle.endpoint);
    final clientAddr =
        bundle.address.contains('/') ? bundle.address : '${bundle.address}/32';
    final dnsServer = bundle.dns.isNotEmpty ? bundle.dns : '1.1.1.1';

    return _withClashApi({
      'log': {'level': 'info'},
      'dns': {
        'servers': [
          {'tag': 'dns-remote', 'address': dnsServer, 'detour': wgEndpointTag},
        ],
        'final': 'dns-remote',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': _tunInbounds(),
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'},
      ],
      'endpoints': [
        {
          'type': 'wireguard',
          'tag': wgEndpointTag,
          'address': [clientAddr],
          'private_key': clientPrivateKey,
          'mtu': 1280,
          'peers': [
            {
              'address': host,
              'port': port,
              'public_key': bundle.serverPublicKey,
              'allowed_ips': ['0.0.0.0/0', '::/0'],
              'persistent_keepalive_interval': 25,
            },
          ],
        },
      ],
      'route': _route(finalTag: wgEndpointTag, wgServerHost: host),
    });
  }

  /// Stealth carriers reuse the node-provided sing-box profile (loopback WG peer).
  static Map<String, dynamic> _buildStealth({
    required CredentialBundle bundle,
    required Transport transport,
    required String clientPrivateKey,
  }) {
    final profile =
        jsonDecode(jsonEncode(bundle.singboxProfile)) as Map<String, dynamic>;
    final endpoints = (profile['endpoints'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (endpoints.isEmpty) {
      throw StateError('credential bundle has no sing-box endpoints for stealth');
    }
    final wg = endpoints.first;
    wg['private_key'] = clientPrivateKey;
    if (bundle.address.isNotEmpty) {
      wg['address'] = [
        bundle.address.contains('/') ? bundle.address : '${bundle.address}/32',
      ];
    }
    final peers = (wg['peers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (peers.isNotEmpty && bundle.serverPublicKey.isNotEmpty) {
      peers.first['public_key'] = bundle.serverPublicKey;
    }

    switch (transport) {
      case Transport.vlessReality:
        wg['detour'] = carrierVlessTag;
        break;
      case Transport.hysteria2:
        wg['detour'] = carrierHy2Tag;
        break;
      case Transport.wireguard:
        break;
    }

    final dnsServer = bundle.dns.isNotEmpty ? bundle.dns : '1.1.1.1';
    final profileRoute = (profile['route'] as Map?)?.cast<String, dynamic>() ?? const {};
    final extraRules =
        (profileRoute['rules'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return _withClashApi({
      'log': {'level': 'info'},
      'dns': {
        'servers': [
          {'tag': 'dns-remote', 'address': dnsServer, 'detour': wgEndpointTag},
        ],
        'final': 'dns-remote',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': _tunInbounds(),
      'endpoints': endpoints,
      'outbounds': profile['outbounds'] ?? [
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': _route(
        finalTag: wgEndpointTag,
        extraRules: extraRules,
      ),
    });
  }

  static List<Map<String, dynamic>> _tunInbounds() => [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': [tunAddress],
          'auto_route': true,
          'strict_route': true,
          'stack': 'gvisor',
          'sniff': true,
        },
        {
          'type': 'mixed',
          'tag': localMixedInboundTag,
          'listen': localProxyHost,
          'listen_port': localProxyPort,
          'sniff': true,
        },
      ];

  /// Local/bypass rules that must run before [final]. DNS hijack comes first so
  /// queries to [tunDnsAddress] are not caught by a broad CIDR → direct rule.
  static List<Map<String, dynamic>> _localRouteRules({String? wgServerHost}) {
    final rules = <Map<String, dynamic>>[
      {'protocol': 'dns', 'action': 'hijack-dns'},
      {'ip_cidr': ['127.0.0.0/8'], 'outbound': 'direct'},
    ];
    if (wgServerHost != null &&
        wgServerHost.isNotEmpty &&
        wgServerHost != '127.0.0.1') {
      rules.insert(0, {
        'ip_cidr': ['$wgServerHost/32'],
        'outbound': 'direct',
      });
    }
    return rules;
  }

  static Map<String, dynamic> _route({
    required String finalTag,
    String? wgServerHost,
    List<Map<String, dynamic>> extraRules = const [],
  }) =>
      {
        'rules': [..._localRouteRules(wgServerHost: wgServerHost), ...extraRules],
        'final': finalTag,
        'auto_detect_interface': true,
      };

  static (String, int) _splitHostPort(String hostPort) {
    final i = hostPort.lastIndexOf(':');
    if (i < 0) return (hostPort, 51820);
    final host = hostPort.substring(0, i);
    final port = int.tryParse(hostPort.substring(i + 1)) ?? 51820;
    return (host, port);
  }

  /// Blocks all traffic through a local TUN when the VPN tunnel drops unexpectedly.
  static Map<String, dynamic> killSwitchBlockConfig() => {
        'log': {'level': 'warn'},
        'inbounds': [
          {
            'type': 'tun',
            'tag': 'tun-in',
            'address': [tunAddress],
            'auto_route': true,
            'strict_route': true,
            'stack': 'gvisor',
          },
        ],
        'outbounds': [
          {'type': 'block', 'tag': 'block'},
        ],
        'route': {
          'final': 'block',
          'auto_detect_interface': true,
        },
      };
}
