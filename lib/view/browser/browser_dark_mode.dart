/// Auto-dark for light-only web pages in the in-app browser.
///
/// The app runs in a dark appearance on every platform, so sites with a
/// native dark theme already pick it up through `prefers-color-scheme`. This
/// script covers the rest: once the DOM is ready it samples the backgrounds
/// actually on screen and, if the page is predominantly light, applies an
/// invert + hue-rotate filter to the root (re-inverting media so photos and
/// video keep their real colours). It is generic — no per-site rules — and
/// re-evaluates a few times after load so client-rendered pages settle.
///
/// Idempotent per document: re-injecting only updates the enabled flag.
library;

String autoDarkScript({required bool enabled}) =>
    _kAutoDarkJs.replaceFirst('__EREBRUS_DARK_ENABLED__', '$enabled');

const _kAutoDarkJs = r'''
(function () {
  var enabled = __EREBRUS_DARK_ENABLED__;
  var w = window, d = document;
  if (w.__erebrusAutoDark) { w.__erebrusAutoDark.set(enabled); return; }
  var ID = 'erebrus-auto-dark';
  var INVERT = 'invert(1) hue-rotate(180deg)';
  var CSS =
    // Zero-specificity base so pages with a transparent root still invert to
    // the app's near-black instead of exposing the WebView backdrop.
    ':where(html){background-color:#f5f5f3}' +
    'html{filter:' + INVERT + ' !important}' +
    'img,video,canvas,embed,object,iframe,svg image,' +
    '[style*="background-image"]{filter:' + INVERT + ' !important}' +
    '[style*="background-image"] img,[style*="background-image"] video{filter:none !important}' +
    // SVG images are overwhelmingly logos, icons and diagrams drawn for a
    // light page (e.g. black wordmarks): let them invert with the page so
    // they stay legible, instead of restoring them to dark-on-dark.
    'img[src*=".svg"],img[src^="data:image/svg"]{filter:none !important}';

  function rgba(s) {
    var m = /rgba?\(([^)]+)\)/.exec(s || '');
    if (!m) return null;
    var p = m[1].split(/[\s,\/]+/).filter(Boolean).map(parseFloat);
    if (p.length < 3) return null;
    return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1];
  }
  function lum(c) { return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255; }
  function opaqueBg(el) {
    for (; el && el.nodeType === 1; el = el.parentElement) {
      var c = rgba(getComputedStyle(el).backgroundColor);
      if (c && c[3] >= 0.6) return c;
    }
    return null;
  }
  // true = light page, false = dark page, null = not enough to judge yet.
  function pageIsLight() {
    var body = d.body;
    if (!body || !d.documentElement) return null;
    var W = w.innerWidth, H = w.innerHeight;
    if (!W || !H) return null;
    var pts = [[.5,.5],[.5,.2],[.5,.8],[.2,.5],[.8,.5],[.15,.12],[.85,.88]];
    var light = 0, dark = 0;
    for (var i = 0; i < pts.length; i++) {
      var el = d.elementFromPoint(W * pts[i][0], H * pts[i][1]);
      if (!el) continue;
      var c = opaqueBg(el);
      if (!c) continue;
      if (lum(c) > 0.55) light++; else dark++;
    }
    if (light + dark > 0) return light > dark;
    // Fully transparent page: judge by its text colour instead.
    var t = rgba(getComputedStyle(body).color);
    return t ? lum(t) < 0.45 : null;
  }
  function apply(on) {
    var s = d.getElementById(ID);
    if (on) {
      if (s) return;
      s = d.createElement('style');
      s.id = ID;
      s.textContent = CSS;
      (d.head || d.documentElement).appendChild(s);
    } else if (s) {
      s.parentNode.removeChild(s);
    }
  }
  function evaluate() {
    if (!state.enabled) { apply(false); return; }
    var light = pageIsLight();
    if (light !== null) apply(light);
  }
  var state = {
    enabled: enabled,
    set: function (on) { state.enabled = on; evaluate(); }
  };
  w.__erebrusAutoDark = state;
  function settle() {
    evaluate();
    setTimeout(evaluate, 800);
    setTimeout(evaluate, 2500);
  }
  if (d.readyState === 'loading') {
    d.addEventListener('DOMContentLoaded', settle, { once: true });
  } else {
    settle();
  }
  w.addEventListener('load', function () { evaluate(); setTimeout(evaluate, 1200); }, { once: true });
})();
''';
