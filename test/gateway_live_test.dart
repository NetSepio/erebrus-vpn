import 'package:erebrus_vpn/view/home/node_display.dart';
import 'package:erebrus_vpn/vpn/gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live gateway is reachable', () async {
    final nodes = await GatewayClient().fetchNodes();
    expect(nodes, isNotEmpty);
    final n = nodes.first;
    expect(n.name, isNotEmpty);
    expect(n.zone, isNotEmpty);
    expect(n.org?.name, isNotEmpty);
    expect(n.walletAddress, isNotEmpty);
    expect(n.chain, isNotEmpty);

    final d = NodeDisplay.of(n, showActivity: true);
    expect(d.regionCompact.toLowerCase(), contains('east'));
    expect(d.org?.name, isNotEmpty);
    expect(d.showSolanaBadge, isTrue);
  }, skip: false);
}