import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:reown_appkit/reown_appkit.dart';

import 'auth_config.dart';
import 'deep_link_handler.dart';
import 'entitlement_state.dart';
import 'gateway_auth_client.dart';
import '../vpn/gateway_controller.dart';

/// Solana wallet login via Reown AppKit + gateway v2 signature auth.
class WalletAuthController extends GetxController {
  WalletAuthController({
    GatewayAuthClient? authClient,
    FlutterSecureStorage? storage,
  })  : _authClient = authClient ?? GatewayAuthClient(),
        _storage = storage ?? const FlutterSecureStorage();

  final GatewayAuthClient _authClient;
  final FlutterSecureStorage _storage;

  ReownAppKitModal? appKitModal;

  final walletAddress = ''.obs;
  final userId = ''.obs;
  final role = ''.obs;
  final isAuthenticating = false.obs;
  final reownReady = false.obs;
  final authError = RxnString();
  final entitlement = EntitlementState.none.obs;
  final isLoadingEntitlement = false.obs;
  final isStartingTrial = false.obs;
  final entitlementError = RxnString();

  String? _token;

  static const _kToken = 'erebrus_gateway_token';
  static const _kWallet = 'erebrus_wallet_address';
  static const _kUserId = 'erebrus_user_id';
  static const _kRole = 'erebrus_user_role';

  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  bool get isEntitled => entitlement.value.entitled;
  String? get bearerToken => _token;

  @override
  void onInit() {
    super.onInit();
    _restoreSession();
  }

  @override
  void onClose() {
    appKitModal?.onModalConnect.unsubscribe(_onModalConnect);
    appKitModal?.onModalDisconnect.unsubscribe(_onModalDisconnect);
    appKitModal?.onModalError.unsubscribe(_onModalError);
    super.onClose();
  }

  Future<void> initReown(BuildContext context) async {
    if (appKitModal != null) {
      reownReady.value = true;
      return;
    }

    ReownAppKitModalNetworks.removeSupportedNetworks('eip155');
    ReownAppKitModalNetworks.removeTestNetworks();

    final solanaChains =
        ReownAppKitModalNetworks.getAllSupportedNetworks(namespace: 'solana');
    final solanaNamespaces = solanaChains.isEmpty
        ? null
        : {
            'solana': RequiredNamespace(
              chains: solanaChains.map((c) => c.chainId).toList(),
              methods: const [
                'solana_signMessage',
                'solana_signTransaction',
              ],
              events: const [],
            ),
          };

    appKitModal = ReownAppKitModal(
      context: context,
      projectId: kReownProjectId,
      logLevel: LogLevel.error,
      metadata: PairingMetadata(
        name: 'Erebrus VPN',
        description: 'Private, stealth-capable DePIN VPN',
        url: kErebrusSiteUrl,
        icons: [kErebrusSiteIcon],
        redirect: const Redirect(
          native: kErebrusNativeRedirect,
          universal: kErebrusUniversalRedirect,
          // Native `erebrusvpn://` — universal links not on erebrus.io yet.
          linkMode: false,
        ),
      ),
      optionalNamespaces: solanaNamespaces,
      featuresConfig: FeaturesConfig(showMainWallets: true),
      disconnectOnDispose: false,
    );

    try {
      debugPrint('[Reown] initializing AppKit (project $kReownProjectId)');
      await appKitModal!.init();
      appKitModal!.onModalConnect.subscribe(_onModalConnect);
      appKitModal!.onModalDisconnect.subscribe(_onModalDisconnect);
      appKitModal!.onModalError.subscribe(_onModalError);

      DeepLinkHandler.bind(this);
      DeepLinkHandler.checkInitialLink();
      reownReady.value = true;
      debugPrint('[Reown] ready — Solana wallets available');

      if (appKitModal!.isConnected) {
        await _authenticateConnectedWallet();
      }
    } catch (e) {
      debugPrint('[Reown] init failed: $e');
      authError.value = 'Wallet connect failed to start: $e';
      reownReady.value = false;
    }
  }

  Future<void> openWalletModal() async {
    authError.value = null;
    if (appKitModal == null || !reownReady.value) {
      authError.value = 'Wallet connect is still starting — try again in a moment';
      return;
    }
    await appKitModal!.openModalView();
  }

  Future<void> signOut() async {
    authError.value = null;
    entitlementError.value = null;
    entitlement.value = EntitlementState.none;
    _token = null;
    walletAddress.value = '';
    userId.value = '';
    role.value = '';
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kWallet);
    await _storage.delete(key: _kUserId);
    await _storage.delete(key: _kRole);
    if (appKitModal?.isConnected == true) {
      await appKitModal?.disconnect();
    }
    _syncGatewayToken();
  }

  Future<void> _restoreSession() async {
    _token = await _storage.read(key: _kToken);
    walletAddress.value = await _storage.read(key: _kWallet) ?? '';
    userId.value = await _storage.read(key: _kUserId) ?? '';
    role.value = await _storage.read(key: _kRole) ?? '';
    _syncGatewayToken();
    if (isAuthenticated) {
      await refreshEntitlement();
    } else {
      entitlement.value = EntitlementState.none;
    }
  }

  /// Loads subscription state from `GET /api/v2/subscriptions`.
  Future<void> refreshEntitlement() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      entitlement.value = EntitlementState.none;
      return;
    }
    isLoadingEntitlement.value = true;
    entitlementError.value = null;
    try {
      entitlement.value = await _authClient.fetchSubscription(token);
    } on AuthException catch (e) {
      entitlementError.value = e.message;
      entitlement.value = EntitlementState.none;
    } catch (e) {
      entitlementError.value = e.toString();
      entitlement.value = EntitlementState.none;
    } finally {
      isLoadingEntitlement.value = false;
    }
  }

  /// Activates the one-time 14-day pro trial via `POST /api/v2/subscriptions/trial`.
  Future<void> startFreeTrial() async {
    if (!isAuthenticated) {
      entitlementError.value = 'Connect your Solana wallet first';
      return;
    }
    if (isEntitled) return;

    isStartingTrial.value = true;
    entitlementError.value = null;
    try {
      entitlement.value = await _authClient.startTrial(_token!);
    } on AuthException catch (e) {
      entitlementError.value = e.message;
    } catch (e) {
      entitlementError.value = e.toString();
    } finally {
      isStartingTrial.value = false;
    }
  }

  Future<void> _persistSession(AuthSession session) async {
    _token = session.token;
    walletAddress.value = session.walletAddress;
    userId.value = session.userId;
    role.value = session.role;
    await _storage.write(key: _kToken, value: session.token);
    await _storage.write(key: _kWallet, value: session.walletAddress);
    await _storage.write(key: _kUserId, value: session.userId);
    await _storage.write(key: _kRole, value: session.role);
    _syncGatewayToken();
  }

  void _syncGatewayToken() {
    if (Get.isRegistered<GatewayController>()) {
      Get.find<GatewayController>().setBearerToken(_token);
    }
  }

  void _onModalConnect(ModalConnect? event) {
    if (event != null) _authenticateConnectedWallet();
  }

  void _onModalDisconnect(ModalDisconnect? event) {}

  void _onModalError(ModalError? event) {
    if (event?.message != null && event!.message.isNotEmpty) {
      authError.value = event.message;
    }
  }

  Future<void> _authenticateConnectedWallet() async {
    final modal = appKitModal;
    if (modal == null || !modal.isConnected) return;

    final address = await _solanaAddress(modal);
    if (address == null || address.isEmpty) {
      authError.value = 'Connect a Solana wallet';
      return;
    }

    isAuthenticating.value = true;
    authError.value = null;
    try {
      final challenge = await _authClient.fetchFlowId(walletAddress: address);
      final signature = await _signChallenge(modal, address, challenge.message);
      final session = await _authClient.authenticate(
        flowId: challenge.flowId,
        signature: signature,
        publicKey: address,
      );
      await _persistSession(session);
      await refreshEntitlement();
      if (modal.isOpen) modal.closeModal();
      debugPrint('[Reown] gateway auth OK for $address');
    } on AuthException catch (e) {
      authError.value = e.message;
    } catch (e) {
      authError.value = e.toString();
    } finally {
      isAuthenticating.value = false;
    }
  }

  Future<String?> _solanaAddress(ReownAppKitModal modal) async {
    final chainId = modal.selectedChain?.chainId ?? '';
    if (!chainId.startsWith('solana:')) {
      final solChains =
          ReownAppKitModalNetworks.getAllSupportedNetworks(namespace: 'solana');
      if (solChains.isNotEmpty) {
        await modal.selectChain(solChains.first);
      }
    }
    final selected = modal.selectedChain?.chainId ?? '';
    if (!selected.startsWith('solana:')) return null;
    return modal.session?.getAddress('solana');
  }

  Future<String> _signChallenge(
    ReownAppKitModal modal,
    String address,
    String message,
  ) async {
    final chainId = modal.selectedChain!.chainId;
    final messageBase58 = base58.encode(utf8.encode(message));

    final response = await modal.request(
      topic: modal.session!.topic,
      chainId: chainId,
      request: SessionRequestParams(
        method: 'solana_signMessage',
        params: {'pubkey': address, 'message': messageBase58},
      ),
    );

    return _signatureToTransmittable(response);
  }

  String _signatureToTransmittable(dynamic response) {
    if (response is String) return response;
    if (response is Map) {
      final sig = ReownCoreUtils.recursiveSearchForMapKey(
        Map<String, dynamic>.from(response),
        'signature',
      );
      if (sig is String) return sig;
    }
    if (response is List && response.isNotEmpty) {
      return _signatureToTransmittable(response.first);
    }
    throw AuthException('Wallet returned an unreadable signature');
  }
}