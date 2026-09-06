import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:fvcksubs_js_runtime/fvcksubs_js_runtime.dart';

/// WebView-backed Cloudflare solver for extension HTTP fetches.
///
/// The browser is used only to obtain the challenge cookie and matching user
/// agent. The extension HTTP client performs the retried request, so cookies
/// never enter source ids or the player protocol.
class _CloudflareBrowser extends InAppBrowser {}

class CloudflareKiller {
  CloudflareKiller({this.timeout = const Duration(seconds: 25)});

  final Duration timeout;
  final Map<String, Future<JsCloudflareChallenge?>> _inFlight = {};
  final Map<String, Future<String?>> _inFlightMedia = {};

  Future<JsCloudflareChallenge?> solve(String url, {String? referer}) {
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return Future.value(null);
    return _inFlight.putIfAbsent(host, () {
      final future = _solve(url, referer: referer);
      future.then<void>(
        (_) {
          if (identical(_inFlight[host], future)) _inFlight.remove(host);
        },
        onError: (Object _, StackTrace _) {
          if (identical(_inFlight[host], future)) _inFlight.remove(host);
        },
      );
      return future;
    });
  }

  /// Loads a provider page in a headless WebView and returns the first
  /// resource whose URL matches [interceptPattern]. This mirrors the
  /// CloudStream Filesim WebViewResolver fallback without exposing the page
  /// as an in-app browser tab.
  Future<String?> resolveMedia(
    String url, {
    String? referer,
    String? interceptPattern,
  }) {
    final key = '$url\u0000${referer ?? ''}\u0000${interceptPattern ?? ''}';
    return _inFlightMedia.putIfAbsent(key, () {
      final future = _resolveMedia(
        url,
        referer: referer,
        interceptPattern: interceptPattern,
      );
      future.then<void>(
        (_) {
          if (identical(_inFlightMedia[key], future)) {
            _inFlightMedia.remove(key);
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_inFlightMedia[key], future)) {
            _inFlightMedia.remove(key);
          }
        },
      );
      return future;
    });
  }

  Future<String?> _resolveMedia(
    String url, {
    String? referer,
    String? interceptPattern,
  }) async {
    final matcher = RegExp(
      interceptPattern == null || interceptPattern.isEmpty
          ? r'(m3u8|master\.txt)'
          : interceptPattern,
      caseSensitive: false,
    );
    String? captured;
    void consider(String? candidate) {
      if (captured != null || candidate == null || candidate.isEmpty) return;
      if (!matcher.hasMatch(candidate)) return;
      captured = candidate.replaceAll(r'\/', '/');
      _log('media_intercepted host=${Uri.tryParse(url)?.host}');
    }

    Future<void> scanPage(InAppWebViewController controller) async {
      try {
        // Some WebKit versions do not report cross-origin iframe/fetch
        // requests through onLoadResource. The DOM and Performance APIs still
        // expose the same URLs, including a player iframe inserted after the
        // initial document load.
        final value = await controller.evaluateJavascript(
          source: r'''(() => {
            const urls = [];
            try {
              performance.getEntriesByType('resource').forEach((entry) => {
                if (entry && entry.name) urls.push(entry.name);
              });
            } catch (_) {}
            try {
              document.querySelectorAll('iframe,video,source').forEach((node) => {
                const value = node.currentSrc || node.src || node.getAttribute('data-src');
                if (value) urls.push(value);
              });
            } catch (_) {}
            return JSON.stringify([...new Set(urls)]);
          })()''',
        );
        final raw = value?.toString() ?? '';
        final matches = RegExp(
          r'''https?://[^"'<>\s\\]+''',
        ).allMatches(raw).map((match) => match.group(0)).whereType<String>();
        for (final candidate in matches) {
          consider(candidate);
          if (captured != null) return;
        }

        // A number of HTML5 players do not request HLS until play() is called.
        // Start only real media elements; do not click arbitrary page buttons
        // because those are commonly advertisement links.
        await controller.evaluateJavascript(
          source: r'''(() => {
            document.querySelectorAll('video').forEach((video) => {
              try {
                video.muted = true;
                video.autoplay = true;
                const promise = video.play();
                if (promise && promise.catch) promise.catch(() => {});
              } catch (_) {}
            });
          })()''',
        );
      } catch (_) {
        // The page can navigate or its WebKit content process can terminate
        // between polling ticks; onLoadResource remains the fast path.
      }
    }

    final view = HeadlessInAppWebView(
      initialSize: const Size(1280, 720),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        useOnLoadResource: true,
      ),
      initialUrlRequest: URLRequest(
        url: WebUri(url),
        headers: referer == null ? null : {'Referer': referer},
      ),
      onLoadResource: (_, resource) {
        final candidate = resource.url?.toString();
        consider(candidate);
      },
      onLoadStop: (controller, _) async => scanPage(controller),
    );
    try {
      await view.run();
      final deadline = DateTime.now().add(timeout);
      while (captured == null && DateTime.now().isBefore(deadline)) {
        final controller = view.webViewController;
        if (controller != null) await scanPage(controller);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (captured == null) {
        _log('media_intercept_timeout host=${Uri.tryParse(url)?.host}');
      }
      return captured;
    } finally {
      await view.dispose();
    }
  }

  Future<JsCloudflareChallenge?> _solve(String url, {String? referer}) async {
    final uri = WebUri(url);
    final manager = CookieManager.instance();
    final existing = _cookieMap(await manager.getCookies(url: uri));
    if (existing.containsKey('cf_clearance')) {
      _log('existing_cookie host=${uri.host}');
      return JsCloudflareChallenge(cookies: existing);
    }
    _log('challenge_start host=${uri.host}');

    if (Platform.isMacOS) {
      return _solveWithVisibleBrowser(uri, manager, referer: referer);
    }

    final view = HeadlessInAppWebView(
      // The macOS implementation attaches headless views to the window, but
      // WebKit can throttle JavaScript in a 1x1 offscreen viewport. Keep a
      // realistic challenge viewport while the plugin keeps it visually
      // hidden.
      initialSize: const Size(1280, 720),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
      ),
      initialUrlRequest: URLRequest(
        url: uri,
        headers: referer == null ? null : {'Referer': referer},
      ),
    );

    try {
      await view.run();
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final cookies = _cookieMap(await manager.getCookies(url: uri));
        if (cookies.containsKey('cf_clearance')) {
          _log('challenge_ready host=${uri.host} cookies=${cookies.length}');
          return JsCloudflareChallenge(
            cookies: cookies,
            userAgent: await _userAgent(view.webViewController),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      _log('challenge_timeout host=${uri.host}');
      return null;
    } finally {
      await view.dispose();
    }
  }

  Future<JsCloudflareChallenge?> _solveWithVisibleBrowser(
    WebUri uri,
    CookieManager manager, {
    String? referer,
  }) async {
    final browser = _CloudflareBrowser();
    _log('visible_challenge_start host=${uri.host}');
    try {
      await browser.openUrlRequest(
        urlRequest: URLRequest(
          url: uri,
          headers: referer == null ? null : {'Referer': referer},
        ),
        settings: InAppBrowserClassSettings(
          // Cloudflare's managed challenge needs a rendered macOS WebKit
          // window. A transparent window is frequently throttled before it
          // can issue cf_clearance, so keep this short-lived window visible
          // and close it immediately after the cookie is available.
          browserSettings: InAppBrowserSettings(
            windowAlphaValue: 1.0,
            hideToolbarTop: true,
            hideToolbarBottom: true,
            hideTitleBar: true,
          ),
          webViewSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            thirdPartyCookiesEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
          ),
        ),
      );
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final cookies = _cookieMap(await manager.getCookies(url: uri));
        if (cookies.containsKey('cf_clearance')) {
          _log(
            'visible_challenge_ready host=${uri.host} cookies=${cookies.length}',
          );
          return JsCloudflareChallenge(
            cookies: cookies,
            userAgent: await _userAgent(browser.webViewController),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      _log('visible_challenge_timeout host=${uri.host}');
      return null;
    } finally {
      await browser.close();
    }
  }

  static Map<String, String> _cookieMap(List<Cookie> cookies) => {
    for (final cookie in cookies)
      if (cookie.name.isNotEmpty && '${cookie.value}'.isNotEmpty)
        cookie.name: '${cookie.value}',
  };

  static Future<String?> _userAgent(InAppWebViewController? controller) async {
    if (controller == null) return null;
    try {
      final value = await controller.evaluateJavascript(
        source: 'navigator.userAgent',
      );
      final userAgent = value?.toString();
      return userAgent == null || userAgent.isEmpty ? null : userAgent;
    } catch (_) {
      return null;
    }
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint('[CloudflareKiller] $message');
  }
}
