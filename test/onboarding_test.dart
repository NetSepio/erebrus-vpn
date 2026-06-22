import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:erebrus_vpn/onboarding/onboarding_view.dart';
import 'package:erebrus_vpn/theme/app_theme.dart';

void main() {
  // The mesh floats/breathes on infinite controllers, so we drive frames with
  // pump(Duration) and never pumpAndSettle.
  Future<void> mount(WidgetTester tester, VoidCallback onDone) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: OnboardingView(onDone: onDone),
    ));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('walks through all four steps to "Get started"', (tester) async {
    var done = false;
    await mount(tester, () => done = true);

    // Step 1
    expect(find.text('01 / WELCOME'), findsOneWidget);
    expect(find.text('A private internet for everything you own'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('SKIP'), findsOneWidget);

    // Step 2
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('02 / THE AGENTIC INTERNET'), findsOneWidget);

    // Step 3 — bullets
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('03 / HOW IT WORKS'), findsOneWidget);
    expect(find.text('Connect once'), findsOneWidget);
    expect(find.text('Use sovereign AI'), findsOneWidget);

    // Step 4 — last step: button becomes "Get started", SKIP hidden
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('04 / GET STARTED'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('SKIP'), findsNothing);

    // Finish
    expect(done, isFalse);
    await tester.tap(find.text('Get started'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(done, isTrue);
  });

  testWidgets('SKIP finishes onboarding immediately', (tester) async {
    var done = false;
    await mount(tester, () => done = true);
    await tester.tap(find.text('SKIP'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(done, isTrue);
  });
}
