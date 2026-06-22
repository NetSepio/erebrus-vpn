import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// The private start page (the "Sovereign web." service grid). New tabs open
/// here; navigating to a real URL hands off to the WebView.
const kStartPage = 'erebrus://home';
const kStartTitle = 'Erebrus Home';

/// Fallback web home if a real page is requested without a URL.
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

  /// True while the tab is showing the private start page (no web content).
  bool get isStart => url == kStartPage || url.isEmpty;
}

/// Multi-tab in-app browser over the tunnel. Tabs start on the private start
/// page and load real pages through [webview_flutter] on navigation.
class BrowserController extends GetxController {
  final tabs = <BrowserTab>[].obs;
  final activeIndex = 0.obs;
  final addressBar = kStartPage.obs;
  final isLoading = false.obs;

  BrowserTab get activeTab => tabs[activeIndex.value.clamp(0, tabs.length - 1)];

  @override
  void onInit() {
    super.onInit();
    if (tabs.isEmpty) addTab();
  }

  void addTab([String? url]) {
    final u = url == null ? kStartPage : _normalizeUrl(url);
    final tab = BrowserTab(id: DateTime.now().microsecondsSinceEpoch.toString(), url: u, title: kStartTitle);
    _configure(tab);
    tabs.add(tab);
    activeIndex.value = tabs.length - 1;
    addressBar.value = u;
  }

  void closeTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    if (tabs.length <= 1) {
      // Always keep ≥1 tab — closing the last spawns a fresh start page.
      final fresh = BrowserTab(id: DateTime.now().microsecondsSinceEpoch.toString(), url: kStartPage, title: kStartTitle);
      _configure(fresh);
      tabs[0] = fresh;
      activeIndex.value = 0;
      addressBar.value = kStartPage;
      tabs.refresh();
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

  Future<void> goHome() async {
    final tab = activeTab;
    tab.url = kStartPage;
    tab.title = kStartTitle;
    addressBar.value = kStartPage;
    tabs.refresh();
  }

  Future<void> navigate(String input) async {
    final url = _normalizeUrl(input);
    final tab = activeTab;
    tab.url = url;
    addressBar.value = url;
    if (url == kStartPage) {
      tabs.refresh();
      return;
    }
    await tab.controller.loadRequest(Uri.parse(url));
  }

  Future<void> reload() async {
    if (activeTab.isStart) return;
    await activeTab.controller.reload();
  }

  Future<void> goBack() async {
    if (activeTab.isStart) return;
    if (await activeTab.controller.canGoBack()) {
      await activeTab.controller.goBack();
    }
  }

  Future<void> goForward() async {
    if (activeTab.isStart) return;
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
            if (tabs.isNotEmpty && tabs[activeIndex.value.clamp(0, tabs.length - 1)] == tab) {
              addressBar.value = url;
            }
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
      );
    if (!tab.isStart) {
      tab.controller.loadRequest(Uri.parse(tab.url));
    }
  }

  static String _normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty || trimmed == kStartPage) return kStartPage;
    if (trimmed.contains(' ') && !trimmed.contains('.')) {
      return 'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }
}
