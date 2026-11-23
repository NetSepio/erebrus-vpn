import 'dart:async';

import 'package:erebrus_vpn/auth/auth_repository.dart';
import 'package:erebrus_vpn/auth/auth_session.dart';
import 'package:erebrus_vpn/auth/auth_session_store.dart';
import 'package:erebrus_vpn/auth/wallet_auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Secure storage answers at once; the gateway never does. That is a slow,
/// lossy or blocked network — and for a VPN app, a blocked gateway is a normal
/// Tuesday, not an edge case.
class _StalledGatewayRepository extends AuthRepository {
  _StalledGatewayRepository(this._stored)
      : super(gatewayUrl: 'https://gateway.invalid');

  final StoredAuthSession? _stored;
  int ensureFreshCalls = 0;

  @override
  Future<StoredAuthSession?> restore() async => _stored;

  @override
  Future<void> ensureFresh() {
    ensureFreshCalls += 1;
    // Never completes.
    return Completer<void>().future;
  }
}

StoredAuthSession _session() => StoredAuthSession(
      credentials: const AuthSession(
        token: 'paseto',
        userId: 'user-1',
        role: 'user',
        walletAddress: 'wallet-1',
      ),
      authMethod: 'wallet',
    );

/// Launch must never wait on the network.
///
/// `main()` used to await `loadPersistedSession`, which awaited a token
/// refresh, an entitlement read and a profile read — three sequential gateway
/// round-trips at 8–12s timeouts each — before `runApp`. On a bad network that
/// was half a minute of black screen before any UI: no splash, no error, just
/// an app that looks crashed, and a start-up the OS may kill. The splash exists
/// to cover the restore; it cannot cover a frame that never arrives.
void main() {
  test('the restore lifts the splash without waiting for the gateway', () async {
    final repo = _StalledGatewayRepository(_session());
    final auth = WalletAuthController(repository: repo);

    // The timeout is the assertion: re-awaiting the gateway calls inside
    // loadPersistedSession hangs here instead of shipping.
    await auth.loadPersistedSession().timeout(const Duration(seconds: 2));

    expect(auth.sessionReady.value, isTrue,
        reason: 'the UI must be allowed to render on the storage read alone');
    expect(auth.walletAddress.value, 'wallet-1');
    expect(auth.sessionActive.value, isTrue);
    expect(repo.ensureFreshCalls, 1,
        reason: 'the refresh still happens, just behind the UI');
  });

  test('a device with no stored session is ready immediately', () async {
    final repo = _StalledGatewayRepository(null);
    final auth = WalletAuthController(repository: repo);

    await auth.loadPersistedSession().timeout(const Duration(seconds: 2));

    expect(auth.sessionReady.value, isTrue);
    expect(auth.sessionActive.value, isFalse);
    expect(auth.entitlement.value.entitled, isFalse);
    expect(repo.ensureFreshCalls, 0,
        reason: 'nothing to refresh, so nothing should be dialled');
  });
}
