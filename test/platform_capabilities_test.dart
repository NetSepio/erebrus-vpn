import 'package:erebrus_vpn/platform/platform_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => PlatformCapabilities.isSolanaMobileDevice = false);

  test('usesReown is false when Solana Mobile device flag is set', () {
    PlatformCapabilities.isSolanaMobileDevice = true;
    expect(PlatformCapabilities.usesReown, isFalse);
  });

  test('usesReown is false on desktop', () {
    PlatformCapabilities.isSolanaMobileDevice = false;
    if (PlatformCapabilities.isDesktop) {
      expect(PlatformCapabilities.usesReown, isFalse);
      expect(PlatformCapabilities.usesWebLogin, isTrue);
    }
  });

  test('usesWebLogin and usesReown are mutually exclusive on desktop', () {
    if (!PlatformCapabilities.isDesktop) return;
    expect(PlatformCapabilities.usesWebLogin, isTrue);
    expect(PlatformCapabilities.usesReown, isFalse);
  });
}