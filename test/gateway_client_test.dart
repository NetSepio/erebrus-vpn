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
    });
    expect(node.id, '59d52ecd-dfc3-41c2-90a4-0d2495a239e2');
    expect(node.name, 'erebrus-nexus');
    expect(node.supportsStealth, isTrue);
  });

  test('GatewayClient normalizes base URL', () {
    final c = GatewayClient(baseUrl: '212.147.232.36:8080');
    expect(c.baseUrl, 'http://212.147.232.36:8080');
  });
}