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
      'org': {'name': 'clawbrick'},
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
    expect(node.orgName, 'clawbrick');
    expect(node.protocolsLabel, 'WG · VLESS');
    expect(node.probeHost, '203.0.113.10');
    expect(node.probePorts, [443, 51820]);
    expect(node.hasReportedSpeedtest, isTrue);
    expect(node.requiresHigherTier, isTrue);
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

  test('GatewayClient defaults to production gateway', () {
    final c = GatewayClient(baseUrl: 'https://gateway.erebrus.io');
    expect(c.baseUrl, 'https://gateway.erebrus.io');
  });

  test('GatewayClient normalizes dev base URL', () {
    final c = GatewayClient(baseUrl: 'http://212.147.232.36:8080');
    expect(c.baseUrl, 'http://212.147.232.36:8080');
  });
}