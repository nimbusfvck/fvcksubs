import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'cloudflare_killer.dart';

/// Loads a provider page in a headless WebView and returns the first resource
/// matching the pattern supplied by the extension.
///
/// This is deliberately a request resolver, not a player. It does not inspect
/// or start DOM media elements. Provider-specific matching belongs in the
/// extension's intercept pattern, while WebView lifecycle and cleanup stay
/// here.
class WebViewResolver {
  WebViewResolver({this.timeout = const Duration(seconds: 45)});

  final Duration timeout;
  final Map<String, Future<String?>> _inFlight = {};

  Future<String?> resolveMedia(
    String url, {
    String? referer,
    String? interceptPattern,
    String? clickUrl,
    String? callerId,
  }) {
    final key =
        '${callerId ?? '_global_'}\u0000$url\u0000${referer ?? ''}\u0000${interceptPattern ?? ''}\u0000${clickUrl ?? ''}';
    return _inFlight.putIfAbsent(key, () {
      final future = _resolve(
        url,
        referer: referer,
        interceptPattern: interceptPattern,
        clickUrl: clickUrl,
      );
      future.then<void>(
        (_) {
          if (identical(_inFlight[key], future)) _inFlight.remove(key);
        },
        onError: (Object _, StackTrace _) {
          if (identical(_inFlight[key], future)) _inFlight.remove(key);
        },
      );
      return future;
    });
  }

  Future<String?> _resolve(
    String url, {
    String? referer,
    String? interceptPattern,
    String? clickUrl,
  }) async {
    final matcher = RegExp(
      interceptPattern == null || interceptPattern.isEmpty
          ? r'(m3u8|master\.txt)'
          : interceptPattern,
      caseSensitive: false,
    );
    final result = Completer<String?>();
    late final HeadlessInAppWebView view;
    var running = false;
    var playerSelectionApplied = false;
    final cookieManager = CookieManager.instance();
    final browserCookies = await cookieManager.getCookies(url: WebUri(url));
    final cookieHeader = browserCookies
        .where(
          (cookie) => cookie.name.isNotEmpty && '${cookie.value}'.isNotEmpty,
        )
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
    final browserUserAgent = CloudflareKiller.userAgentFor(url);
    final requestHeaders = <String, String>{
      ...?(referer == null ? null : {'Referer': referer}),
      if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
      ...?(browserUserAgent == null ? null : {'User-Agent': browserUserAgent}),
    };
    _log(
      'browser_context host=${Uri.tryParse(url)?.host ?? ''} '
      'cookies=${browserCookies.length} '
      'has_user_agent=${browserUserAgent?.isNotEmpty == true}',
    );

    void consider(String? candidate) {
      if (result.isCompleted || candidate == null || candidate.isEmpty) {
        return;
      }
      if (!matcher.hasMatch(candidate)) return;
      final normalized = candidate.replaceAll(r'\/', '/');
      _log('intercepted host=${Uri.tryParse(url)?.host}');
      result.complete(normalized);
      if (running) unawaited(view.dispose());
    }

    void considerResource(LoadedResource resource) {
      consider(resource.url?.toString());
    }

    AjaxRequest keepAjaxRequest(AjaxRequest request) {
      // Ajax interception is only an observation point. Returning the same
      // request with its default PROCEED action keeps the page untouched.
      consider(request.responseURL?.toString());
      consider(request.url?.toString());
      return request;
    }

    FetchRequest keepFetchRequest(FetchRequest request) {
      // Fetch interception is only an observation point. Returning the same
      // request with its default PROCEED action keeps the page untouched.
      consider(request.url?.toString());
      return request;
    }

    Future<void> selectPlayer(InAppWebViewController controller) async {
      if (clickUrl == null || clickUrl.isEmpty || playerSelectionApplied) {
        return;
      }
      final target = jsonEncode(clickUrl);
      try {
        final outcome = await controller.evaluateJavascript(
          source:
              '''(() => {
            const target = $target;
            const links = Array.from(document.querySelectorAll(
              '#player-list a, a[data-url]'
            ));
            const link = links.find((node) =>
              node.getAttribute('data-url') === target ||
              node.href === target ||
              (node.getAttribute('data-url') &&
                new URL(node.getAttribute('data-url'), document.baseURI).href === target) ||
              (node.getAttribute('href') &&
                new URL(node.getAttribute('href'), document.baseURI).href === target)
            );
            if (link) {
              link.click();
              return 'clicked';
            }
            const frame = document.querySelector('#main-player');
            if (frame) {
              frame.src = target;
              return 'assigned';
            }
            return 'missing';
          })()''',
        );
        final outcomeText = outcome?.toString();
        playerSelectionApplied =
            outcomeText == 'clicked' || outcomeText == 'assigned';
        _log(
          'player_selection outcome=${outcomeText ?? 'null'} '
          'target=${_shortUrl(clickUrl)}',
        );
      } catch (_) {
        // Navigation can replace the document immediately after the player
        // source is selected; resource interception remains authoritative.
        _log('player_selection outcome=error target=${_shortUrl(clickUrl)}');
      }
    }

    view = HeadlessInAppWebView(
      initialSize: const Size(1280, 720),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
        // The player is commonly inside a nested iframe. Make both the
        // observer scripts and their bridge available there as well.
        pluginScriptsForMainFrameOnly: false,
        javaScriptBridgeForMainFrameOnly: false,
        // This WebView only observes requests. Never let a provider page
        // autoplay media or open a browser-style popup during interception.
        mediaPlaybackRequiresUserGesture: true,
        javaScriptCanOpenWindowsAutomatically: false,
        useOnLoadResource: true,
        useShouldInterceptAjaxRequest: true,
        useShouldInterceptFetchRequest: true,
        userAgent: browserUserAgent,
      ),
      initialUrlRequest: URLRequest(
        url: WebUri(url),
        headers: requestHeaders.isEmpty ? null : requestHeaders,
      ),
      onLoadResource: (_, resource) {
        considerResource(resource);
      },
      shouldInterceptAjaxRequest: (_, request) {
        return keepAjaxRequest(request);
      },
      shouldInterceptFetchRequest: (_, request) {
        return keepFetchRequest(request);
      },
      onLoadStop: (controller, _) async {
        await selectPlayer(controller);
        if (!playerSelectionApplied &&
            clickUrl != null &&
            clickUrl.isNotEmpty) {
          // Some pages attach the player-list handler after the initial load
          // event. Give that DOM a couple of short, provider-agnostic retries.
          unawaited(
            Future<void>.delayed(const Duration(milliseconds: 400), () async {
              await selectPlayer(controller);
              if (!playerSelectionApplied) {
                await Future<void>.delayed(const Duration(milliseconds: 800));
                await selectPlayer(controller);
              }
            }),
          );
        }
      },
    );

    try {
      await view.run();
      running = true;
      final deadline = DateTime.now().add(timeout);
      while (!result.isCompleted && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!result.isCompleted) {
        _log('timeout host=${Uri.tryParse(url)?.host}');
        result.complete(null);
      }
      return await result.future;
    } finally {
      running = false;
      await view.dispose();
    }
  }

  static void _log(String message) {
    if (kDebugMode) debugPrint('[WebViewResolver] $message');
  }

  static String _shortUrl(String? raw) {
    if (raw == null || raw.isEmpty) return '<none>';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return '<invalid-url>';
    final path = uri.pathSegments.isEmpty
        ? ''
        : '/${uri.pathSegments.take(3).join('/')}${uri.pathSegments.length > 3 ? '/…' : ''}';
    return '${uri.scheme}://${uri.host}$path';
  }
}
