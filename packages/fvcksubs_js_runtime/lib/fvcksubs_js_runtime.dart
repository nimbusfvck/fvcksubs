import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:dio/dio.dart';
import 'package:ffi/ffi.dart';

import 'fvcksubs_js_runtime_bindings_generated.dart' as bindings;

/// Thrown when a script passed to [JsEngine.eval]/[JsEngine.evalAsync]
/// throws inside QuickJS.
class JsEvalException implements Exception {
  JsEvalException(this.message);

  final String message;

  @override
  String toString() => 'JsEvalException: $message';
}

/// A function JS can call via the engine's `__host_call(name, argsJson)`.
///
/// Runs synchronously, on the same call stack as [JsEngine.eval] — see
/// [JsEngine.setHostFunction].
typedef HostFunction = String Function(String name, String argsJson);

/// A single QuickJS runtime + context, callable from Dart.
///
/// Proof-of-concept surface for PLAN.md's Phase 3 extension runtime: eval a
/// script, let it call one generic Dart-side function, let it make real,
/// host-allowlisted HTTP requests via `fetch(url, options)`, and cap what it
/// can consume (memory, C stack, JS execution time). Still no
/// `crypto`/`codec`/`storage` host primitives, and nothing wires this into
/// `ContentExtension` yet.
///
/// Not thread-safe: create, use, and [dispose] every [JsEngine] on the same
/// isolate. QuickJS itself never runs on a separate thread — `fetch`'s
/// asynchrony comes from ordinary Dart `Future`s on this isolate's own event
/// loop, not from a worker isolate or extra OS thread. The registered host
/// function and the `fetch` bridge are both invoked synchronously, inline
/// with whichever [JsEngine] call is on the stack, via
/// [ffi.NativeCallable.isolateLocal].
class JsEngine {
  /// Creates the engine.
  ///
  /// [allowedHosts] enforces PLAN.md §19's host allowlist for `fetch`:
  /// `null` (the default) allows every host — fine for tests and low-level
  /// use, but a real extension's engine should always pass its manifest's
  /// declared hosts. Entries may be an exact host, or `*.suffix` matching
  /// exactly one label in front of `suffix` (so `*.kora-plus.li` matches
  /// `a12.kora-plus.li` but not `kora-plus.li` or `x.a12.kora-plus.li`) —
  /// re-checked against every redirect hop, not just the initial URL.
  ///
  /// [memoryLimitBytes], [maxStackBytes] and [scriptTimeout] cap what a
  /// script can consume (PLAN.md §19). All three default to something
  /// generous but finite, so an engine is bounded unless deliberately
  /// opened up; pass [Duration.zero]/`0` to disable one. Exceeding any of
  /// them surfaces as a [JsEvalException], not a hang or a crash.
  ///
  /// [scriptTimeout] budgets *JS execution*, and is re-armed each time
  /// control enters JS — a script awaiting a slow `fetch` is charged for
  /// the code it runs, not for the host's round-trip. It is therefore not
  /// a bound on total wall-clock time for an [evalAsync]; [fetchTimeout]
  /// bounds each HTTP call separately.
  ///
  /// [fetchTimeout] is the default every call gets. A script may ask for
  /// more on one call — `fetch(url, {timeoutMs: 30000})` — up to
  /// [maxFetchTimeout], which is what stops one deliberately slow host from
  /// widening the budget for every other request the engine makes. A script
  /// can only *raise* its own call's timeout this way, never lower another
  /// one's, and the request itself carries no trace of the option: it is
  /// consumed here, not sent.
  JsEngine({
    Set<String>? allowedHosts,
    Duration? fetchTimeout,
    Duration? maxFetchTimeout,
    int? maxRedirects,
    int memoryLimitBytes = 64 * 1024 * 1024,
    int maxStackBytes = 1024 * 1024,
    Duration scriptTimeout = const Duration(seconds: 10),
  }) : _engine = bindings.qjsr_new_engine(),
       _allowedHosts = allowedHosts,
       _fetchTimeout = fetchTimeout ?? const Duration(seconds: 15),
       _maxFetchTimeout = maxFetchTimeout ?? const Duration(seconds: 45),
       _maxRedirects = maxRedirects ?? 10 {
    if (_engine == ffi.nullptr) {
      throw StateError('Failed to create QuickJS engine');
    }
    bindings.qjsr_set_limits(
      _engine,
      memoryLimitBytes,
      maxStackBytes,
      scriptTimeout.inMilliseconds,
    );
    _installFetch();
    eval(_fetchOptionsShim);
  }

  final ffi.Pointer<bindings.QjsrEngine> _engine;
  final Set<String>? _allowedHosts;
  final Duration _fetchTimeout;
  final Duration _maxFetchTimeout;
  final int _maxRedirects;
  final Dio _dio = Dio();

  ffi.NativeCallable<bindings.QjsrHostCallbackFunction>? _hostCallable;
  ffi.NativeCallable<bindings.QjsrFetchStartCallbackFunction>? _fetchCallable;
  final Map<int, Completer<String>> _pendingEvals = {};
  bool _disposed = false;

  /// Evaluates [code] as a global-scope script.
  ///
  /// Returns the result JSON-stringified where possible (covers objects,
  /// arrays, primitives), or its plain `String()` when JSON can't represent
  /// it (e.g. a bare `undefined`). Throws [JsEvalException] if the script
  /// itself throws. `code` must not depend on `fetch` settling — its result
  /// is read synchronously; use [evalAsync] for scripts that `await`.
  String eval(String code) {
    _checkNotDisposed();
    final codePtr = code.toNativeUtf8();
    final errorOut = calloc<ffi.Pointer<ffi.Char>>();
    try {
      final result = bindings.qjsr_eval(_engine, codePtr.cast(), errorOut);
      if (result == ffi.nullptr) {
        throw JsEvalException(_takeError(errorOut) ?? 'unknown QuickJS error');
      }
      return _takeString(result);
    } finally {
      calloc.free(codePtr);
      calloc.free(errorOut);
    }
  }

  /// Evaluates [code] as a global-scope script whose result may be a
  /// pending Promise — an async IIFE (`(async () => { ... await
  /// fetch(url) ... })()`) or a `.then()` chain. Bare top-level `await`,
  /// outside any function, isn't supported; wrap the script as above.
  ///
  /// Returns a [Future] that completes with the script's settled result
  /// (same JSON-or-ToString shape as [eval]), or fails with
  /// [JsEvalException] if the script throws or its promise rejects.
  ///
  /// Several calls may be in flight at once. They share one JS event loop —
  /// interleaved the way concurrent work in a browser is, not run in
  /// parallel — so a fan-out across providers needs one engine, not one per
  /// call. Scripts do share global scope, though: two that both write
  /// `globalThis.x` will see each other.
  Future<String> evalAsync(String code) {
    _checkNotDisposed();
    final codePtr = code.toNativeUtf8();
    final errorOut = calloc<ffi.Pointer<ffi.Char>>();
    final pendingOut = calloc<ffi.Bool>();
    final evalIdOut = calloc<ffi.Uint32>();
    try {
      final result = bindings.qjsr_eval_async(
        _engine,
        codePtr.cast(),
        errorOut,
        pendingOut,
        evalIdOut,
      );
      if (pendingOut.value) {
        final completer = Completer<String>();
        _pendingEvals[evalIdOut.value] = completer;
        return completer.future;
      }
      if (result == ffi.nullptr) {
        return Future.error(
          JsEvalException(_takeError(errorOut) ?? 'unknown QuickJS error'),
        );
      }
      return Future.value(_takeString(result));
    } finally {
      calloc.free(codePtr);
      calloc.free(errorOut);
      calloc.free(pendingOut);
      calloc.free(evalIdOut);
    }
  }

  /// Registers [fn] as this engine's `__host_call` target, replacing any
  /// previously registered one. Pass `null` to clear it — JS calling
  /// `__host_call` then throws.
  void setHostFunction(HostFunction? fn) {
    _checkNotDisposed();
    _hostCallable?.close();
    _hostCallable = null;

    if (fn == null) {
      bindings.qjsr_set_host_callback(_engine, ffi.nullptr);
      return;
    }

    final callable =
        ffi.NativeCallable<bindings.QjsrHostCallbackFunction>.isolateLocal((
          ffi.Pointer<ffi.Char> namePtr,
          ffi.Pointer<ffi.Char> argsPtr,
        ) {
          final name = namePtr.cast<Utf8>().toDartString();
          final args = argsPtr.cast<Utf8>().toDartString();
          return fn(name, args).toNativeUtf8().cast<ffi.Char>();
        });
    _hostCallable = callable;
    bindings.qjsr_set_host_callback(_engine, callable.nativeFunction);
  }

  void _installFetch() {
    final callable =
        ffi.NativeCallable<bindings.QjsrFetchStartCallbackFunction>.isolateLocal((
          int requestId,
          ffi.Pointer<ffi.Char> urlPtr,
          ffi.Pointer<ffi.Char> methodPtr,
          ffi.Pointer<ffi.Char> headersJsonPtr,
          ffi.Pointer<ffi.Char> bodyPtr,
        ) {
          final url = urlPtr.cast<Utf8>().toDartString();
          final method = methodPtr.cast<Utf8>().toDartString();
          final headersJson = headersJsonPtr.cast<Utf8>().toDartString();
          final body = bodyPtr == ffi.nullptr
              ? null
              : bodyPtr.cast<Utf8>().toDartString();
          unawaited(_startFetch(requestId, url, method, headersJson, body));
        });
    _fetchCallable = callable;
    bindings.qjsr_set_fetch_start_callback(_engine, callable.nativeFunction);
  }

  Future<void> _startFetch(
    int requestId,
    String url,
    String method,
    String headersJson,
    String? body,
  ) async {
    try {
      final headers = (jsonDecode(headersJson) as Map).cast<String, dynamic>();
      final result = await _performFetch(
        url: url,
        method: method,
        headers: headers,
        timeout: _takeRequestTimeout(headers),
        body: body,
      );
      _resolveFetch(
        requestId,
        status: result.status,
        headersJson: jsonEncode(result.headers),
        finalUrl: result.url,
        body: result.body,
      );
    } catch (e) {
      _resolveFetch(requestId, errorMessage: e.toString());
    }
  }

  /// Removes the shim's private timeout header from [headers] and returns
  /// the timeout it asked for, clamped to `[_fetchTimeout, _maxFetchTimeout]`.
  ///
  /// Removing it matters as much as reading it: the option travels as a
  /// header only because that is the one channel the native `fetch` bridge
  /// already carries, and an extension's own header must never leave the
  /// process.
  Duration _takeRequestTimeout(Map<String, dynamic> headers) {
    final key = headers.keys.firstWhere(
      (name) => name.toLowerCase() == _timeoutHeader,
      orElse: () => '',
    );
    if (key.isEmpty) return _fetchTimeout;
    final requested = int.tryParse('${headers.remove(key)}');
    if (requested == null || requested <= 0) return _fetchTimeout;
    final asked = Duration(milliseconds: requested);
    if (asked < _fetchTimeout) return _fetchTimeout;
    return asked > _maxFetchTimeout ? _maxFetchTimeout : asked;
  }

  Future<_FetchResult> _performFetch({
    required String url,
    required String method,
    required Map<String, dynamic> headers,
    required Duration timeout,
    required String? body,
  }) async {
    var currentUrl = url;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final uri = Uri.parse(currentUrl);
      final allowed = _allowedHosts;
      if (allowed != null && !_hostAllowed(uri.host, allowed)) {
        throw StateError('host not allowed: ${uri.host}');
      }

      final response = await _dio.requestUri<List<int>>(
        uri,
        data: body,
        options: Options(
          method: method,
          headers: headers,
          responseType: ResponseType.bytes,
          followRedirects: false,
          validateStatus: (_) => true,
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );

      final status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        final location = response.headers.value('location');
        if (location != null) {
          currentUrl = uri.resolve(location).toString();
          continue;
        }
      }

      final responseHeaders = <String, String>{
        for (final entry in response.headers.map.entries)
          entry.key: entry.value.join(', '),
      };
      return _FetchResult(
        status: status,
        headers: responseHeaders,
        url: currentUrl,
        body: utf8.decode(response.data ?? const [], allowMalformed: true),
      );
    }
    throw StateError('too many redirects');
  }

  void _resolveFetch(
    int requestId, {
    int status = 0,
    String? headersJson,
    String? finalUrl,
    String? body,
    String? errorMessage,
  }) {
    // A fetch can settle after the engine is gone — an extension replaced by
    // an update, or one that left a request in flight when it was disposed.
    // Handing the result to a freed engine is a use-after-free, and there is
    // no JS left to deliver it to anyway.
    if (_disposed) return;
    final headersPtr = (headersJson ?? '{}').toNativeUtf8();
    final urlPtr = (finalUrl ?? '').toNativeUtf8();
    final bodyPtr = (body ?? '').toNativeUtf8();
    final errorPtr = errorMessage?.toNativeUtf8() ?? ffi.nullptr;
    try {
      bindings.qjsr_resolve_fetch(
        _engine,
        requestId,
        status,
        headersPtr.cast(),
        urlPtr.cast(),
        bodyPtr.cast(),
        errorPtr == ffi.nullptr ? ffi.nullptr : errorPtr.cast(),
      );
    } finally {
      calloc.free(headersPtr);
      calloc.free(urlPtr);
      calloc.free(bodyPtr);
      if (errorPtr != ffi.nullptr) calloc.free(errorPtr);
    }
    _drainCompletions();
  }

  /// Completes every eval that settled since the last check.
  ///
  /// A loop, not a single take: one fetch can unblock several scripts at
  /// once (two catalogs awaiting the same host, a `Promise.all` fanning
  /// back in), and stopping after the first would strand the rest until
  /// some unrelated fetch happened to run.
  void _drainCompletions() {
    final outId = calloc<ffi.Uint32>();
    final outError = calloc<ffi.Pointer<ffi.Char>>();
    try {
      while (true) {
        final value = bindings.qjsr_take_completion(_engine, outId, outError);
        if (outId.value == 0) return;

        final completer = _pendingEvals.remove(outId.value);
        final errorPtr = outError.value;
        if (errorPtr != ffi.nullptr) {
          final message = _takeString(errorPtr);
          completer?.completeError(JsEvalException(message));
        } else if (value != ffi.nullptr) {
          final result = _takeString(value);
          completer?.complete(result);
        } else {
          completer?.complete('undefined');
        }
      }
    } finally {
      calloc.free(outId);
      calloc.free(outError);
    }
  }

  /// Frees the underlying QuickJS runtime + context. The engine is unusable
  /// after this — call it exactly once, when done with the engine.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _hostCallable?.close();
    _hostCallable = null;
    _fetchCallable?.close();
    _fetchCallable = null;
    _dio.close();
    bindings.qjsr_free_engine(_engine);
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('JsEngine already disposed');
  }

  static String _takeString(ffi.Pointer<ffi.Char> ptr) {
    final value = ptr.cast<Utf8>().toDartString();
    bindings.qjsr_free_string(ptr);
    return value;
  }

  static String? _takeError(ffi.Pointer<ffi.Pointer<ffi.Char>> errorOut) {
    final errorPtr = errorOut.value;
    if (errorPtr == ffi.nullptr) return null;
    return _takeString(errorPtr);
  }
}

/// Single-label wildcard host matching for PLAN.md §19's allowlist:
/// `*.suffix` matches exactly one label in front of `suffix`.
///
/// A bare `*` entry allows every host. It is a deliberate opt-out of the
/// allowlist, not a shorthand: an extension whose stream URLs are handed to
/// it by upstream at runtime cannot enumerate the hosts it will contact, and
/// pinning them made the manifest churn without bounding playback, which
/// reaches those hosts through the native player rather than through `fetch`.
/// The install prompt states the widened access, so the user decides.
bool _hostAllowed(String host, Set<String> allowed) {
  final lower = host.toLowerCase();
  for (final pattern in allowed) {
    final lowerPattern = pattern.toLowerCase();
    if (lowerPattern == '*') {
      return true;
    } else if (lowerPattern.startsWith('*.')) {
      final suffix = lowerPattern.substring(1); // ".suffix"
      if (lower.length <= suffix.length || !lower.endsWith(suffix)) continue;
      final label = lower.substring(0, lower.length - suffix.length);
      if (!label.contains('.')) return true;
    } else if (lower == lowerPattern) {
      return true;
    }
  }
  return false;
}

/// Name of the private header the [_fetchOptionsShim] moves `timeoutMs`
/// into. Lower-case: [JsEngine._takeRequestTimeout] matches case-insensitively
/// against it and strips it before the request goes out.
const _timeoutHeader = 'x-qjsr-timeout-ms';

/// Teaches the native `fetch` one option it has no parameter for.
///
/// The C bridge carries exactly url/method/headers/body, and widening that
/// signature would mean regenerating the FFI bindings for every platform to
/// pass a single integer. A JS wrapper that folds `timeoutMs` into a private
/// header keeps the whole feature inside this library — the wrapper puts it
/// in, [JsEngine._takeRequestTimeout] takes it back out, and nothing
/// downstream (or upstream) ever sees it.
///
/// Installed before any script runs, so a bundle cannot get at the
/// unwrapped `fetch` to smuggle the header in by hand.
const _fetchOptionsShim = '''
(() => {
  const nativeFetch = globalThis.fetch;
  if (typeof nativeFetch !== 'function') return;
  globalThis.fetch = function (url, options) {
    if (!options || options.timeoutMs == null) return nativeFetch(url, options);
    const headers = {};
    if (options.headers && typeof options.headers === 'object') {
      for (const key of Object.keys(options.headers)) {
        if (String(key).toLowerCase() === '$_timeoutHeader') continue;
        headers[key] = options.headers[key];
      }
    }
    headers['$_timeoutHeader'] = String(options.timeoutMs);
    const next = {};
    for (const key of Object.keys(options)) {
      if (key === 'timeoutMs' || key === 'headers') continue;
      next[key] = options[key];
    }
    next.headers = headers;
    return nativeFetch(url, next);
  };
})();
''';

class _FetchResult {
  _FetchResult({
    required this.status,
    required this.headers,
    required this.url,
    required this.body,
  });

  final int status;
  final Map<String, String> headers;
  final String url;
  final String body;
}
