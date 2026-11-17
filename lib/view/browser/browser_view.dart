import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../platform/desktop_browser.dart';
import '../../platform/platform_capabilities.dart';
import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../../settings/app_settings_controller.dart';
import '../bottombar/shell_back_scope.dart';
import 'browser_chrome.dart';
import 'browser_controller.dart';
import 'browser_link_menu.dart';
import 'browser_session_status.dart';

/// In-app private browser: tab strip, omnibox, the private start page (service
/// grid) and the WebView for real pages, all over the dVPN tunnel.
///
/// The native WebView platform view is mounted only while the BROWSER tab is
/// selected in [MainShell]'s [IndexedStack] — embedding it in a hidden
/// IndexedStack child freezes many Android devices.
class BrowserView extends StatefulWidget {
  const BrowserView({super.key});

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView> with RouteAware {
  late final BrowserController _c;
  ModalRoute<dynamic>? _route;
  int _routeGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route == route) return;
    browserRouteObserver.unsubscribe(this);
    _route = route;
    if (route != null) browserRouteObserver.subscribe(this, route);
    _c.setRouteCovered(route != null && !route.isCurrent);
  }

  @override
  void didPushNext() {
    _routeGeneration++;
    _c.setRouteCovered(true);
  }

  @override
  void didPopNext() {
    final generation = ++_routeGeneration;
    final departing = browserRouteObserver.departingRoute;
    if (!PlatformCapabilities.usesDesktopVpnRunner || departing == null) {
      _c.setRouteCovered(false);
      return;
    }
    unawaited(
      departing.then((_) {
        if (mounted &&
            generation == _routeGeneration &&
            _route?.isCurrent == true) {
          _c.setRouteCovered(false);
        }
      }),
    );
  }

  @override
  void initState() {
    super.initState();
    _c = Get.isRegistered<BrowserController>()
        ? Get.find<BrowserController>()
        : Get.put(BrowserController());
    _c.linkContextMenuHandler = _onLinkContextMenu;
  }

  @override
  void dispose() {
    browserRouteObserver.unsubscribe(this);
    _c.linkContextMenuHandler = null;
    _c.setShellTabVisible(false);
    super.dispose();
  }

  void _onLinkContextMenu(BrowserLinkHit hit) {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    showBrowserLinkContextMenu(context, _c, hit);
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.supportsEmbeddedBrowser) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: BrowserStatePanel(
            icon: Icons.web_asset_off,
            title: 'Embedded browser unavailable',
            message:
                'In-app browsing is not supported on this platform. '
                'VPN controls remain available.',
          ),
        ),
      );
    }
    final c = _c;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.bg,
      // Desktop carries navigation, tabs and the menu in the toolbar row; a
      // bottom bar would duplicate it. As the Scaffold's bottom bar, toasts
      // float above it instead of covering it.
      bottomNavigationBar: PlatformCapabilities.isDesktop
          ? null
          : _ControlBar(controller: c),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Obx(() {
              c.tabs.length; // observe
              c.activeIndex.value;
              return _TabStrip(controller: c);
            }),
            Obx(() {
              c.addressBar.value; // observe
              c.tabs.length; // canGoBack/Forward updates refresh the list
              c.activeIndex.value;
              c.isLoading.value;
              return _Omnibox(controller: c);
            }),
            const BrowserSessionStrip(),
            Expanded(
              child: Obx(() {
                c.tabs.length;
                c.activeIndex.value;
                c.addressBar.value;
                if (c.tabs.isEmpty) return const SizedBox.shrink();
                final tab = c.activeTab;
                if (tab.isStart) return const _StartPage();
                if (PlatformCapabilities.usesDesktopVpnRunner &&
                    !c.protectionAvailable.value) {
                  return BrowserStatePanel(
                    icon: Icons.shield_outlined,
                    tone: AppColors.warn,
                    title: 'Connect to browse',
                    message:
                        'Pages load only through a verified VPN connection. '
                        'Connect, then come back to this tab.',
                    actionLabel: 'Open VPN',
                    onAction: () => ShellBackScope.selectHome(context),
                  );
                }
                final error = c.browserError.value;
                if (error != null) {
                  return BrowserStatePanel(
                    icon: Icons.cloud_off_outlined,
                    tone: AppColors.danger,
                    title: 'Page unavailable',
                    message: error,
                    actionLabel: 'Retry',
                    onAction: c.reload,
                  );
                }
                if (!c.canMountBrowser || !tab.configured) {
                  // Shell is on VPN/Settings — keep Flutter-only UI in the tree.
                  return _PendingWebPage(
                    url: tab.url,
                    loading: c.isLoading.value,
                  );
                }
                if (PlatformCapabilities.usesDesktopVpnRunner) {
                  return Column(
                    children: [
                      SizedBox(
                        height: 2,
                        child: c.isLoading.value
                            ? const _PageProgressBar()
                            : null,
                      ),
                      Expanded(
                        child: _DesktopWebPage(
                          key: ValueKey('${tab.id}:${tab.generation}'),
                          browser: c,
                          tab: tab,
                        ),
                      ),
                    ],
                  );
                }
                return Stack(
                  children: [
                    WebViewWidget(
                      key: ValueKey('${tab.id}:${tab.generation}'),
                      controller: tab.controller,
                    ),
                    if (c.isLoading.value)
                      const SizedBox(height: 2, child: _PageProgressBar()),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when a tab has a URL but the BROWSER shell tab is not visible.
class _PendingWebPage extends StatelessWidget {
  const _PendingWebPage({required this.url, required this.loading});
  final String url;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return BrowserStatePanel(
      icon: Icons.language,
      tone: AppColors.accent,
      loading: loading,
      title: loading ? 'Loading securely' : 'Ready to load',
      message: url,
      monoMessage: true,
    );
  }
}

class _PageProgressBar extends StatelessWidget {
  const _PageProgressBar();

  @override
  Widget build(BuildContext context) {
    return const LinearProgressIndicator(
      minHeight: 2,
      backgroundColor: Colors.transparent,
      color: AppColors.accent,
    );
  }
}

class _DesktopWebPage extends StatefulWidget {
  const _DesktopWebPage({super.key, required this.browser, required this.tab});

  final BrowserController browser;
  final BrowserTab tab;

  @override
  State<_DesktopWebPage> createState() => _DesktopWebPageState();
}

class _DesktopWebPageState extends State<_DesktopWebPage> {
  @override
  void initState() {
    super.initState();
    unawaited(_showWhenLaidOut());
  }

  @override
  void activate() {
    super.activate();
    unawaited(_showWhenLaidOut());
  }

  Future<void> _showWhenLaidOut() async {
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await widget.browser.showNativeTab(widget.tab);
  }

  @override
  Widget build(BuildContext context) =>
      WebViewWidget(controller: widget.tab.controller);
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.controller});
  final BrowserController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: kBrowserGutter,
          vertical: 8,
        ),
        children: [
          ...List.generate(controller.tabs.length, (i) {
            final tab = controller.tabs[i];
            final active = controller.activeIndex.value == i;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => controller.selectTab(i),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 150),
                  padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
                  decoration: BoxDecoration(
                    color: active ? AppColors.surface3 : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: active
                          ? AppColors.accent.withValues(alpha: 0.35)
                          : AppColors.stroke,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active ? AppColors.accent : AppColors.textDim,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          tab.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: grotesk(
                            size: 12.5,
                            weight: FontWeight.w500,
                            color: active
                                ? AppColors.textPrimary
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => controller.closeTab(i),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          VisibleIconButton(
            icon: Icons.add,
            size: 32,
            iconSize: 17,
            onTap: () => controller.addTab(),
          ),
        ],
      ),
    );
  }
}

class _Omnibox extends StatefulWidget {
  const _Omnibox({required this.controller});
  final BrowserController controller;
  @override
  State<_Omnibox> createState() => _OmniboxState();
}

class _OmniboxState extends State<_Omnibox> {
  late final TextEditingController _text;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.controller.addressBar.value);
    _focus.addListener(_onFocusChange);
  }

  /// Browser convention: tapping the address selects all of it (so typing
  /// replaces it), and leaving the field scrolls back to the URL's start.
  void _onFocusChange() {
    if (_focus.hasFocus) {
      // After the tap's own caret placement, which would otherwise win.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focus.hasFocus) return;
        _text.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _text.text.length,
        );
      });
    } else {
      final url = widget.controller.addressBar.value;
      _text.value = TextEditingValue(
        text: url == kStartPage ? '' : url,
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rawUrl = widget.controller.addressBar.value;
    // Don't surface the internal start-page scheme (erebrus://home) in the
    // address bar — keep it blank so the "Search or enter address" hint shows.
    final url = rawUrl == kStartPage ? '' : rawUrl;
    if (!_focus.hasFocus && _text.text != url) {
      _text.value = TextEditingValue(
        text: url,
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
    final desktop = PlatformCapabilities.isDesktop;
    final c = widget.controller;
    final tab = c.tabs.isEmpty ? null : c.activeTab;
    final onWeb = tab != null && !tab.isStart && tab.configured;
    final loading = c.isLoading.value && tab != null && !tab.isStart;

    return Padding(
      padding: const EdgeInsets.fromLTRB(kBrowserGutter, 0, kBrowserGutter, 10),
      child: Row(
        children: [
          if (desktop) ...[
            _DesktopBrowserButton(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              enabled: onWeb && tab.canGoBack,
              onTap: c.goBack,
            ),
            const SizedBox(width: 6),
            _DesktopBrowserButton(
              icon: Icons.arrow_forward,
              tooltip: 'Forward',
              enabled: onWeb && tab.canGoForward,
              onTap: c.goForward,
            ),
            const SizedBox(width: 6),
            _DesktopBrowserButton(
              icon: Icons.home_outlined,
              tooltip: 'Home',
              onTap: c.goHome,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Container(
              height: 40,
              padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.stroke),
              ),
              child: Row(
                children: [
                  Icon(
                    url.startsWith('https://')
                        ? Icons.lock_outline
                        : url.isEmpty
                        ? Icons.search
                        : Icons.public,
                    size: 15,
                    color: url.startsWith('https://')
                        ? AppColors.success
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      style: mono(
                        size: 13,
                        weight: FontWeight.w400,
                        color: AppColors.textPrimary,
                      ),
                      cursorColor: AppColors.accent,
                      textInputAction: TextInputAction.go,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Search or enter address',
                        hintStyle: mono(
                          size: 13,
                          weight: FontWeight.w400,
                          color: AppColors.textMuted,
                        ),
                      ),
                      onSubmitted: (v) => widget.controller.navigate(v),
                    ),
                  ),
                  Tooltip(
                    message: loading ? 'Stop' : 'Reload',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: loading ? c.stopLoading : c.reload,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          loading ? Icons.close : Icons.refresh,
                          size: 17,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (desktop) ...[
            const SizedBox(width: 10),
            _TabCountButton(controller: c),
            const SizedBox(width: 6),
            _DesktopBrowserButton(
              icon: Icons.more_horiz,
              tooltip: 'Menu',
              onTap: () => showBrowserMenu(context, c),
            ),
          ],
        ],
      ),
    );
  }
}

class _DesktopBrowserButton extends StatelessWidget {
  const _DesktopBrowserButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: VisibleIconButton(
        icon: icon,
        size: 40,
        onTap: onTap,
        enabled: enabled,
      ),
    );
  }
}

/// Open-tab count; opens the tab switcher. Shared by the mobile bottom bar
/// and the desktop toolbar.
class _TabCountButton extends StatelessWidget {
  const _TabCountButton({required this.controller});
  final BrowserController controller;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Tabs',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showBrowserTabsSheet(context, controller),
        child: Container(
          height: 40,
          constraints: const BoxConstraints(minWidth: 40),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.strokeHi),
          ),
          child: Text(
            '${controller.tabs.length}',
            style: mono(
              size: 11,
              weight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _StartPage extends StatefulWidget {
  const _StartPage();

  @override
  State<_StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<_StartPage> {
  final _search = TextEditingController();
  final _focus = FocusNode();

  BrowserController get _browser => Get.isRegistered<BrowserController>()
      ? Get.find<BrowserController>()
      : Get.put(BrowserController());

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submitSearch() {
    final query = _search.text;
    if (query.trim().isEmpty) return;
    _browser.searchPrivateWeb(query);
    _search.clear();
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final screenSize = MediaQuery.sizeOf(context);
    final compact = screenSize.width < 380;
    final tightHeight = screenSize.height < 700;
    final toolColumns = PlatformCapabilities.isDesktop ? 3 : 2;
    final services = <_Service>[
      _Service(
        'Speed Test',
        'Download, upload & latency',
        'https://fast.com/',
        Icons.speed,
        AppColors.accent,
        AppColors.accent.withValues(alpha: 0.14),
      ),
      _Service(
        'Public IP',
        'Verify VPN exit location',
        'https://ipinfo.io/what-is-my-ip',
        Icons.public,
        const Color(0xFF7E96F0),
        AppColors.ethereum.withValues(alpha: 0.16),
      ),
      _Service(
        'DNS Leak',
        'Check exposed resolvers',
        'https://www.dnsleaktest.com/',
        Icons.dns_outlined,
        AppColors.shared,
        AppColors.shared.withValues(alpha: 0.16),
      ),
      _Service(
        'WebRTC Leak',
        'Check browser IP exposure',
        'https://browserleaks.com/webrtc',
        Icons.visibility_outlined,
        AppColors.success,
        AppColors.success.withValues(alpha: 0.16),
      ),
      _Service(
        'IPv6 Test',
        'Check IPv6 routing',
        'https://test-ipv6.com/',
        Icons.route_outlined,
        const Color(0xFFB07CFF),
        AppColors.solana.withValues(alpha: 0.18),
      ),
      _Service(
        'Connection Info',
        'DNS & data-center details',
        'https://1.1.1.1/help',
        Icons.hub_outlined,
        AppColors.warn,
        AppColors.warn.withValues(alpha: 0.16),
      ),
    ];

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        kBrowserGutter,
        tightHeight ? 4 : 8,
        kBrowserGutter,
        16 + bottomInset,
      ),
      children: [
        Text(
          'Sovereign web.',
          style: grotesk(
            size: compact || tightHeight ? 28 : 32,
            weight: FontWeight.w600,
            letterSpacing: -0.8,
          ),
        ),
        SizedBox(height: tightHeight ? 12 : 18),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 11),
              Expanded(
                child: TextField(
                  controller: _search,
                  focusNode: _focus,
                  style: grotesk(
                    size: 14,
                    weight: FontWeight.w400,
                    color: AppColors.textPrimary,
                  ),
                  cursorColor: AppColors.accent,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Search the private web…',
                    hintStyle: grotesk(
                      size: 14,
                      weight: FontWeight.w400,
                      color: AppColors.textMuted,
                    ),
                  ),
                  onSubmitted: (_) => _submitSearch(),
                ),
              ),
              _SearchActionButton(
                icon: Icons.arrow_forward,
                tooltip: 'Search',
                onTap: () => _submitSearch(),
              ),
            ],
          ),
        ),
        SizedBox(height: tightHeight ? 14 : 22),
        Text(
          'NETWORK TOOLS',
          style: mono(
            size: 11,
            weight: FontWeight.w500,
            color: AppColors.textMuted,
            letterSpacing: 11 * 0.12,
          ),
        ),
        SizedBox(height: tightHeight ? 8 : 12),
        GridView.count(
          crossAxisCount: toolColumns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: tightHeight ? 70 : 80,
          children: [
            for (final s in services)
              _ServiceCard(
                service: s,
                onTap: () {
                  _browser.navigate(s.url);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _SearchActionButton extends StatelessWidget {
  const _SearchActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, size: 18, color: AppColors.accent),
        ),
      ),
    );
  }
}

class _Service {
  const _Service(
    this.title,
    this.sub,
    this.url,
    this.icon,
    this.color,
    this.chip,
  );
  final String title;
  final String sub;
  final String url;
  final IconData icon;
  final Color color;
  final Color chip;
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onTap});
  final _Service service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: service.chip,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(service.icon, size: 16, color: service.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    service.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: grotesk(size: 13, weight: FontWeight.w600),
                  ),
                  Text(
                    service.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: grotesk(
                      size: 11,
                      weight: FontWeight.w400,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.controller});
  final BrowserController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          kBrowserGutter,
          10,
          kBrowserGutter,
          8,
        ),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          border: Border(top: BorderSide(color: AppColors.strokeSoft)),
        ),
        child: Obx(() {
          controller.activeIndex.value;
          controller.tabs.length;
          final tab = controller.activeTab;
          final onWeb = !tab.isStart && tab.configured;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CtlIcon(
                Icons.arrow_back,
                onTap: controller.goBack,
                enabled: onWeb && tab.canGoBack,
              ),
              _CtlIcon(
                Icons.arrow_forward,
                onTap: controller.goForward,
                enabled: onWeb && tab.canGoForward,
              ),
              _CtlIcon(Icons.home_outlined, onTap: controller.goHome),
              _TabCountButton(controller: controller),
              _CtlIcon(
                Icons.more_horiz,
                onTap: () => showBrowserMenu(context, controller),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// The browser ⋯ menu (mobile bottom bar and desktop toolbar).
void showBrowserMenu(BuildContext context, BrowserController controller) {
  final tab = controller.activeTab;
  showBrowserSheet<void>(
    context,
    builder: (ctx) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrowserSheetHeader(
            icon: Icons.travel_explore,
            title: tab.isStart ? 'Private browser' : tab.title,
            subtitle: tab.isStart ? 'Erebrus home' : tab.url,
          ),
          BrowserSheetGroup(
            children: [
              if (!tab.isStart)
                BrowserSheetTile(
                  icon: Icons.refresh,
                  title: 'Reload page',
                  onTap: () {
                    Navigator.pop(ctx);
                    controller.reload();
                  },
                ),
              BrowserSheetTile(
                icon: Icons.add,
                title: 'New tab',
                onTap: () {
                  Navigator.pop(ctx);
                  controller.addTab();
                },
              ),
              if (!tab.isStart)
                BrowserSheetTile(
                  icon: Icons.open_in_new,
                  title: 'Duplicate in new tab',
                  onTap: () {
                    Navigator.pop(ctx);
                    controller.openInNewTab(tab.url);
                  },
                ),
              BrowserSheetTile(
                icon: Icons.tab,
                title: 'All tabs',
                trailing: MonoChip(
                  label: '${controller.tabs.length}',
                  color: AppColors.textSecondary,
                  background: AppColors.surface2,
                  borderColor: AppColors.stroke,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  showBrowserTabsSheet(context, controller);
                },
              ),
            ],
          ),
          if (Get.isRegistered<AppSettingsController>())
            BrowserSheetGroup(
              children: [
                Obx(() {
                  final on =
                      Get.find<AppSettingsController>().browserDarkPages.value;
                  return BrowserSheetTile(
                    icon: Icons.dark_mode_outlined,
                    title: 'Dark web pages',
                    subtitle: 'Render light-only sites in dark mode',
                    onTap: () => controller.setDarkPages(!on),
                    trailing: EreToggle(
                      value: on,
                      onChanged: controller.setDarkPages,
                    ),
                  );
                }),
              ],
            ),
        ],
      ),
    ),
  );
}

void showBrowserTabsSheet(BuildContext context, BrowserController controller) {
  showBrowserSheet<void>(
    context,
    maxHeightFactor: 0.85,
    builder: (ctx) => Obx(() {
      controller.tabs.length;
      controller.activeIndex.value;
      final tabs = controller.tabs;
      final active = controller.activeIndex.value;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrowserSheetHeader(
            icon: Icons.tab,
            title: 'Tabs',
            count: tabs.length,
            action: VisibleIconButton(
              icon: Icons.add,
              size: 34,
              onTap: () {
                controller.addTab();
                Navigator.pop(ctx);
              },
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: tabs.length,
              itemBuilder: (_, i) {
                final tab = tabs[i];
                final isActive = i == active;
                final subtitle = tab.isStart ? 'Erebrus home' : tab.url;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isActive ? AppColors.surface3 : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () {
                        controller.selectTab(i);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: isActive
                                ? AppColors.accent.withValues(alpha: 0.35)
                                : AppColors.stroke,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.accent.withValues(alpha: 0.14)
                                    : AppColors.surface2,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                                border: Border.all(
                                  color: isActive
                                      ? AppColors.accent.withValues(alpha: 0.35)
                                      : AppColors.stroke,
                                ),
                              ),
                              child: Icon(
                                tab.isStart
                                    ? Icons.home_outlined
                                    : Icons.public,
                                size: 17,
                                color: isActive
                                    ? AppColors.accent
                                    : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tab.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: grotesk(
                                      size: 14.5,
                                      weight: FontWeight.w600,
                                      color: isActive
                                          ? AppColors.textPrimary
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: mono(
                                      size: 11,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            VisibleIconButton(
                              icon: Icons.close,
                              size: 32,
                              iconSize: 16,
                              onTap: () => controller.closeTab(i),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }),
  );
}

class _CtlIcon extends StatelessWidget {
  const _CtlIcon(this.icon, {required this.onTap, this.enabled = true});
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    return VisibleIconButton(
      icon: icon,
      size: 40,
      iconSize: 20,
      onTap: onTap,
      enabled: enabled,
    );
  }
}
