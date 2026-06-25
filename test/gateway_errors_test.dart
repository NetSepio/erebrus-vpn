import 'package:erebrus_vpn/vpn/gateway_client.dart';
import 'package:erebrus_vpn/vpn/gateway_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('friendlyGatewayError maps node unreachable', () {
    final msg = friendlyGatewayError(
      GatewayException('node unreachable — no client created'),
      nodeName: 'erebrus-nexus',
    );
    expect(msg, contains('erebrus-nexus'));
    expect(msg, contains('9080'));
  });

  test('friendlyGatewayError maps subscription gate', () {
    final msg = friendlyGatewayError(
      GatewayException('no active subscription — start a trial or subscribe'),
    );
    expect(msg, contains('free trial'));
  });

  test('friendlyGatewayError maps tier gate', () {
    final msg = friendlyGatewayError(
      GatewayException('node requires a higher tier'),
    );
    expect(msg, contains('tier'));
  });

  test('friendlyGatewayError maps private node', () {
    final msg = friendlyGatewayError(
      GatewayException('private node — org membership required'),
    );
    expect(msg, contains('private'));
  });
}