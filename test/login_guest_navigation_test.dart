import 'package:erebrus_vpn/auth/gateway_auth_client.dart';
import 'package:erebrus_vpn/auth/wallet_auth_controller.dart';
import 'package:erebrus_vpn/theme/app_theme.dart';
import 'package:erebrus_vpn/view/auth/login_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _TestAuthController extends WalletAuthController {
  @override
  Future<void> loadPersistedSession() async {
    sessionReady.value = true;
  }

  @override
  Future<void> loadAuthMethods() async {
    authMethods.value = const AuthMethods(email: true);
    appleDeviceReady.value = false;
  }
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<WalletAuthController>(_TestAuthController());
  });

  tearDown(Get.reset);

  testWidgets('Continue as guest returns to the guest app route', (
    tester,
  ) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LoginView()),
                ),
                child: const Text('Open login'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open login'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('continue-as-guest')), findsOneWidget);
    expect(find.text('CONTINUE AS GUEST'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('continue-as-guest')));
    await tester.pumpAndSettle();

    expect(find.text('Open login'), findsOneWidget);
    expect(find.byType(LoginView), findsNothing);
  });
}
