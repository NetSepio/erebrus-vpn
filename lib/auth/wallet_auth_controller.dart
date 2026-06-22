import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:reown_appkit/reown_appkit.dart';

import 'auth_config.dart';
import 'auth_session_store.dart';
import 'deep_link_handler.dart';
import 'entitlement_state.dart';
import 'gateway_auth_client.dart';
import '../platform/platform_capabilities.dart';
import '../view/auth/desktop_social_sign_in_page.dart';
import 'solana_mobile_wallet.dart';
import '../vpn/gateway_controller.dart';

/// Sentinel ID so Reown's explorer returns no wallets on desktop.
const _desktopBlockedWalletIds = {'erebrus-desktop-no-wallets'};

/// Wallet login via MWA on Solana Mobile, Reown elsewhere, and gateway v2 auth.
class WalletAuthController extends GetxController {
  WalletAuthController({
    GatewayAuthClient? authClient,
    AuthSessionStore? store,
  })  : _authClient = authClient ?? GatewayAuthClient(),
        _store = store ?? AuthSessionStore();

  final GatewayAuthClient _authClient;
  final AuthSessionStore _store;

  ReownAppKitModal? appKitModal;

  final walletAddress = ''.obs;
  final userId = ''.obs;
  final role = ''.obs;
  final authMethod = ''.obs;
  final isAuthenticating = false.obs;
  final reownReady = false.obs;
  final sessionReady = false.obs;
  final authError = RxnString();
  final entitlement = EntitlementState.none.obs;
  final isLoadingEntitlement = false.obs;
  final isStartingTrial = false.obs;
  final entitlementError = RxnString();

  String? _token;
  String? _mwaAuthToken;

  final isSolanaMobileDevice = false.obs;

  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  bool get isEntitled => entitlement.value.entitled;
  bool get usesReown => PlatformCapabilities.usesReown;
  String? get bearerToken => _token;

  @override
  void onInit() {
    super.onInit();
    loadPersistedSession();
  }

  @override
  void onClose() {
    appKitModal?.onModalConnect.unsubscribe(_onModalConnect);
    appKitModal?.onModalDisconnect.unsubscribe(_onModalDisconnect);
    appKitModal?.onModalError.unsubscribe(_onModalError);
    super.onClose();
  }

  /// Detects Seeker/Saga hardware so auth can skip Reown on Solana Mobile.
  Future<void> detectDevice() async {
    final detected = await detectSolanaMobileDevice();
    isSolanaMobileDevice.value = detected;
    PlatformCapabilities.isSolanaMobileDevice = detected;
  }

  /// Restores token + profile from secure storage before the UI loads.
  Future<void> loadPersistedSession() async {
    sessionReady.value = false;
    try {
      final stored = await _store.read();
      if (stored != null) {
        _token = stored.token;
        _mwaAuthToken = stored.mwaAuthToken;
        walletAddress.value = stored.walletAddress;
        userId.value = stored.userId;
        role.value = stored.role;
        authMethod.value = stored.authMethod;
        _syncGatewayToken();
        await refreshEntitlement();
        debugPrint('[Auth] restored session for ${stored.walletAddress}');
      } else {
        entitlement.value = EntitlementState.none;
      }
    } catch (e) {
      debugPrint('[Auth] restore failed: $e');
    } finally {
      sessionReady.value = true;
    }
  }

  Future<void> initReown(BuildContext context) async {
    if (!usesReown) {
      reownReady.value = false;
      return;
    }
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

    final isDesktop = PlatformCapabilities.isDesktop;
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
          linkMode: false,
        ),
      ),
      optionalNamespaces: solanaNamespaces,
      // Desktop: social/email only — no Phantom/Solflare/WalletConnect chips.
      featuresConfig: FeaturesConfig(
        showMainWallets: !isDesktop,
        socials: isDesktop
            ? const [
                AppKitSocialOption.Google,
                AppKitSocialOption.Apple,
                AppKitSocialOption.Email,
              ]
            : const [
                AppKitSocialOption.Google,
                AppKitSocialOption.Apple,
                AppKitSocialOption.Email,
                AppKitSocialOption.X,
              ],
      ),
      includedWalletIds: isDesktop ? _desktopBlockedWalletIds : null,
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
      debugPrint(
        isDesktop
            ? '[Reown] ready — social/email sign-in (desktop, no wallets)'
            : '[Reown] ready — wallets + social login available',
      );

      if (appKitModal!.isConnected && !isAuthenticated) {
        await _authenticateConnectedWallet();
      }
    } catch (e) {
      debugPrint('[Reown] init failed: $e');
      authError.value = 'Wallet connect failed to start: $e';
      reownReady.value = false;
    }
  }

  /// Opens MWA wallet selector on Solana Mobile, Reown modal elsewhere.
  Future<void> openSignIn() async {
    authError.value = null;
    if (isSolanaMobileDevice.value) {
      await signInWithSolanaMobile();
    } else {
      await openWalletModal();
    }
  }

  Future<void> openWalletModal() async {
    authError.value = null;
    if (appKitModal == null || !reownReady.value) {
      authError.value = PlatformCapabilities.isDesktop
          ? 'Sign-in is still starting — try again in a moment'
          : 'Wallet connect is still starting — try again in a moment';
      return;
    }
    await appKitModal!.openModalView(
      PlatformCapabilities.isDesktop
          ? const DesktopSocialSignInPage()
          : null,
    );
  }

  /// Mobile Wallet Adapter path — opens the native wallet selector on Seeker/Saga.
  Future<void> signInWithSolanaMobile() async {
    if (!isSolanaMobileDevice.value) {
      authError.value = 'Solana Mobile sign-in is only available on Seeker and Saga';
      return;
    }
    // Guard against a double-tap opening two wallet associations at once.
    if (isAuthenticating.value) return;

    isAuthenticating.value = true;
    authError.value = null;
    try {
      // One MWA association: authorize → fetch the challenge → sign it.
      var flowId = '';
      final result = await mwaSignIn(
        storedAuthToken: _mwaAuthToken,
        challengeBuilder: (address, publicKey) async {
          final challenge = await _authClient.fetchFlowId(walletAddress: address);
          flowId = challenge.flowId;
          return challenge.message;
        },
      );
      _mwaAuthToken = result.authToken;

      final session = await _authClient.authenticate(
        flowId: flowId,
        signature: result.signature,
        publicKey: result.address,
      );
      await _persistSession(session, method: 'solana_mobile', mwaToken: result.authToken);
      await refreshEntitlement();
      debugPrint('[MWA] gateway auth OK for ${result.address}');
    } on MwaException catch (e) {
      authError.value = e.message;
    } on AuthException catch (e) {
      authError.value = e.message;
    } catch (e) {
      authError.value = e.toString();
    } finally {
      isAuthenticating.value = false;
    }
  }

  Future<void> signOut() async {
    authError.value = null;
    entitlementError.value = null;
    entitlement.value = EntitlementState.none;
    final mwaToken = _mwaAuthToken;
    _token = null;
    _mwaAuthToken = null;
    walletAddress.value = '';
    userId.value = '';
    role.value = '';
    authMethod.value = '';
    await _store.clear();
    if (appKitModal?.isConnected == true) {
      await appKitModal?.disconnect();
    }
    await disconnectSolanaMobile(mwaToken);
    _syncGatewayToken();
  }

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

  Future<void> _persistSession(
    AuthSession session, {
    required String method,
    String? mwaToken,
  }) async {
    _token = session.token;
    walletAddress.value = session.walletAddress;
    userId.value = session.userId;
    role.value = session.role;
    authMethod.value = method;
    if (mwaToken != null) _mwaAuthToken = mwaToken;
    await _store.write(
      token: session.token,
      walletAddress: session.walletAddress,
      userId: session.userId,
      role: session.role,
      authMethod: method,
      mwaAuthToken: mwaToken ?? _mwaAuthToken,
    );
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
      await _persistSession(session, method: 'reown');
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