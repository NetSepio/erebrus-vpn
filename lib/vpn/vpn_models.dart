import 'dart:convert';

import 'package:flutter/foundation.dart';

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
        ConnectMode.wireguard => 'Fast direct tunnel for normal use',
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

/// Org summary embedded on gateway node discovery (`GET /api/v2/nodes`) and the
/// operator node view (`GET /api/v2/operator/nodes`). Mirrors the gateway
/// `orgSummary` shape (api/org_views.go): `verification_status` (string),
/// `slug`, `display_name`, `description`, `website_url`, `plan`, and `id` (only
/// present when the caller is org owner/admin).
class VpnNodeOrg {
  const VpnNodeOrg({
    required this.name,
    this.id,
    this.kind,
    this.verified = false,
    this.verificationStatus,
    this.slug,
    this.displayName,
    this.description,
    this.website,
    this.plan,
  });

  final String name;
  final String? id;
  final String? kind;
  /// Derived from [verificationStatus] == 'verified'.
  final bool verified;
  final String? verificationStatus;
  final String? slug;
  final String? displayName;
  final String? description;
  final String? website;
  final String? plan;

  /// Preferred display label: `display_name` falls back to `name`.
  String get label =>
      (displayName != null && displayName!.isNotEmpty) ? displayName! : name;

  factory VpnNodeOrg.fromJson(Map<String, dynamic> j) {
    String? str(String key) {
      final v = (j[key] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    final verificationStatus = str('verification_status');
    return VpnNodeOrg(
      name: (j['name'] ?? '').toString(),
      id: str('id'),
      kind: str('kind'),
      // Gateway sends `verification_status`; tolerate a legacy bool `verified`.
      verified: verificationStatus == 'verified' || j['verified'] == true,
      verificationStatus: verificationStatus,
      slug: str('slug'),
      displayName: str('display_name'),
      description: str('description'),
      // Gateway field is `website_url`; tolerate legacy `website`.
      website: str('website_url') ?? str('website'),
      plan: str('plan'),
    );
  }
}

/// An organization the signed-in user belongs to (`GET /api/v2/orgs`). The org
/// UUID (`id`) is only returned to owner/admin members; [slug] is always present
/// and is the stable key used to scope nodes to an org.
class VpnOrg {
  const VpnOrg({
    required this.name,
    required this.slug,
    this.id,
    this.role,
    this.plan,
    this.verificationStatus,
  });

  final String name;
  final String slug;
  final String? id;
  final String? role;
  final String? plan;
  final String? verificationStatus;

  bool get verified => verificationStatus == 'verified';

  factory VpnOrg.fromJson(Map<String, dynamic> j) {
    String? str(String key) {
      final v = (j[key] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    return VpnOrg(
      name: (j['name'] ?? '').toString(),
      slug: (j['slug'] ?? '').toString(),
      id: str('id'),
      role: str('role'),
      plan: str('plan'),
      verificationStatus: str('verification_status'),
    );
  }
}

/// Capability flags advertised by a node.
class VpnNodeCapabilities {
  const VpnNodeCapabilities({
    this.accessMode,
    this.appHosting = false,
    this.wildcardDomain,
  });

  final String? accessMode;
  final bool appHosting;
  final String? wildcardDomain;

  factory VpnNodeCapabilities.fromJson(Map<String, dynamic> j) {
    final wildcard = (j['wildcard_domain'] ?? '').toString().trim();
    final accessMode = (j['access_mode'] ?? '').toString().trim();
    return VpnNodeCapabilities(
      accessMode: accessMode.isEmpty ? null : accessMode,
      appHosting: j['app_hosting'] == true,
      wildcardDomain: wildcard.isEmpty ? null : wildcard,
    );
  }
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
    this.status = 'online',
    this.accessMode = 'public',
    this.minTier = 0,
    this.zone,
    this.peerId,
    this.walletAddress,
    this.chain,
    this.ipHash,
    this.version,
    this.rxBytes,
    this.txBytes,
    this.lastHeartbeat,
    this.lastPeerHandshake,
    this.createdAt,
    this.latencyMs,
    this.downloadMbps,
    this.uploadMbps,
    this.speedtestMeasuredAt,
    this.org,
    this.capabilities,
    this.probeHost,
    this.probePorts = const [],
  });

  final String id;
  final String name;
  final String region;
  final String did;
  final List<String> protocols;
  final double loadPct;
  final String status;
  final String accessMode;
  final int minTier;
  final String? zone;
  final String? peerId;
  final String? walletAddress;
  final String? chain;
  final String? ipHash;
  final String? version;
  final int? rxBytes;
  final int? txBytes;
  final String? lastHeartbeat;
  final String? lastPeerHandshake;
  final String? createdAt;
  final int? latencyMs;
  final double? downloadMbps;
  final double? uploadMbps;
  final int? speedtestMeasuredAt;
  final VpnNodeOrg? org;
  final VpnNodeCapabilities? capabilities;
  final String? probeHost;
  final List<int> probePorts;

  bool get supportsStealth =>
      protocols.contains('vless-reality') || protocols.contains('hysteria2');

  bool get isDraining => status.toLowerCase() == 'draining';
  bool get isOffline => status.toLowerCase() == 'offline';
  bool get isPrivateAccess => accessMode.toLowerCase() == 'private';
  bool get requiresHigherTier => minTier > 0;

  bool get hasLatency => latencyMs != null && latencyMs! > 0;
  bool get hasDownloadMbps => downloadMbps != null && downloadMbps! > 0;
  bool get hasUploadMbps => uploadMbps != null && uploadMbps! > 0;

  /// Node-reported Cloudflare speedtest (node → internet), not phone → node.
  bool get hasReportedSpeedtest =>
      speedtestMeasuredAt != null &&
      speedtestMeasuredAt! > 0 &&
      (hasLatency || hasDownloadMbps || hasUploadMbps);

  bool get hasHeartbeat => lastHeartbeat != null && lastHeartbeat!.isNotEmpty;

  bool get hasPeerHandshake =>
      lastPeerHandshake != null && lastPeerHandshake!.isNotEmpty;

  bool get isSolana => chain?.toUpperCase() == 'SOLANA';

  bool get canProbe => probeHost != null && probeHost!.isNotEmpty && probePorts.isNotEmpty;

  String get protocolsLabel {
    final parts = <String>[];
    if (protocols.contains('wireguard')) parts.add('WG');
    if (protocols.contains('vless-reality')) parts.add('VLESS');
    if (protocols.contains('hysteria2')) parts.add('Hy2');
    return parts.isEmpty ? 'VPN' : parts.join(' · ');
  }

  factory VpnNode.fromJson(Map<String, dynamic> j) {
    final caps = (j['capabilities'] as Map?)?.cast<String, dynamic>();
    final speedtest = (j['speedtest'] as Map?)?.cast<String, dynamic>();
    final orgMap = (j['org'] as Map?)?.cast<String, dynamic>();
    final org = orgMap == null ? null : VpnNodeOrg.fromJson(orgMap);
    final endpoints = (j['endpoints'] as Map?)?.cast<String, dynamic>();
    final probe = _parseProbeTargets(endpoints);
    final zone = (j['zone'] ?? '').toString().trim();
    final peerId = (j['peer_id'] ?? '').toString().trim();
    final walletAddress = (j['wallet_address'] ?? '').toString().trim();
    final chain = (j['chain'] ?? '').toString().trim();
    final ipHash = (j['ip_hash'] ?? '').toString().trim();
    final version = (j['version'] ?? '').toString().trim();
    final lastHeartbeat = (j['last_heartbeat'] ?? '').toString().trim();
    final lastPeerHandshake = (j['last_peer_handshake'] ?? '').toString().trim();
    final createdAt = (j['created_at'] ?? '').toString().trim();
    return VpnNode(
      id: (j['node_id'] ?? j['id'] ?? '').toString(),
      name: (j['name'] ?? 'Erebrus node').toString(),
      region: (j['region'] ?? '').toString(),
      did: (j['did'] ?? '').toString(),
      protocols: ((j['protocols'] as List?) ?? const []).map((e) => e.toString()).toList(),
      loadPct: (j['load_pct'] as num?)?.toDouble() ?? 0,
      status: (j['status'] ?? 'online').toString(),
      accessMode: (j['access_mode'] ?? caps?['access_mode'] ?? 'public').toString(),
      minTier: (j['min_tier'] as num?)?.toInt() ?? 0,
      zone: zone.isEmpty ? null : zone,
      peerId: peerId.isEmpty ? null : peerId,
      walletAddress: walletAddress.isEmpty ? null : walletAddress,
      chain: chain.isEmpty ? null : chain,
      ipHash: ipHash.isEmpty ? null : ipHash,
      version: version.isEmpty ? null : version,
      rxBytes: (j['rx_bytes'] as num?)?.toInt(),
      txBytes: (j['tx_bytes'] as num?)?.toInt(),
      lastHeartbeat: lastHeartbeat.isEmpty ? null : lastHeartbeat,
      lastPeerHandshake: lastPeerHandshake.isEmpty ? null : lastPeerHandshake,
      createdAt: createdAt.isEmpty ? null : createdAt,
      latencyMs: (speedtest?['latency_ms'] as num?)?.toInt(),
      downloadMbps: (speedtest?['download_mbps'] as num?)?.toDouble(),
      uploadMbps: (speedtest?['upload_mbps'] as num?)?.toDouble(),
      speedtestMeasuredAt: (speedtest?['measured_at'] as num?)?.toInt(),
      org: org,
      capabilities: caps == null ? null : VpnNodeCapabilities.fromJson(caps),
      probeHost: probe.$1,
      probePorts: probe.$2,
    );
  }

  static (String?, List<int>) _parseProbeTargets(Map<String, dynamic>? endpoints) {
    if (endpoints == null) return (null, const []);
    final wg = (endpoints['wireguard'] as Map?)?.cast<String, dynamic>();
    final vless = (endpoints['vless_reality'] as Map?)?.cast<String, dynamic>();
    final hy2 = (endpoints['hysteria2'] as Map?)?.cast<String, dynamic>();
    final host = (wg?['host'] ?? '').toString().trim();
    final ports = <int>[];
    void addPort(dynamic value) {
      final port = (value as num?)?.toInt();
      if (port != null && port > 0 && !ports.contains(port)) ports.add(port);
    }
    addPort(vless?['port']);
    addPort(hy2?['port']);
    addPort(wg?['port']);
    return (host.isEmpty ? null : host, ports);
  }
}

/// Sorts nodes for the picker: client ping (if measured) → load → name.
List<VpnNode> sortNodesForPicker(
  Iterable<VpnNode> nodes, {
  Map<String, int>? clientPingMs,
}) {
  final list = nodes.toList();
  list.sort((a, b) => _compareNodesForPicker(a, b, clientPingMs: clientPingMs));
  return list;
}

int _clientPingSortKey(VpnNode node, Map<String, int>? clientPingMs) {
  final ms = clientPingMs?[node.id];
  if (ms == null || ms <= 0) return 1 << 20;
  return ms;
}

int _compareNodesForPicker(VpnNode a, VpnNode b, {Map<String, int>? clientPingMs}) {
  if (clientPingMs != null && clientPingMs.isNotEmpty) {
    final ping = _clientPingSortKey(a, clientPingMs).compareTo(_clientPingSortKey(b, clientPingMs));
    if (ping != 0) return ping;
  }

  final load = a.loadPct.compareTo(b.loadPct);
  if (load != 0) return load;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
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

  /// Host:port the client actually dials for [transport] (for logs / diagnostics).
  String dialTarget(Transport transport) {
    switch (transport) {
      case Transport.wireguard:
        return endpoint;
      case Transport.vlessReality:
        final m = RegExp(r'^vless://[^@]+@([^:/?#]+):(\d+)').firstMatch(vlessUri);
        if (m != null) return '${m.group(1)}:${m.group(2)}';
        return endpoint;
      case Transport.hysteria2:
        final m = RegExp(r'^hysteria2://[^@]+@([^:/?#]+):(\d+)').firstMatch(hysteria2Uri);
        if (m != null) return '${m.group(1)}:${m.group(2)}';
        return endpoint;
    }
  }
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

  /// sing-box TUN address. [tunDnsAddress] is the tunnel DNS resolver on-device.
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
    /// When false (desktop CLI / unsigned macOS), only the local mixed proxy
    /// inbound is used — no TUN (avoids needing root). Pair with system HTTP proxy.
    bool useSystemTunnel = true,
  }) {
    if (!bundle.hasWireGuard) {
      throw StateError('credential bundle is missing wireguard fields');
    }
    if (transport == Transport.wireguard) {
      return _buildDirectWireGuard(
        bundle: bundle,
        clientPrivateKey: clientPrivateKey,
        useSystemTunnel: useSystemTunnel,
      );
    }
    return _buildStealth(
      bundle: bundle,
      transport: transport,
      clientPrivateKey: clientPrivateKey,
      useSystemTunnel: useSystemTunnel,
    );
  }

  /// Direct UDP WireGuard — mirrors the gateway's `client_conf` / wg-quick layout.
  static Map<String, dynamic> _buildDirectWireGuard({
    required CredentialBundle bundle,
    required String clientPrivateKey,
    bool useSystemTunnel = true,
  }) {
    final (host, port) = _splitHostPort(bundle.endpoint);
    final clientAddr =
        bundle.address.contains('/') ? bundle.address : '${bundle.address}/32';
    final dnsServer = bundle.dns.isNotEmpty ? bundle.dns : '1.1.1.1';

    return _withClashApi({
      'log': {'level': 'info'},
      'dns': _dnsConfig(
        remoteServer: dnsServer,
        wgTag: wgEndpointTag,
        tunInbound: useSystemTunnel,
      ),
      'inbounds': _inbounds(includeTun: useSystemTunnel),
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
    bool useSystemTunnel = true,
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

    final outbounds =
        ((profile['outbounds'] as List?)?.cast<Map<String, dynamic>>() ?? [])
            .map((o) => Map<String, dynamic>.from(o))
            .toList();
    // Node profiles ship carrier outbounds only; local bypass rules need `direct`.
    if (!outbounds.any((o) => o['tag'] == 'direct')) {
      outbounds.add({'type': 'direct', 'tag': 'direct'});
    }
    _patchStealthOutbounds(outbounds, transport, bundle);

    // Dial the carrier (VLESS/Hy2) on the underlying network, not through the TUN.
    final carrierHost = _carrierBypassHost(outbounds, transport, bundle);

    return _withClashApi({
      'log': {'level': 'info'},
      'dns': _dnsConfig(
        remoteServer: dnsServer,
        wgTag: wgEndpointTag,
        tunInbound: useSystemTunnel,
      ),
      'inbounds': _inbounds(includeTun: useSystemTunnel),
      'endpoints': endpoints,
      'outbounds': outbounds,
      'route': _route(
        finalTag: wgEndpointTag,
        wgServerHost: carrierHost,
        extraRules: extraRules,
      ),
    });
  }

  /// Ensures carrier outbounds carry REALITY/TLS params (from [bundle.vlessUri]
  /// when the cached profile is stale or incomplete).
  static void _patchStealthOutbounds(
    List<Map<String, dynamic>> outbounds,
    Transport transport,
    CredentialBundle bundle,
  ) {
    for (final ob in outbounds) {
      final tag = ob['tag']?.toString() ?? '';
      if (transport == Transport.vlessReality && tag == carrierVlessTag) {
        _patchVlessFromUri(ob, bundle.vlessUri);
      }
    }
  }

  static void _patchVlessFromUri(Map<String, dynamic> outbound, String vlessUri) {
    if (vlessUri.isEmpty) return;
    final m = RegExp(r'^vless://([^@]+)@([^:/?#]+):(\d+)\?([^#]*)').firstMatch(vlessUri);
    if (m == null) return;
    final uuid = m.group(1) ?? '';
    final host = m.group(2) ?? '';
    final port = int.tryParse(m.group(3) ?? '') ?? 443;
    final q = Uri.splitQueryString(m.group(4) ?? '');
    if (uuid.isNotEmpty) outbound['uuid'] = uuid;
    if (host.isNotEmpty) outbound['server'] = host;
    outbound['server_port'] = port;
    if (q['flow']?.isNotEmpty == true) outbound['flow'] = q['flow'];
    final tls = Map<String, dynamic>.from(
      (outbound['tls'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    tls['enabled'] = true;
    tls['server_name'] = q['sni'] ?? tls['server_name'] ?? 'www.microsoft.com';
    tls['utls'] = {
      'enabled': true,
      'fingerprint': q['fp'] ?? 'chrome',
    };
    final reality = Map<String, dynamic>.from(
      (tls['reality'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    if (q['pbk']?.isNotEmpty == true) reality['public_key'] = q['pbk'];
    if (q['sid']?.isNotEmpty == true) reality['short_id'] = q['sid'];
    reality['enabled'] = true;
    tls['reality'] = reality;
    outbound['tls'] = tls;
  }

  static String? _carrierBypassHost(
    List<Map<String, dynamic>> outbounds,
    Transport transport,
    CredentialBundle bundle,
  ) {
    final tag = switch (transport) {
      Transport.vlessReality => carrierVlessTag,
      Transport.hysteria2 => carrierHy2Tag,
      Transport.wireguard => null,
    };
    if (tag != null) {
      for (final ob in outbounds) {
        if (ob['tag'] == tag) {
          final host = ob['server']?.toString() ?? '';
          if (host.isNotEmpty) return host;
        }
      }
    }
    final (host, _) = _splitHostPort(bundle.endpoint);
    return host.isNotEmpty ? host : null;
  }

  static bool get _isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static Map<String, dynamic> _dnsConfig({
    required String remoteServer,
    required String wgTag,
    required bool tunInbound,
  }) {
    if (tunInbound && _isMacOS) {
      return {
        'servers': [
          {'tag': 'dns-local', 'address': 'local'},
          {'tag': 'dns-remote', 'address': remoteServer, 'detour': wgTag},
        ],
        'rules': [
          {'inbound': 'tun-in', 'server': 'dns-remote'},
        ],
        'final': 'dns-remote',
        'strategy': 'prefer_ipv4',
      };
    }
    return {
      'servers': [
        {'tag': 'dns-remote', 'address': remoteServer, 'detour': wgTag},
      ],
      'final': 'dns-remote',
      'strategy': 'prefer_ipv4',
    };
  }

  static List<Map<String, dynamic>> _inbounds({required bool includeTun}) {
    final inbounds = <Map<String, dynamic>>[];
    if (includeTun) {
      inbounds.add({
        'type': 'tun',
        'tag': 'tun-in',
        'address': [tunAddress],
        'auto_route': true,
        // macOS CLI TUN: strict_route often breaks DNS for system browsers.
        'strict_route': !_isMacOS,
        'stack': _isMacOS ? 'system' : 'gvisor',
        'sniff': true,
      });
    }
    inbounds.add({
      'type': 'mixed',
      'tag': localMixedInboundTag,
      'listen': localProxyHost,
      'listen_port': localProxyPort,
      'sniff': true,
    });
    return inbounds;
  }

  /// Local/bypass rules that must run before [final]. Tunnel DNS capture comes
  /// first so queries to [tunDnsAddress] reach sing-box's DNS module locally.
  /// (sing-box config action name: `hijack-dns`.)
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
