import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

const kBrowserHome = 'https://www.google.com';

class BrowserTab {
  BrowserTab({
    required this.id,
    required this.url,
    this.title = 'New tab',
    WebViewController? controller,
  }) : controller = controller ?? WebViewController();

  final String id;
  String url;
  String title;
  final WebViewController controller;
  bool canGoBack = false;
  bool canGoForward = false;
}

/// Multi-tab in-app browser (default home: Google).
class BrowserController extends GetxController {
  final tabs = <BrowserTab>[].obs;
  final activeIndex = 0.obs;
  final addressBar = kBrowserHome.obs;
  final isLoading = false.obs;

  BrowserTab get activeTab => tabs[activeIndex.value.clamp(0, tabs.length - 1)];

  @override
  void onInit() {
    super.onInit();
    if (tabs.isEmpty) addTab(kBrowserHome);
  }

  void addTab([String? url]) {
    final u = _normalizeUrl(url ?? kBrowserHome);
    final tab = BrowserTab(id: DateTime.now().microsecondsSinceEpoch.toString(), url: u);
    _configure(tab);
    tabs.add(tab);
    activeIndex.value = tabs.length - 1;
    addressBar.value = u;
  }

  void closeTab(int index) {
    if (tabs.length <= 1) {
      tabs.first.url = kBrowserHome;
      tabs.first.title = 'Google';
      addressBar.value = kBrowserHome;
      tabs.first.controller.loadRequest(Uri.parse(kBrowserHome));
      return;
    }
    tabs.removeAt(index);
    if (activeIndex.value >= tabs.length) {
      activeIndex.value = tabs.length - 1;
    }
    addressBar.value = activeTab.url;
  }

  void selectTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    activeIndex.value = index;
    addressBar.value = activeTab.url;
  }

  Future<void> navigate(String input) async {
    final url = _normalizeUrl(input);
    final tab = activeTab;
    tab.url = url;
    addressBar.value = url;
    await tab.controller.loadRequest(Uri.parse(url));
  }

  Future<void> reload() => activeTab.controller.reload();

  Future<void> goBack() async {
    if (await activeTab.controller.canGoBack()) {
      await activeTab.controller.goBack();
    }
  }

  Future<void> goForward() async {
    if (await activeTab.controller.canGoForward()) {
      await activeTab.controller.goForward();
    }
  }

  void _configure(BrowserTab tab) {
    tab.controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => isLoading.value = true,
          onPageFinished: (url) async {
            isLoading.value = false;
            tab.url = url;
            if (tabs[activeIndex.value] == tab) addressBar.value = url;
            tab.canGoBack = await tab.controller.canGoBack();
            tab.canGoForward = await tab.controller.canGoForward();
            final title = await tab.controller.getTitle();
            if (title != null && title.isNotEmpty) {
              tab.title = title.length > 24 ? '${title.substring(0, 24)}…' : title;
              tabs.refresh();
            }
          },
          onNavigationRequest: (req) => NavigationDecision.navigate,
        ),
      )
      ..loadRequest(Uri.parse(tab.url));
  }

  static String _normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return kBrowserHome;
    if (trimmed.contains(' ') && !trimmed.contains('.')) {
      return 'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }
}