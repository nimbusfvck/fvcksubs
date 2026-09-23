import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fvcksubs_core/fvcksubs_core.dart';

/// A short-lived loopback proxy for live streams.
///
/// Some live origins re-sign the same media segment on every playlist refresh.
/// The proxy gives that segment one stable local URI while refreshing the
/// upstream signed URI behind it. The proxy is deliberately session-scoped and
/// only accepts opaque resource ids created from the original stream.
class LocalHlsProxy {
  LocalHlsProxy({HttpClient? client, Random? random, this.logger})
    : _client = client ?? HttpClient(),
      _random = random ?? Random.secure();

  final HttpClient _client;
  final Random _random;
  final void Function(String message)? logger;
  final Map<String, _ProxySession> _sessions = {};
  final Map<String, String> _sessionKeys = {};
  HttpServer? _server;
  bool _disposed = false;

  Future<PlayableStream> wrap(PlayableStream stream) async {
    if (_disposed) throw StateError('The local HLS proxy is disposed.');
    final server = await _ensureServer();
    final sessionKey = _streamKey(stream);
    final existingId = _sessionKeys[sessionKey];
    final sessionId = existingId ?? _newToken(18);
    if (existingId == null) {
      _sessionKeys[sessionKey] = sessionId;
      _sessions[sessionId] = _ProxySession(
        sourceUrl: stream.url,
        playlistHeaders: Map<String, String>.unmodifiable(
          stream.playlistHeaders.isEmpty
              ? stream.headers
              : stream.playlistHeaders,
        ),
        segmentHeaders: Map<String, String>.unmodifiable(
          stream.segmentHeaders.isEmpty
              ? stream.headers
              : stream.segmentHeaders,
        ),
        isPlaylist: _looksLikePlaylist(stream),
      );
    }

    return PlayableStream(
      url: 'http://127.0.0.1:${server.port}/hls/$sessionId/root',
      format: stream.format,
      drm: stream.drm,
      audioUrl: stream.audioUrl,
      label: stream.label,
      subtitles: stream.subtitles,
      variants: stream.variants,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _sessions.clear();
    _sessionKeys.clear();
    _client.close(force: true);
    await _server?.close(force: true);
    _server = null;
  }

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_disposed) {
      await server.close(force: true);
      throw StateError('The local HLS proxy was disposed while starting.');
    }
    _server = server;
    unawaited(server.forEach(_handleRequest));
    return server;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.length != 3 || segments[0] != 'hls') {
      await _sendStatus(request.response, HttpStatus.notFound);
      return;
    }
    final session = _sessions[segments[1]];
    if (session == null) {
      await _sendStatus(request.response, HttpStatus.notFound);
      return;
    }

    final resourceId = segments[2];
    final resource = resourceId == 'root'
        ? session.rootResource
        : session.resources[resourceId];
    if (resource == null) {
      await _sendStatus(request.response, HttpStatus.notFound);
      return;
    }

    try {
      await _serveResource(request, session, resource);
    } catch (error) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {
        // The upstream or the client may already have closed the response.
      }
    }
  }

  Future<void> _serveResource(
    HttpRequest request,
    _ProxySession session,
    _ProxyResource resource,
  ) async {
    final upstream = await _client.openUrl(
      request.method,
      Uri.parse(resource.url),
    );
    resource.headers.forEach(upstream.headers.set);
    _copyRequestHeader(request, upstream, 'range');
    _copyRequestHeader(request, upstream, 'if-range');
    _copyRequestHeader(request, upstream, 'if-none-match');

    final upstreamResponse = await upstream.close();
    _log(
      'fetch id=${resource.id} '
      'kind=${resource.isPlaylist ? 'playlist' : 'segment'} '
      'status=${upstreamResponse.statusCode} '
      'range=${request.headers.value(HttpHeaders.rangeHeader) ?? '-'} '
      'bytes=${upstreamResponse.contentLength} '
      'upstream=${_safeProxyUrl(resource.url)}',
    );
    if (resource.isPlaylist) {
      await _servePlaylist(
        request.response,
        session,
        resource,
        upstreamResponse,
      );
      return;
    }
    await _pipeResponse(request.response, upstreamResponse);
  }

  Future<void> _servePlaylist(
    HttpResponse response,
    _ProxySession session,
    _ProxyResource resource,
    HttpClientResponse upstream,
  ) async {
    final bytes = await consolidateHttpClientResponseBytes(upstream);
    final text = utf8.decode(bytes, allowMalformed: true);
    if (!text.trimLeft().startsWith('#EXTM3U')) {
      response.statusCode = upstream.statusCode;
      response.headers.contentType = upstream.headers.contentType;
      response.headers.contentLength = bytes.length;
      response.add(bytes);
      await response.close();
      return;
    }
    final rewritten = _rewritePlaylist(text, session, resource.url);
    final rewrittenBytes = utf8.encode(rewritten);
    response.statusCode = upstream.statusCode;
    response.headers.contentType = ContentType(
      'application',
      'vnd.apple.mpegurl',
    );
    response.headers.contentLength = rewrittenBytes.length;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.add(rewrittenBytes);
    await response.close();
  }

  Future<void> _pipeResponse(
    HttpResponse response,
    HttpClientResponse upstream,
  ) async {
    response.statusCode = upstream.statusCode;
    _copyResponseHeader(upstream, response, HttpHeaders.contentTypeHeader);
    _copyResponseHeader(upstream, response, HttpHeaders.contentLengthHeader);
    _copyResponseHeader(upstream, response, HttpHeaders.contentRangeHeader);
    _copyResponseHeader(upstream, response, HttpHeaders.acceptRangesHeader);
    _copyResponseHeader(upstream, response, HttpHeaders.etagHeader);
    _copyResponseHeader(upstream, response, HttpHeaders.lastModifiedHeader);
    await upstream.pipe(response);
  }

  String _rewritePlaylist(
    String playlist,
    _ProxySession session,
    String playlistUrl,
  ) {
    final lines = playlist.split('\n');
    var nextUriIsPlaylist = false;
    var nextUriIsSegment = false;
    final output = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#EXT-X-VERSION')) {
        output.add(line);
        continue;
      }
      if (trimmed.startsWith('#EXT-X-STREAM-INF')) {
        nextUriIsPlaylist = true;
        output.add(line);
        continue;
      }
      if (trimmed.startsWith('#EXTINF') || trimmed.startsWith('#EXT-X-PART')) {
        nextUriIsSegment = true;
        output.add(line);
        continue;
      }
      if (trimmed.startsWith('#')) {
        output.add(_rewriteAttributeUris(line, session, playlistUrl));
        continue;
      }

      final uri = _resolveUri(playlistUrl, trimmed);
      final isPlaylist =
          nextUriIsPlaylist ||
          uri.path.toLowerCase().contains('.m3u8') ||
          (!nextUriIsSegment && uri.path.toLowerCase().contains('playlist'));
      final resource = session.resourceFor(
        uri,
        isPlaylist: isPlaylist,
        proxyBase: _proxyBase(session),
        log: _log,
      );
      output.add(resource.localUrl);
      nextUriIsPlaylist = false;
      nextUriIsSegment = false;
    }
    return output.join('\n');
  }

  String _rewriteAttributeUris(
    String line,
    _ProxySession session,
    String playlistUrl,
  ) => line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (match) {
    final uri = _resolveUri(playlistUrl, match.group(1)!);
    final resource = session.resourceFor(
      uri,
      isPlaylist: line.startsWith('#EXT-X-MEDIA'),
      proxyBase: _proxyBase(session),
      log: _log,
    );
    return 'URI="${resource.localUrl}"';
  });

  Uri _resolveUri(String baseUrl, String value) =>
      Uri.parse(baseUrl).resolve(value);

  String _proxyBase(_ProxySession session) {
    final entry = _sessions.entries.firstWhere(
      (entry) => entry.value == session,
    );
    final port = _server!.port;
    return 'http://127.0.0.1:$port/hls/${entry.key}';
  }

  String _newToken(int length) {
    final bytes = List<int>.generate(length, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _streamKey(PlayableStream stream) {
    String encodeHeaders(Map<String, String> values) {
      final entries = values.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return entries.map((e) => '${e.key}=${e.value}').join('&');
    }

    return '${stream.url}\u0000'
        '${encodeHeaders(stream.headers)}\u0000'
        '${encodeHeaders(stream.playlistHeaders)}\u0000'
        '${encodeHeaders(stream.segmentHeaders)}';
  }

  void _log(String message) => logger?.call('[LocalHlsProxy] $message');

  static bool _looksLikePlaylist(PlayableStream stream) {
    if (stream.format == StreamFormat.hls) return true;
    final path = Uri.tryParse(stream.url)?.path.toLowerCase() ?? '';
    return path.endsWith('.m3u8') || path.contains('playlist');
  }

  static void _copyRequestHeader(
    HttpRequest source,
    HttpClientRequest target,
    String name,
  ) {
    final value = source.headers.value(name);
    if (value != null) target.headers.set(name, value);
  }

  static void _copyResponseHeader(
    HttpClientResponse source,
    HttpResponse target,
    String name,
  ) {
    final value = source.headers.value(name);
    if (value != null) target.headers.set(name, value);
  }

  static Future<void> _sendStatus(HttpResponse response, int status) async {
    response.statusCode = status;
    await response.close();
  }
}

class _ProxySession {
  _ProxySession({
    required this.sourceUrl,
    required this.playlistHeaders,
    required this.segmentHeaders,
    required bool isPlaylist,
  }) : rootResource = _ProxyResource(
         id: 'root',
         url: sourceUrl,
         headers: playlistHeaders,
         isPlaylist: isPlaylist,
       );

  final String sourceUrl;
  final Map<String, String> playlistHeaders;
  final Map<String, String> segmentHeaders;
  final _ProxyResource rootResource;
  final Map<String, _ProxyResource> resources = {};
  final Map<String, String> idsByCanonicalUrl = {};
  int nextResourceId = 0;

  _ProxyResource resourceFor(
    Uri url, {
    required bool isPlaylist,
    required String proxyBase,
    required void Function(String message) log,
  }) {
    final canonical = _canonicalUrl(url);
    final existingId = idsByCanonicalUrl[canonical];
    if (existingId != null) {
      final existing = resources[existingId]!;
      final rotated = existing.url != url.toString();
      existing.url = url.toString();
      existing.isPlaylist = existing.isPlaylist || isPlaylist;
      log(
        'map id=$existingId '
        'kind=${existing.isPlaylist ? 'playlist' : 'segment'} '
        'rotated=$rotated upstream=${_safeProxyUrl(url.toString())}',
      );
      return existing..localUrl = '$proxyBase/$existingId';
    }
    final id = 'r${nextResourceId++}';
    idsByCanonicalUrl[canonical] = id;
    final resource = _ProxyResource(
      id: id,
      url: url.toString(),
      headers: isPlaylist ? playlistHeaders : segmentHeaders,
      isPlaylist: isPlaylist,
    )..localUrl = '$proxyBase/$id';
    resources[id] = resource;
    log(
      'map id=$id '
      'kind=${isPlaylist ? 'playlist' : 'segment'} '
      'rotated=false upstream=${_safeProxyUrl(url.toString())}',
    );
    return resource;
  }

  static String _canonicalUrl(Uri url) {
    // The segment object path is the stable identity. Signed query values
    // (date, expiry, signature, and credential) are expected to rotate.
    return url.replace(query: '').toString();
  }
}

class _ProxyResource {
  _ProxyResource({
    required this.id,
    required this.url,
    required this.headers,
    required this.isPlaylist,
  });

  final String id;
  String url;
  final Map<String, String> headers;
  bool isPlaylist;
  String localUrl = '';
}

String _safeProxyUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return '<invalid-url>';
  return '${uri.host}${uri.path}';
}

Future<List<int>> consolidateHttpClientResponseBytes(
  HttpClientResponse response,
) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
