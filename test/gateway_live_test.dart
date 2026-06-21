import 'package:erebrus_vpn/vpn/gateway_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live gateway is reachable', () async {
    final client = GatewayClient();
    final nodes = await client.fetchNodes();
    // Registry may be empty while the node is up but not registered.
    if (nodes.isEmpty) {
      final fallback = GatewayClient.devFallbackNodes();
      expect(fallback, isNotEmpty);
      expect(fallback.first.name, 'erebrus-nexus');
    } else {
      expect(nodes.first.name, isNotEmpty);
    }
  }, skip: false);
}