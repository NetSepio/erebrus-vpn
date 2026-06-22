import 'package:erebrus_vpn/auth/desktop_web_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isAuthCallback matches erebrusvpn://auth', () {
    expect(DesktopWebAuth.isAuthCallback('erebrusvpn://auth?token=abc'), isTrue);
    expect(DesktopWebAuth.isAuthCallback('erebrusvpn://other'), isFalse);
  });

  test('parseCallback reads token and metadata from query', () {
    DesktopWebAuth.buildLoginUrl();
    final state = DesktopWebAuth.pendingState!;
    final url =
        'erebrusvpn://auth?token=paseto-token&user_id=u1&wallet=So111&role=user&state=$state';
    final parsed = DesktopWebAuth.parseCallback(url);
    expect(parsed, isNotNull);
    expect(parsed!.token, 'paseto-token');
    expect(parsed.userId, 'u1');
    expect(parsed.walletAddress, 'So111');
    expect(parsed.role, 'user');
    expect(parsed.state, state);
    expect(parsed.isValid, isTrue);
  });

  test('parseCallback accepts paseto alias', () {
    DesktopWebAuth.buildLoginUrl();
    final state = DesktopWebAuth.pendingState!;
    final parsed = DesktopWebAuth.parseCallback(
      'erebrusvpn://auth?paseto=tok&user_id=u&wallet=w&state=$state',
    );
    expect(parsed?.token, 'tok');
  });

  test('validateState rejects mismatched state', () {
    DesktopWebAuth.buildLoginUrl();
    expect(
      () => DesktopWebAuth.validateState('wrong-state'),
      throwsA(isA<DesktopWebAuthException>()),
    );
  });

  test('parseManualAuthInput accepts raw PASETO', () {
    const token = 'v4.local.abc.def';
    final parsed = DesktopWebAuth.parseManualAuthInput(token);
    expect(parsed?.token, token);
  });

  test('parseManualAuthInput accepts query string fragment', () {
    final parsed = DesktopWebAuth.parseManualAuthInput(
      'token=tok&user_id=u1&wallet=So111&role=user&state=abc',
    );
    expect(parsed?.token, 'tok');
    expect(parsed?.userId, 'u1');
    expect(parsed?.walletAddress, 'So111');
  });

  test('buildLoginUrl includes redirect_uri and platform', () {
    final url = DesktopWebAuth.buildLoginUrl();
    final uri = Uri.parse(url);
    expect(uri.path, '/auth');
    expect(uri.queryParameters['redirect_uri'], 'erebrusvpn://auth');
    expect(uri.queryParameters['platform'], isNotEmpty);
    expect(uri.queryParameters['state'], isNotEmpty);
  });
}