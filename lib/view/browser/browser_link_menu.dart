import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'browser_chrome.dart';
import 'browser_controller.dart';

/// A link the user long-pressed inside a WebView page.
class BrowserLinkHit {
  const BrowserLinkHit({required this.url, required this.label});

  final String url;
  final String label;
}

/// JavaScript injected on each page load to capture link long-presses and
/// forward them to the [kLinkContextMenuChannel] JavaScript channel. It also
/// routes `target="_blank"` links and `window.open` to [kNewTabChannel], so
/// only real web pages the user asked for become new tabs.
const kLinkContextMenuChannel = 'ErebrusLink';
const kNewTabChannel = 'ErebrusNewTab';

const kLinkContextMenuJs = '''
(function () {
  if (window.__erebrusLinkMenuInstalled) return;
  window.__erebrusLinkMenuInstalled = true;

  var LONG_PRESS_MS = 450;
  var suppressClickUntil = 0;
  var pressTimer = null;
  var pressAnchor = null;

  function findAnchor(node) {
    while (node) {
      if (node.nodeType === 1 && node.tagName === 'A' && node.href) return node;
      node = node.parentElement;
    }
    return null;
  }

  function payload(anchor) {
    var text = '';
    try { text = (anchor.innerText || anchor.textContent || '').trim(); } catch (e) {}
    return JSON.stringify({ url: anchor.href, text: text });
  }

  function post(anchor) {
    if (typeof ErebrusLink !== 'undefined' && ErebrusLink.postMessage) {
      ErebrusLink.postMessage(payload(anchor));
    }
  }

  function isWebUrl(url) {
    return typeof url === 'string' && /^https?:/i.test(url);
  }

  function openNewTab(url) {
    if (!isWebUrl(url)) return false;
    if (typeof ErebrusNewTab !== 'undefined' && ErebrusNewTab.postMessage) {
      ErebrusNewTab.postMessage(url);
      return true;
    }
    return false;
  }

  function clearPress() {
    if (pressTimer) {
      clearTimeout(pressTimer);
      pressTimer = null;
    }
    pressAnchor = null;
  }

  document.addEventListener('click', function (e) {
    if (Date.now() < suppressClickUntil) {
      e.preventDefault();
      e.stopImmediatePropagation();
      return;
    }
    var anchor = findAnchor(e.target);
    if (!anchor) return;
    var target = (anchor.getAttribute('target') || '').toLowerCase();
    var wantsNewTab = target === '_blank' || e.metaKey || e.ctrlKey || e.button === 1;
    if (wantsNewTab && openNewTab(anchor.href)) {
      e.preventDefault();
      e.stopImmediatePropagation();
    }
  }, true);

  // Pop-ups become tabs only for real http(s) URLs; blank/scripted pop-ups
  // (ads, about:blank shells) are dropped instead of spawning empty tabs.
  window.open = function (url) {
    var resolved = '';
    try { resolved = url ? new URL(String(url), document.baseURI).href : ''; } catch (e) {}
    openNewTab(resolved);
    return null;
  };

  document.addEventListener('touchstart', function (e) {
    var anchor = findAnchor(e.target);
    if (!anchor) return;
    pressAnchor = anchor;
    if (pressTimer) clearTimeout(pressTimer);
    pressTimer = setTimeout(function () {
      if (!pressAnchor) return;
      suppressClickUntil = Date.now() + 900;
      post(pressAnchor);
      clearPress();
    }, LONG_PRESS_MS);
  }, { passive: true, capture: true });

  document.addEventListener('touchmove', clearPress, { passive: true, capture: true });
  document.addEventListener('touchend', clearPress, { passive: true, capture: true });
  document.addEventListener('touchcancel', clearPress, { passive: true, capture: true });

  document.addEventListener('contextmenu', function (e) {
    var anchor = findAnchor(e.target);
    if (!anchor) return;
    e.preventDefault();
    suppressClickUntil = Date.now() + 900;
    post(anchor);
  }, true);
})();
''';

BrowserLinkHit? parseBrowserLinkHit(String message) {
  try {
    final data = jsonDecode(message) as Map<String, dynamic>;
    final url = (data['url'] as String?)?.trim() ?? '';
    if (url.isEmpty) return null;
    final label = (data['text'] as String?)?.trim() ?? '';
    return BrowserLinkHit(url: url, label: label);
  } catch (_) {
    return null;
  }
}

Future<void> showBrowserLinkContextMenu(
  BuildContext context,
  BrowserController controller,
  BrowserLinkHit hit,
) async {
  if (!BrowserController.isWebUrl(hit.url)) return;
  final label = hit.label.isNotEmpty ? hit.label : hit.url;
  controller.setRouteCovered(true);
  ModalRoute<dynamic>? menuRoute;

  try {
    await showBrowserSheet<void>(
      context,
      builder: (ctx) {
        menuRoute = ModalRoute.of(ctx);
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrowserSheetHeader(
                icon: Icons.link,
                title: label,
                subtitle: hit.url,
              ),
              BrowserSheetGroup(
                children: [
                  BrowserSheetTile(
                    icon: Icons.open_in_browser,
                    title: 'Open',
                    onTap: () {
                      Navigator.pop(ctx);
                      controller.openLink(hit.url);
                    },
                  ),
                  BrowserSheetTile(
                    icon: Icons.open_in_new,
                    title: 'Open in new tab',
                    onTap: () {
                      Navigator.pop(ctx);
                      controller.openInNewTab(hit.url);
                    },
                  ),
                  BrowserSheetTile(
                    icon: Icons.tab,
                    title: 'Open in background tab',
                    onTap: () {
                      Navigator.pop(ctx);
                      controller.openInBackgroundTab(hit.url);
                    },
                  ),
                ],
              ),
              BrowserSheetGroup(
                children: [
                  BrowserSheetTile(
                    icon: Icons.copy_rounded,
                    title: 'Copy link',
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: hit.url));
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        showBrowserToast(context, 'Link copied');
                      }
                    },
                  ),
                  if (hit.label.isNotEmpty)
                    BrowserSheetTile(
                      icon: Icons.short_text,
                      title: 'Copy link text',
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: hit.label));
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          showBrowserToast(context, 'Link text copied');
                        }
                      },
                    ),
                  BrowserSheetTile(
                    icon: Icons.launch,
                    title: 'Open in external browser',
                    subtitle: 'Leaves the private browser',
                    onTap: () async {
                      Navigator.pop(ctx);
                      final uri = Uri.tryParse(hit.url);
                      if (uri == null) return;
                      var launched = false;
                      try {
                        launched = await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (_) {
                        launched = false;
                      }
                      if (!launched && context.mounted) {
                        showBrowserToast(
                          context,
                          'Could not open the external browser',
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  } finally {
    await menuRoute?.completed;
    if (context.mounted) {
      controller.setRouteCovered(ModalRoute.of(context)?.isCurrent == false);
    }
  }
}
