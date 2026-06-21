import 'package:erebrus_vpn/platform/platform_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usesReown is false when Solana Mobile device flag is set', () {
    PlatformCapabilities.isSolanaMobileDevice = true;
    addTearDown(() => PlatformCapabilities.isSolanaMobileDevice = false);
    expect(PlatformCapabilities.usesReown, isFalse);
  });

  test('usesReown is true on non-Solana-Mobile platforms', () {
    PlatformCapabilities.isSolanaMobileDevice = false;
    expect(PlatformCapabilities.usesReown, isTrue);
  });
}