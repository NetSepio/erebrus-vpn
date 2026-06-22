import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/app_theme.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_models.dart';
import 'browser_controller.dart';

/// In-app private browser: tab strip, omnibox, the private start page (service
/// grid) and the WebView for real pages, all over the dVPN tunnel.
class BrowserView extends StatelessWidget {
  const BrowserView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.isRegistered<BrowserController>() ? Get.find<BrowserController>() : Get.put(BrowserController());

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
                if (c.tabs.isEmpty) return const SizedBox.shrink();
                final tab = c.activeTab;
                if (tab.isStart) return const _StartPage();
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

class _StartPage extends StatelessWidget {
  const _StartPage();

  String get _protocol {
    if (!Get.isRegistered<VpnController>()) return 'WIREGUARD';
    return Get.find<VpnController>().mode.value == ConnectMode.stealth ? 'STEALTH' : 'WIREGUARD';
  }

  @override
  Widget build(BuildContext context) {
    final services = <_Service>[
      _Service('Sovereign AI', 'Private models', Icons.auto_awesome, AppColors.accent, AppColors.accent.withValues(alpha: 0.14)),
      _Service('Private Files', 'Encrypted store', Icons.folder_outlined, const Color(0xFF7E96F0), AppColors.ethereum.withValues(alpha: 0.16)),
      _Service('Team Drive', '11 members', Icons.group_outlined, AppColors.shared, AppColors.shared.withValues(alpha: 0.16)),
      _Service('Node Console', 'home-lab-01', Icons.terminal, AppColors.success, AppColors.success.withValues(alpha: 0.16)),
      _Service('Apps Hub', '6 installed', Icons.grid_view, const Color(0xFFB07CFF), AppColors.solana.withValues(alpha: 0.18)),
      _Service('Bookmarks', 'Saved links', Icons.bookmark_outline, AppColors.warn, AppColors.warn.withValues(alpha: 0.16)),
    ];

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
        // search pill
        GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.stroke),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 11),
                Text('Search the private web…', style: grotesk(size: 14, weight: FontWeight.w400, color: AppColors.textMuted)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text('YOUR NETWORK', style: mono(size: 11, weight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 11 * 0.12)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [for (final s in services) _ServiceCard(service: s)],
        ),
      ],
    );
  }
}

class _Service {
  const _Service(this.title, this.sub, this.icon, this.color, this.chip);
  final String title;
  final String sub;
  final IconData icon;
  final Color color;
  final Color chip;
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});
  final _Service service;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${service.title} — connect this card to its destination'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface3,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: service.chip, borderRadius: BorderRadius.circular(12)),
              child: Icon(service.icon, size: 20, color: service.color),
            ),
            const SizedBox(height: 12),
            Text(service.title, style: grotesk(size: 14, weight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(service.sub, style: grotesk(size: 11.5, weight: FontWeight.w400, color: AppColors.textTertiary)),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 4),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.strokeSoft))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _CtlIcon(Icons.arrow_back, color: AppColors.textDim, onTap: controller.goBack),
          _CtlIcon(Icons.arrow_forward, color: AppColors.textDim, onTap: controller.goForward),
          _CtlIcon(Icons.home_outlined, onTap: controller.goHome),
          Obx(() => Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppColors.textTertiary, width: 1.5),
                ),
                child: Text('${controller.tabs.length}',
                    style: mono(size: 11, weight: FontWeight.w600, color: AppColors.textTertiary)),
              )),
          _CtlIcon(Icons.more_horiz, onTap: () {}),
        ],
      ),
    );
  }
}

class _CtlIcon extends StatelessWidget {
  const _CtlIcon(this.icon, {this.color = AppColors.textTertiary, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 20, color: color)),
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
