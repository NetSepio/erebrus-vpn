import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';
import 'browser_controller.dart';

/// In-app private browser: tab strip, omnibox, the private start page (Brave
/// search + network hub placeholder) and the WebView for real pages, all over
/// the dVPN tunnel.
///
/// [isActive] is true when this tab is the selected pane in [MainShell]'s
/// [IndexedStack]. The native WebView platform view is mounted only then —
/// embedding it in a hidden IndexedStack child freezes many Android devices.
class BrowserView extends StatefulWidget {
  const BrowserView({super.key, required this.isActive});

  final bool isActive;

  @override
  State<BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<BrowserView> {
  BrowserController get _c =>
      Get.isRegistered<BrowserController>() ? Get.find<BrowserController>() : Get.put(BrowserController());

  @override
  void initState() {
    super.initState();
    _c.setShellTabVisible(widget.isActive);
  }

  @override
  void didUpdateWidget(BrowserView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      _c.setShellTabVisible(widget.isActive);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;

    return Scaffold(
      backgroundColor: AppColors.bg,
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
              return _Omnibox(controller: c);
            }),
            Expanded(
              child: Obx(() {
                c.tabs.length;
                c.activeIndex.value;
                c.addressBar.value;
                if (c.tabs.isEmpty) return const SizedBox.shrink();
                final tab = c.activeTab;
                if (tab.isStart) return const _StartPage();
                if (!widget.isActive) {
                  // Shell is on VPN/Settings — keep Flutter-only UI in the tree.
                  return _PendingWebPage(url: tab.url, loading: c.isLoading.value);
                }
                return Stack(
                  children: [
                    WebViewWidget(key: ValueKey(tab.id), controller: tab.controller),
                    if (c.isLoading.value)
                      const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent, color: AppColors.accent),
                  ],
                );
              }),
            ),
            _ControlBar(controller: c),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) const CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
            if (loading) const SizedBox(height: 16),
            Text('Ready to load', style: grotesk(size: 16, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(url, textAlign: TextAlign.center, style: mono(size: 12, color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: active ? AppColors.surface3 : const Color(0xFF101014),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: active ? AppColors.accent.withValues(alpha: 0.35) : AppColors.stroke),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active ? AppColors.accent : const Color(0xFF4A4A52),
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
                              color: active ? AppColors.textPrimary : AppColors.textTertiary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => controller.closeTab(i),
                        child: const Icon(Icons.close, size: 13, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          GestureDetector(
            onTap: () => controller.addTab(),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.strokeHi),
              ),
              child: const Icon(Icons.add, size: 17, color: AppColors.textSecondary),
            ),
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
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.controller.addressBar.value;
    if (!_focus.hasFocus && _text.text != url) _text.text = url;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock, size: 16, color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _focus,
                style: mono(size: 13, weight: FontWeight.w400, color: const Color(0xFFC8C7C2)),
                cursorColor: AppColors.accent,
                textInputAction: TextInputAction.go,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search or enter address',
                ),
                onSubmitted: (v) => widget.controller.navigate(v),
              ),
            ),
            GestureDetector(
              onTap: widget.controller.reload,
              child: const Icon(Icons.refresh, size: 17, color: AppColors.textMuted),
            ),
          ],
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

  BrowserController get _browser =>
      Get.isRegistered<BrowserController>() ? Get.find<BrowserController>() : Get.put(BrowserController());

  String get _protocol {
    if (!Get.isRegistered<VpnController>()) return 'AUTO';
    final vpn = Get.find<VpnController>();
    if (vpn.isConnected && vpn.activeTransport.value != null) {
      return vpn.activeTransport.value!.label.toUpperCase();
    }
    return vpn.mode.value.label.toUpperCase();
  }

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submitSearch() {
    final query = _search.text.trim();
    if (query.isEmpty) return;
    _browser.navigate(query);
    _search.clear();
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
      children: [
        Row(
          children: [
            _BlinkDot(color: AppColors.success, size: 6),
            const SizedBox(width: 8),
            Text('PRIVATE SESSION · $_protocol',
                style: mono(size: 11, weight: FontWeight.w500, color: AppColors.accent, letterSpacing: 11 * 0.12)),
          ],
        ),
        const SizedBox(height: 14),
        Text('Sovereign web.', style: grotesk(size: 32, weight: FontWeight.w600, letterSpacing: -0.8)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
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
                  style: grotesk(size: 14, weight: FontWeight.w400, color: AppColors.textPrimary),
                  cursorColor: AppColors.accent,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Search the private web…',
                    hintStyle: grotesk(size: 14, weight: FontWeight.w400, color: AppColors.textMuted),
                  ),
                  onSubmitted: (_) => _submitSearch(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Powered by Brave Search over your tunnel.',
          style: grotesk(size: 12, weight: FontWeight.w400, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.stroke),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.hub_outlined, size: 22, color: AppColors.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Your network hub', style: grotesk(size: 15, weight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        MonoChip(
                          label: 'COMING SOON',
                          color: AppColors.textMuted,
                          background: AppColors.surface2,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Private services, files, and team tools will live here once the network hub ships.',
                      style: grotesk(size: 12.5, weight: FontWeight.w400, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.controller});
  final BrowserController controller;

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.raised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh, color: AppColors.textSecondary),
              title: Text('Reload page', style: grotesk(size: 15, weight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                controller.reload();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add, color: AppColors.textSecondary),
              title: Text('New tab', style: grotesk(size: 15, weight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                controller.addTab();
              },
            ),
            ListTile(
              leading: const Icon(Icons.tab, color: AppColors.textSecondary),
              title: Text('All tabs', style: grotesk(size: 15, weight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                showBrowserTabsSheet(context, controller);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.strokeSoft))),
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
              GestureDetector(
                onTap: () => showBrowserTabsSheet(context, controller),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.strokeHi),
                  ),
                  child: Text(
                    '${controller.tabs.length}',
                    style: mono(size: 11, weight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ),
              ),
              _CtlIcon(Icons.more_horiz, onTap: () => _showMenu(context)),
            ],
          );
        }),
      ),
    );
  }
}

void showBrowserTabsSheet(BuildContext context, BrowserController controller) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.raised,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (_, scrollController) => Obx(() {
        controller.tabs.length;
        controller.activeIndex.value;
        final tabs = controller.tabs;
        final active = controller.activeIndex.value;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Text('Tabs', style: grotesk(size: 18, weight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  MonoChip(
                    label: '${tabs.length}',
                    color: AppColors.textSecondary,
                    background: AppColors.surface2,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add, color: AppColors.textSecondary),
                    tooltip: 'New tab',
                    onPressed: () => controller.addTab(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.strokeSoft),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: tabs.length,
                itemBuilder: (_, i) {
                  final tab = tabs[i];
                  final isActive = i == active;
                  final subtitle = tab.isStart ? 'Erebrus home' : tab.url;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: isActive ? AppColors.surface3 : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          controller.selectTab(i);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isActive ? AppColors.accent.withValues(alpha: 0.35) : AppColors.stroke,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isActive ? AppColors.accent : AppColors.textMuted,
                                  shape: BoxShape.circle,
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
                                        color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: mono(size: 11, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                                onPressed: () => controller.closeTab(i),
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
    ),
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

class _BlinkDot extends StatefulWidget {
  const _BlinkDot({required this.color, this.size = 9});
  final Color color;
  final double size;
  @override
  State<_BlinkDot> createState() => _BlinkDotState();
}

class _BlinkDotState extends State<_BlinkDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.25).animate(_c),
      child: Container(width: widget.size, height: widget.size, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
    );
  }
}
