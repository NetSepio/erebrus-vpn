import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

import '../platform/platform_capabilities.dart';
import 'auth_config.dart';

bool? _solanaMobileDeviceCache;

/// True on Solana Mobile hardware (Seeker, Saga) — not generic Android.
bool get isSolanaMobileDevice => _solanaMobileDeviceCache ?? false;

/// Detects Seeker/Saga devices via Android build metadata.
Future<bool> detectSolanaMobileDevice() async {
  if (_solanaMobileDeviceCache != null) return _solanaMobileDeviceCache!;

  if (kIsWeb || !Platform.isAndroid) {
    _solanaMobileDeviceCache = false;
    return false;
  }

  try {
    final info = await DeviceInfoPlugin().androidInfo;
    _solanaMobileDeviceCache = _isSolanaMobileAndroid(info);
    PlatformCapabilities.isSolanaMobileDevice = _solanaMobileDeviceCache!;
    debugPrint(
      '[MWA] device=${info.brand}/${info.model} solanaMobile=$_solanaMobileDeviceCache',
    );
    return _solanaMobileDeviceCache!;
  } catch (e) {
    debugPrint('[MWA] device detection failed: $e');
    _solanaMobileDeviceCache = false;
    return false;
  }
}

bool _isSolanaMobileAndroid(AndroidDeviceInfo info) {
  final brand = info.brand.toLowerCase();
  final manufacturer = info.manufacturer.toLowerCase();
  final model = info.model.toLowerCase();
  final device = info.device.toLowerCase();
  final product = info.product.toLowerCase();

  if (brand == 'solanamobile' || brand.contains('solana')) return true;
  if (manufacturer.contains('solana mobile') || manufacturer.contains('solanamobile')) {
    return true;
  }
  const markers = ['seeker', 'saga', 'solana mobile'];
  for (final m in markers) {
    if (model.contains(m) || device.contains(m) || product.contains(m)) return true;
  }
  return false;
}

/// Opens MWA: wallet selector activity + local websocket in parallel.
Future<({LocalAssociationScenario scenario, MobileWalletAdapterClient client})> _openMwaSession() async {
  final scenario = await LocalAssociationScenario.create();
  // Must not await — start() must listen while the wallet activity is open.
  unawaited(scenario.startActivityForResult(null));
  debugPrint('[MWA] waiting for wallet association…');
  final client = await scenario.start();
  debugPrint('[MWA] wallet associated');
  return (scenario: scenario, client: client);
}

/// Authorize or reauthorize via Mobile Wallet Adapter (native wallet selector).
Future<SolanaMobileAuthResult?> connectSolanaMobile({String? storedAuthToken}) async {
  if (!isSolanaMobileDevice) return null;

  LocalAssociationScenario? scenario;
  try {
    final session = await _openMwaSession();
    scenario = session.scenario;
    final client = session.client;

    AuthorizationResult? auth;
    if (storedAuthToken != null && storedAuthToken.isNotEmpty) {
      auth = await client.reauthorize(
        identityUri: Uri.parse(kErebrusSiteUrl),
        iconUri: Uri.parse(kErebrusSiteIcon),
        identityName: 'Erebrus VPN',
        authToken: storedAuthToken,
      );
    }
    auth ??= await client.authorize(
      identityUri: Uri.parse(kErebrusSiteUrl),
      iconUri: Uri.parse(kErebrusSiteIcon),
      identityName: 'Erebrus VPN',
      cluster: 'mainnet-beta',
    );
    if (auth == null) {
      debugPrint('[MWA] authorize returned null (cancelled or wallet error)');
      return null;
    }

    return SolanaMobileAuthResult(
      authToken: auth.authToken,
      publicKey: auth.publicKey,
      address: base58.encode(auth.publicKey),
    );
  } catch (e) {
    debugPrint('[MWA] connect failed: $e');
    return null;
  } finally {
    await scenario?.close();
  }
}

/// Signs a UTF-8 challenge with the authorized MWA session.
Future<String?> signSolanaMobileMessage({
  required String mwaAuthToken,
  required Uint8List publicKey,
  required String message,
}) async {
  if (!isSolanaMobileDevice) return null;

  LocalAssociationScenario? scenario;
  try {
    final session = await _openMwaSession();
    scenario = session.scenario;
    final client = session.client;

    final reauth = await client.reauthorize(
      identityUri: Uri.parse(kErebrusSiteUrl),
      iconUri: Uri.parse(kErebrusSiteIcon),
      identityName: 'Erebrus VPN',
      authToken: mwaAuthToken,
    );
    if (reauth == null) return null;

    final result = await client.signMessages(
      messages: [Uint8List.fromList(utf8.encode(message))],
      addresses: [publicKey],
    );
    if (result.signedMessages.isEmpty) return null;
    final sigs = result.signedMessages.first.signatures;
    if (sigs.isEmpty) return null;
    // Gateway CheckSignSol expects hex-encoded ed25519 signatures.
    return sigs.first.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  } catch (e) {
    debugPrint('[MWA] sign failed: $e');
    return null;
  } finally {
    await scenario?.close();
  }
}

Future<void> disconnectSolanaMobile(String? mwaAuthToken) async {
  if (!isSolanaMobileDevice || mwaAuthToken == null || mwaAuthToken.isEmpty) {
    return;
  }
  LocalAssociationScenario? scenario;
  try {
    final session = await _openMwaSession();
    scenario = session.scenario;
    await session.client.deauthorize(authToken: mwaAuthToken);
  } catch (_) {
  } finally {
    await scenario?.close();
  }
}

class SolanaMobileAuthResult {
  const SolanaMobileAuthResult({
    required this.authToken,
    required this.publicKey,
    required this.address,
  });

  final String authToken;
  final Uint8List publicKey;
  final String address;
}