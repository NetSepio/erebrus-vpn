import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/app_theme.dart';
import '../../theme/premium_widgets.dart';
import 'browser_controller.dart';

/// In-app browser with tabs and URL bar (home: google.com).
class BrowserView extends StatelessWidget {
  const BrowserView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.isRegistered<BrowserController>()
        ? Get.find<BrowserController>()
        : Get.put(BrowserController());

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            Obx(() {
              final _ = c.tabs.length + c.activeIndex.value;
              return _TabStrip(controller: c);
            }),
            Obx(() {
              final _ = c.addressBar.value;
              return _UrlBar(controller: c);
            }),
            Expanded(
              child: Obx(() {
                if (c.tabs.isEmpty) return const SizedBox.shrink();
                final tab = c.activeTab;
                return Stack(
                  children: [
                    WebViewWidget(key: ValueKey(tab.id), controller: tab.controller),
                    if (c.isLoading.value)
                      const LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        color: AppColors.cyan,
                      ),
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

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.sm),
      child: Row(
        children: [
          Text('Browse', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          Icon(Icons.lock_outline, size: 18, color: AppColors.connected.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
          Text(
            'via VPN when connected',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
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
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        children: [
          ...List.generate(controller.tabs.length, (i) {
            final tab = controller.tabs[i];
            final active = controller.activeIndex.value == i;
            return Padding(
              padding: const EdgeInsets.only(right: AppSpace.sm),
              child: GestureDetector(
                onTap: () => controller.selectTab(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? AppColors.surfaceHi : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: active ? AppColors.cyan.withValues(alpha: 0.5) : AppColors.stroke,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tab.title,
                        style: TextStyle(
                          color: active ? AppColors.textPrimary : AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (controller.tabs.length > 1) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => controller.closeTab(i),
                          child: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.cyan),
            tooltip: 'New tab',
            onPressed: () => controller.addTab(),
          ),
        ],
      ),
    );
  }
}

class _UrlBar extends StatefulWidget {
  const _UrlBar({required this.controller});
  final BrowserController controller;

  @override
  State<_UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends State<_UrlBar> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.controller.addressBar.value);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.controller.addressBar.value;
    if (_text.text != url) _text.text = url;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.md),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20, color: AppColors.textSecondary),
              onPressed: widget.controller.goBack,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 20, color: AppColors.textSecondary),
              onPressed: widget.controller.goForward,
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
              onPressed: widget.controller.reload,
            ),
            Expanded(
              child: TextField(
                key: ValueKey(widget.controller.activeTab.id),
                controller: _text,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Search or enter URL',
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: (v) => widget.controller.navigate(v),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.home_outlined, size: 20, color: AppColors.cyan),
              tooltip: 'Home',
              onPressed: () {
                _text.text = kBrowserHome;
                widget.controller.navigate(kBrowserHome);
              },
            ),
          ],
        ),
      ),
    );
  }
}