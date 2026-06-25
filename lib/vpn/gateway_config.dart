import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Production gateway — override at build time via `--dart-define=GATEWAY_URL=…`.
const kDefaultGatewayUrl = 'https://gateway.erebrus.io';

const kGatewayUrl = String.fromEnvironment(
  'GATEWAY_URL',
  defaultValue: kDefaultGatewayUrl,
);

/// v2 trial length (`trial_period=168h` in gateway platform_settings).
const kTrialPeriodDays = 7;

/// NFT gating grant (`nft_gate_period` — typically 30d).
const kNftEntitlementDays = 30;

/// Bounded label for gateway metrics / activity (`X-Erebrus-Client`).
String gatewayClientHeader() {
  if (kIsWeb) return 'webapp';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return 'webapp';
}