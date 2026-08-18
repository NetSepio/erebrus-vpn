import 'package:erebrus_vpn/auth/gateway_auth_client.dart';
import 'package:erebrus_vpn/vpn/gateway_client.dart';
import 'package:erebrus_vpn/vpn/gateway_errors.dart';
import 'package:erebrus_vpn/vpn/gateway_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth errors retain status and identify only 401 as expired', () {
    final expired = AuthException(
      'invalid or expired token',
      statusCode: 401,
      code: 'SESSION_EXPIRED',
    );
    final forbidden = AuthException('access denied', statusCode: 403);

    expect(expired.isSessionExpired, isTrue);
    expect(expired.code, 'SESSION_EXPIRED');
    expect(forbidden.isSessionExpired, isFalse);
  });

  test('gateway errors retain machine-readable envelope details', () {
    const body =
        '{"error":"invalid or expired token","code":"SESSION_EXPIRED"}';
    final error = GatewayException(
      GatewayHttp.errorMessage(401, body),
      statusCode: 401,
      code: GatewayHttp.errorCode(body),
    );

    expect(error.message, 'invalid or expired token');
    expect(error.code, 'SESSION_EXPIRED');
    expect(error.isSessionExpired, isTrue);
  });

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
