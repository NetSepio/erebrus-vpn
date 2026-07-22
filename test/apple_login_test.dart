import 'package:erebrus_vpn/auth/gateway_auth_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple login sends every gateway-required credential value', () {
    final payload = GatewayAuthClient.appleLoginPayload(
      idToken: 'identity-token',
      authorizationCode: 'authorization-code',
      nonce: 'request-nonce',
      state: 'request-state',
    );

    expect(payload, {
      'id_token': 'identity-token',
      'authorization_code': 'authorization-code',
      'nonce': 'request-nonce',
      'state': 'request-state',
    });
  });
}
