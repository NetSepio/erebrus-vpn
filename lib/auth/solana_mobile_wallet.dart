import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

import 'auth_config.dart';

/// True on Android devices where Mobile Wallet Adapter can be used (Seeker, Saga, etc.).
bool get solanaMobilePlatformSupported => !kIsWeb && Platform.isAndroid;

/// Authorize or reauthorize with Seed Vault / Solana Mobile Wallet Adapter.
Future<SolanaMobileAuthResult?> connectSolanaMobile({String? storedAuthToken}) async {
  if (!solanaMobilePlatformSupported) return null;

  LocalAssociationScenario? scenario;
  try {
    scenario = await LocalAssociationScenario.create();
    await scenario.startActivityForResult(null);
    final client = await scenario.start();

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
    if (auth == null) return null;

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
  if (!solanaMobilePlatformSupported) return null;

  LocalAssociationScenario? scenario;
  try {
    scenario = await LocalAssociationScenario.create();
    await scenario.startActivityForResult(null);
    final client = await scenario.start();

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
    return base64Encode(sigs.first);
  } catch (e) {
    debugPrint('[MWA] sign failed: $e');
    return null;
  } finally {
    await scenario?.close();
  }
}

Future<void> disconnectSolanaMobile(String? mwaAuthToken) async {
  if (!solanaMobilePlatformSupported || mwaAuthToken == null || mwaAuthToken.isEmpty) {
    return;
  }
  LocalAssociationScenario? scenario;
  try {
    scenario = await LocalAssociationScenario.create();
    await scenario.startActivityForResult(null);
    final client = await scenario.start();
    await client.deauthorize(authToken: mwaAuthToken);
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