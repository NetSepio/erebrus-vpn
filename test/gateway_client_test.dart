import 'package:erebrus_vpn/view/home/node_display.dart';
import 'package:erebrus_vpn/vpn/gateway_client.dart';
import 'package:erebrus_vpn/vpn/vpn_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VpnNode parses gateway discovery payload', () {
    final node = VpnNode.fromJson({
      'node_id': '59d52ecd-dfc3-41c2-90a4-0d2495a239e2',
      'name': 'erebrus-nexus',
      'region': 'NO',
      'did': 'did:erebrus:test',
      'protocols': ['wireguard', 'vless-reality'],
      'load_pct': 14.68,
      'status': 'online',
      'access_mode': 'public',
      'min_tier': 1,
      'speedtest': {
        'latency_ms': 42,
        'download_mbps': 128.4,
        'upload_mbps': 44.2,
        'measured_at': 1710000000,
      },
      'zone': 'east',
      'peer_id': '12D3KooWTestPeer',
      'wallet_address': '9SXo8wiAdsDBQPUKk4LFN73T4DcueYhPDRN3p6wTsgaR',
      'chain': 'SOLANA',
      'version': '2.0.0-abc1234',
      'last_heartbeat': DateTime.now().toUtc().subtract(const Duration(seconds: 13)).toIso8601String(),
      'org': {'name': 'clawbrick', 'kind': 'team', 'verified': false, 'slug': 'clawbrick'},
      'endpoints': {
        'wireguard': {'host': '203.0.113.10', 'port': 51820, 'public_key': 'abc'},
        'vless_reality': {'port': 443, 'public_key': 'def', 'short_ids': ['01'], 'sni': 'example.com'},
      },
    });
    expect(node.id, '59d52ecd-dfc3-41c2-90a4-0d2495a239e2');
    expect(node.name, 'erebrus-nexus');
    expect(node.supportsStealth, isTrue);
    expect(node.minTier, 1);
    expect(node.latencyMs, 42);
    expect(node.downloadMbps, 128.4);
    expect(node.uploadMbps, 44.2);
    expect(node.org?.name, 'clawbrick');
    expect(node.zone, 'east');
    expect(node.peerId, '12D3KooWTestPeer');
    expect(node.walletAddress, '9SXo8wiAdsDBQPUKk4LFN73T4DcueYhPDRN3p6wTsgaR');
    expect(node.chain, 'SOLANA');
    expect(node.isSolana, isTrue);
    expect(node.version, '2.0.0-abc1234');
    expect(node.hasHeartbeat, isTrue);
    expect(node.org?.verified, isFalse);

    final display = NodeDisplay.of(node, showActivity: true);
    expect(display.showSolanaBadge, isTrue);
    expect(display.regionCompact, 'NO-East');
    expect(display.activityTime, isNotNull);
    expect(display.activityLive, isTrue);
    expect(display.downloadLabel, '128');
    expect(display.uploadLabel, '44.2');
    expect(display.showNodeSpeedtest, isTrue);
    expect(node.protocolsLabel, 'WG · VLESS');
    expect(node.probeHost, '203.0.113.10');
    expect(node.probePorts, [443, 51820]);
    expect(node.hasReportedSpeedtest, isTrue);
    expect(node.requiresHigherTier, isTrue);
  });

  test('NodeDisplay activity uses latest heartbeat or peer handshake', () {
    final now = DateTime.now().toUtc();
    final recentBeat = now.subtract(const Duration(seconds: 20)).toIso8601String();
    final olderPeer = now.subtract(const Duration(minutes: 5)).toIso8601String();
    final recentPeer = now.subtract(const Duration(seconds: 40)).toIso8601String();

    final fromHeartbeat = NodeDisplay.of(
      VpnNode.fromJson({
        'node_id': 'a',
        'name': 'alpha',
        'region': 'US',
        'did': 'did:1',
        'protocols': ['wireguard'],
        'last_heartbeat': recentBeat,
        'last_peer_handshake': olderPeer,
      }),
      showActivity: true,
    );
    expect(fromHeartbeat.activityLive, isTrue);
    expect(fromHeartbeat.activityTime, contains('s ago'));

    final fromPeer = NodeDisplay.of(
      VpnNode.fromJson({
        'node_id': 'b',
        'name': 'beta',
        'region': 'US',
        'did': 'did:2',
        'protocols': ['wireguard'],
        'last_heartbeat': olderPeer,
        'last_peer_handshake': recentPeer,
      }),
      showActivity: true,
    );
    expect(fromPeer.activityLive, isTrue);
    expect(fromPeer.activityTime, contains('s ago'));
  });

  test('sortNodesForPicker ranks client ping then load', () {
    final nodes = sortNodesForPicker(
      [
        VpnNode(
          id: 'b',
          name: 'beta',
          region: 'US',
          did: 'did:1',
          protocols: const ['wireguard'],
          loadPct: 5,
        ),
        VpnNode(
          id: 'a',
          name: 'alpha',
          region: 'NO',
          did: 'did:2',
          protocols: const ['wireguard'],
          loadPct: 40,
        ),
      ],
      clientPingMs: const {'a': 120, 'b': 45},
    );

    expect(nodes.map((n) => n.id).toList(), ['b', 'a']);
  });

  test('sortNodesForPicker ranks load then name', () {
    final nodes = sortNodesForPicker([
      VpnNode(
        id: 'b',
        name: 'beta',
        region: 'US',
        did: 'did:1',
        protocols: const ['wireguard'],
        loadPct: 10,
      ),
      VpnNode(
        id: 'a',
        name: 'alpha',
        region: 'NO',
        did: 'did:2',
        protocols: const ['wireguard'],
        loadPct: 40,
      ),
      VpnNode(
        id: 'c',
        name: 'gamma',
        region: 'DE',
        did: 'did:3',
        protocols: const ['wireguard'],
        loadPct: 5,
      ),
    ]);

    expect(nodes.map((n) => n.id).toList(), ['c', 'b', 'a']);
  });

  test('VpnNodeOrg parses the verification_status org shape', () {
    final org = VpnNodeOrg.fromJson({
      'id': '5de0115a-0000-0000-0000-000000000000',
      'name': 'clawbrick',
      'slug': 'clawbrick',
      'plan': 'team',
      'verification_status': 'verified',
      'display_name': 'Clawbrick Labs',
      'website_url': 'https://clawbrick.io',
    });
    expect(org.verified, isTrue);
    expect(org.verificationStatus, 'verified');
    expect(org.label, 'Clawbrick Labs');
    expect(org.website, 'https://clawbrick.io');
    expect(org.id, isNotNull);
  });

  test('VpnNodeOrg still parses the legacy verified/kind shape', () {
    final org = VpnNodeOrg.fromJson({
      'name': 'clawbrick',
      'kind': 'team',
      'verified': false,
      'slug': 'clawbrick',
    });
    expect(org.verified, isFalse);
    expect(org.kind, 'team');
    expect(org.label, 'clawbrick'); // falls back to name when no display_name
  });

  test('VpnOrg parses the /orgs list shape', () {
    final org = VpnOrg.fromJson({
      'name': 'Clawbrick',
      'slug': 'clawbrick',
      'role': 'member',
      'plan': 'team',
      'verification_status': 'verified',
    });
    expect(org.slug, 'clawbrick');
    expect(org.role, 'member');
    expect(org.verified, isTrue);
    expect(org.id, isNull); // omitted for non-privileged members
  });

  test('GatewayClient defaults to production gateway', () {
    final c = GatewayClient(baseUrl: 'https://gateway.erebrus.io');
    expect(c.baseUrl, 'https://gateway.erebrus.io');
  });

  test('GatewayClient normalizes dev base URL', () {
    final c = GatewayClient(baseUrl: 'http://212.147.232.36:8080');
    expect(c.baseUrl, 'http://212.147.232.36:8080');
  });
}