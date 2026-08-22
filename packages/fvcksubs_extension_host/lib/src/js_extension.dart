import 'dart:convert';

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_js_runtime/fvcksubs_js_runtime.dart';

import 'host_api.dart';

/// Thrown when a JS-backed extension fails: a bundle that won't load, a role
/// that throws, or a response that isn't the protocol shape.
class JsExtensionException implements Exception {
  /// Creates the exception.
  JsExtensionException(this.message, [this.cause]);

  /// What went wrong.
  final String message;

  /// The underlying error, when there was one.
  final Object? cause;

  @override
  String toString() =>
      'JsExtensionException: $message${cause == null ? '' : ' ($cause)'}';
}

/// A [ContentExtension] whose roles are implemented in JavaScript, run in a
/// vendored QuickJS engine (see `fvcksubs_js_runtime`).
///
/// Everything crossing the boundary is JSON. Protocol responses are decoded
/// into the shared core models before reaching the application.
///
/// **The manifest is not read from the bundle.** It's parsed from its own
/// `manifest.json` and passed in, so the engine's host allowlist is derived
/// from declared permissions *before* any bundle code runs. A bundle cannot
/// widen its own permissions.
///
/// Not thread-safe — create, use, and [dispose] one on a single isolate.
/// Concurrent role calls are fine: they interleave on the engine's shared JS
/// event loop, so a fan-out (`Future.wait` across providers, or Home loading
/// several shelves at once) needs one extension instance, not one per call.
class JsExtension extends ContentExtension {
  JsExtension._(this._manifest, this._engine);

  /// Loads [source] as [manifest]'s bundle.
  ///
  /// [prelude], when given, is evaluated before the bundle — a seam for
  /// tests, not a configuration mechanism.
  ///
  /// Throws [JsExtensionException] if the bundle fails to evaluate or doesn't
  /// install the surface the host calls.
  factory JsExtension.load({
    required Manifest manifest,
    required String source,
    String? prelude,
    Duration? scriptTimeout,
  }) {
    final engine = JsEngine(
      allowedHosts: manifest.permissions.hosts.toSet(),
      scriptTimeout: scriptTimeout ?? const Duration(seconds: 10),
    );
    try {
      // Before anything from the bundle: the host API it is allowed to use.
      HostApi.install(engine);
      if (prelude != null) engine.eval(prelude);
      engine.eval(source);
      final installed = engine.eval('typeof globalThis.__extension');
      if (installed != '"object"') {
        throw JsExtensionException(
          '${manifest.id}: bundle did not install globalThis.__extension',
        );
      }
    } on JsEvalException catch (e) {
      engine.dispose();
      throw JsExtensionException('${manifest.id}: bundle failed to load', e);
    } catch (_) {
      engine.dispose();
      rethrow;
    }
    return JsExtension._(manifest, engine);
  }

  final Manifest _manifest;
  final JsEngine _engine;

  @override
  Manifest get manifest => _manifest;

  @override
  Future<VersionedCatalogPage> catalog(CatalogQuery query) async {
    final decoded = await _call('catalog', query.toJson());
    return VersionedCatalogPage.fromProtocolJson(
      decoded,
      apiVersion: _manifest.apiVersion,
    );
  }

  @override
  Future<VersionedCatalogPage> search(String query, {String? page}) async {
    final decoded = await _call('search', {'query': query, 'page': ?page});
    return VersionedCatalogPage.fromProtocolJson(
      decoded,
      apiVersion: _manifest.apiVersion,
    );
  }

  @override
  Future<MediaDetailV2> meta(MediaRef ref) async {
    final decoded = await _call('meta', {'ref': ref.toJson()});
    return MediaDetailV2.fromJson(decoded);
  }

  /// Lists sources for [item].
  ///
  /// The whole item goes across, not just its ref — a stream extension
  /// matches broadcast candidates on title/participants/kickoff (PLAN.md
  /// §11), and re-deriving that from an id would cost a second fetch. Note
  /// that a JS extension has to do that matching *itself*: the matcher lives
  /// in `fvcksubs_core` and is not exposed as a host primitive, so a ported
  /// stream provider must either carry its own or get one added.
  @override
  Future<List<StreamSource>> sources(
    MediaItemV2 item, {
    Set<String>? enabledProviders,
  }) => _sourcesFromJson(item.toJson(), enabledProviders);

  Future<List<StreamSource>> _sourcesFromJson(
    Map<String, Object?> item,
    Set<String>? enabledProviders,
  ) async {
    final decoded = await _call('sources', {
      'item': item,
      if (enabledProviders != null)
        'enabledProviders': enabledProviders.toList(),
    });
    final list = decoded['sources'];
    if (list is! List) {
      throw JsExtensionException(
        '${_manifest.id}.sources did not return a "sources" list',
      );
    }
    return [
      for (final entry in list)
        StreamSource.fromJson((entry as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<PlayableStream> resolve(String sourceId) async {
    final decoded = await _call('resolve', {'sourceId': sourceId});
    return PlayableStream.fromJson(decoded);
  }

  @override
  Future<List<SubtitleTrack>> externalSubtitles(MediaItemV2 item) =>
      _subtitlesFromJson(item.toJson());

  Future<List<SubtitleTrack>> _subtitlesFromJson(
    Map<String, Object?> item,
  ) async {
    final decoded = await _call('subtitles', {'item': item});
    final list = decoded['subtitles'];
    if (list is! List) {
      throw JsExtensionException(
        '${_manifest.id}.subtitles did not return a "subtitles" list',
      );
    }
    return [
      for (final entry in list)
        SubtitleTrack.fromJson((entry as Map).cast<String, Object?>()),
    ];
  }

  /// Calls `__extension.<role>(<args>)` and decodes its JSON result.
  ///
  /// Arguments go in as a JSON literal rather than through a string the
  /// bundle would parse itself, so nothing in the query is ever interpreted
  /// as code.
  Future<Map<String, Object?>> _call(
    String role,
    Map<String, Object?> args,
  ) async {
    final String raw;
    try {
      raw = await _engine.evalAsync(
        'globalThis.__extension.$role(${jsonEncode(args)})',
      );
    } on JsEvalException catch (e) {
      throw JsExtensionException('${_manifest.id}.$role failed', e);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw JsExtensionException(
        '${_manifest.id}.$role returned malformed JSON',
        e,
      );
    }
    if (decoded is! Map) {
      throw JsExtensionException(
        '${_manifest.id}.$role returned ${decoded.runtimeType}, not an object',
      );
    }
    return decoded.cast<String, Object?>();
  }

  /// Frees the underlying engine. The extension is unusable afterwards.
  void dispose() => _engine.dispose();
}
