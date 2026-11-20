import 'package:erebrus_vpn/view/root_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Android blanks the recents thumbnail with FLAG_SECURE. Apple platforms have
/// no equivalent, so the cover is the whole mechanism there — and it has to be
/// up on `inactive`, which is the state the snapshot is taken in, not on
/// `paused`, which is after.
void main() {
  Finder cover() => find.byKey(const ValueKey('privacy-cover'));

  testWidgets('covers the UI while inactive on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      const MaterialApp(home: PrivacyCover(child: Text('node list'))),
    );
    expect(cover(), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(cover(), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(cover(), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('does nothing on Android, where FLAG_SECURE covers it',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      const MaterialApp(home: PrivacyCover(child: Text('node list'))),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(cover(), findsNothing);
    expect(find.text('node list'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
