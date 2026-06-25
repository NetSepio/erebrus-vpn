import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../auth/runtime_config.dart';

/// Production gateway — override at build time via `--dart-define=GATEWAY_URL=…`
/// or project-root `.env` (bundled on mobile).
const kDefaultGatewayUrl = 'https://gateway.erebrus.io';

const _kGatewayUrlDefine = String.fromEnvironment('GATEWAY_URL', defaultValue: '');

/// Resolved gateway base URL (dart-define → bundled `.env` → production default).
String resolveGatewayUrl() {
  final fromDefine = _kGatewayUrlDefine.trim();
  if (fromDefine.isNotEmpty) return fromDefine;
  final fromEnv = RuntimeConfig.gatewayUrl.trim();
  if (fromEnv.isNotEmpty) return fromEnv;
  return kDefaultGatewayUrl;
}

/// Compile-time override when set; otherwise empty (use [resolveGatewayUrl]).
const kGatewayUrl = _kGatewayUrlDefine;

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