import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:fvcksubs_js_runtime/fvcksubs_js_runtime.dart';

import 'webkit_lifecycle_coordinator.dart';

/// WebView-backed Cloudflare solver for extension HTTP fetches.
///
/// The browser is used only to obtain the challenge cookie and matching user
/// agent. The extension HTTP client performs the retried request, so cookies
/// never enter source ids or the player protocol.
class _CloudflareBrowser extends InAppBrowser {
  final Completer<void> _exited = Completer<void>();

  Future<void> waitForExit() => _exited.future;

  @override
  void onExit() {
    if (!_exited.isCompleted) _exited.complete();
  }
}

class CloudflareKiller {
  CloudflareKiller({
    this.timeout = const Duration(seconds: 25),
    WebKitLifecycleCoordinator? webKitLifecycle,
  }) : _webKitLifecycle = webKitLifecycle ?? WebKitLifecycleCoordinator();

  final Duration timeout;
  final WebKitLifecycleCoordinator _webKitLifecycle;
  final Map<String, Future<JsCloudflareChallenge?>> _inFlight = {};
  static final Map<String, String> _userAgentsByHost = {};

  /// Returns the User-Agent paired with the current browser clearance for a
  /// host so a generic WebView resolver can reuse the same browser context.
  static String? userAgentFor(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == null || host.isEmpty) return null;
    return _userAgentsByHost[host];
  }

  Future<JsCloudflareChallenge?> solve(
    String url, {
    String? referer,
    String? callerId,
  }) {
    final host = Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) return Future.value(null);
    final scopeKey = _scopeKey(callerId, host);
    return _inFlight.putIfAbsent(scopeKey, () {
      final future = _solve(url, referer: referer);
      future.then<void>(
        (_) {
          if (identical(_inFlight[scopeKey], future)) {
            _inFlight.remove(scopeKey);
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_inFlight[scopeKey], future)) {
            _inFlight.remove(scopeKey);
          }
        },
      );
      return future;
    });
  }

  /// Keeps concurrent browser work isolated per opaque caller and host.
  ///
  /// The solver deliberately does not interpret the caller id. It is only a
  /// lifecycle/session boundary supplied by the extension host.
  static String _scopeKey(String? callerId, String host) {
    final scope = callerId == null || callerId.trim().isEmpty
        ? '_global_'
        : callerId.trim();
    return '$scope::$host';
  }

  Future<JsCloudflareChallenge?> _solve(String url, {String? referer}) {
    if (Platform.isMacOS) {
      return _webKitLifecycle.run(
        'cloudflare_challenge',
        () => _solveInWebView(url, referer: referer, visibleBrowser: true),
      );
    }
    return _solveInWebView(url, referer: referer, visibleBrowser: false);
  }

  Future<JsCloudflareChallenge?> _solveInWebView(
    String url, {
    String? referer,
    required bool visibleBrowser,
  }) async {
    final uri = WebUri(url);
    final manager = CookieManager.instance();
    final existing = _cookieMap(await manager.getCookies(url: uri));
    if (existing.containsKey('cf_clearance')) {
      // A clearance cookie is bound to the browser session and User-Agent.
      // The request that reached this solver already rejected it, so replaying
      // the same cookie only sends the extension into another 403 loop. This
      // is intentionally scoped to the challenged host, not the whole jar.
      _log('stale_cookie host=${uri.host} refresh=true');
      await manager.deleteCookies(url: uri);
    }
    _log('challenge_start host=${uri.host}');

    if (visibleBrowser) {
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
        final userAgent = await _userAgent(view.webViewController);
        // Match CloudStream's solver contract: only a real clearance cookie
        // authorizes the HTTP client to retry the original request. Do not
        // return the WebView DOM here: a challenge/redirect document can look
        // like a successful same-host page while containing no player HTML.
        if (cookies.containsKey('cf_clearance')) {
          _log('challenge_ready host=${uri.host} cookies=${cookies.length}');
          _rememberUserAgent(uri.host, userAgent);
          return JsCloudflareChallenge(cookies: cookies, userAgent: userAgent);
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
            // The visible WebView exists only to solve Cloudflare. Never let
            // the challenged page autoplay its player or ads in this window;
            // playback belongs to the native VideoPlayerVOD route.
            mediaPlaybackRequiresUserGesture: true,
          ),
        ),
      );
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final cookies = _cookieMap(await manager.getCookies(url: uri));
        final userAgent = await _userAgent(browser.webViewController);
        if (cookies.containsKey('cf_clearance')) {
          _log(
            'visible_challenge_ready host=${uri.host} cookies=${cookies.length}',
          );
          _rememberUserAgent(uri.host, userAgent);
          return JsCloudflareChallenge(cookies: cookies, userAgent: userAgent);
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      _log('visible_challenge_timeout host=${uri.host}');
      return null;
    } finally {
      if (browser.isOpened()) {
        await browser.close();
        await browser.waitForExit();
      }
    }
  }

  static Map<String, String> _cookieMap(List<Cookie> cookies) => {
    for (final cookie in cookies)
      if (cookie.name.isNotEmpty && '${cookie.value}'.isNotEmpty)
        cookie.name: '${cookie.value}',
  };

  static void _rememberUserAgent(String host, String? userAgent) {
    if (userAgent == null || userAgent.isEmpty) return;
    _userAgentsByHost[host.toLowerCase()] = userAgent;
  }

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
