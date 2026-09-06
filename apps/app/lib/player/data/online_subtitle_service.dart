import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:path_provider/path_provider.dart';

import '../../config/env.dart';

/// A subtitle returned by an online provider. The URL is resolved only when
/// the viewer selects a result; this keeps a search cheap and avoids storing
/// provider-specific metadata in the core [SubtitleTrack] protocol.
class OnlineSubtitleSearchResult {
  const OnlineSubtitleSearchResult({
    required this.id,
    required this.name,
    required this.language,
    required this.source,
    required this.provider,
    this.fileId,
    this.detailPath,
    this.hearingImpaired = false,
  });

  final String id;
  final String name;
  final String language;
  final String source;
  final String provider;
  final String? fileId;
  final String? detailPath;
  final bool hearingImpaired;
}

/// Subtitle search adapters used by the player subtitle sheet.
///
/// OpenSubtitles is enabled when an API key is supplied at build/run time.
/// SubSource remains the credential-free fallback.
class OnlineSubtitleSearchService {
  OnlineSubtitleSearchService({HttpClient? client})
    : _client = client ?? HttpClient();

  static const _subSourceApi = 'https://api.subsource.net';
  static const _openSubtitlesApi = 'https://api.opensubtitles.com/api/v1';
  static const _openSubtitlesApiKey = AppEnv.openSubtitlesApiKey ?? '';
  static const _openSubtitlesUserAgent = 'SkyStream v2.2.1';
  static const _headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36',
    'Referer': 'https://subsource.net/',
    'Origin': 'https://subsource.net/',
    'Accept': '*/*',
  };

  final HttpClient _client;

  void dispose() => _client.close(force: true);

  void _log(String message) {
    if (kDebugMode) debugPrint('[OnlineSubtitleSearch] $message');
  }

  Future<List<OnlineSubtitleSearchResult>> search({
    required String query,
    required String language,
    int? season,
    int? episode,
    int? year,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];
    _log(
      'start query="$cleanQuery" language=$language '
      'season=${season ?? '-'} episode=${episode ?? '-'} year=${year ?? '-'} '
      'openSubtitlesKey=${_openSubtitlesApiKey.isNotEmpty}',
    );
    if (_openSubtitlesApiKey.isNotEmpty) {
      try {
        _log('provider=OpenSubtitles request');
        final results = await _searchOpenSubtitles(
          query: cleanQuery,
          language: language,
          season: season,
          episode: episode,
          year: year,
        );
        _log('provider=OpenSubtitles filteredResults=${results.length}');
        if (results.isNotEmpty) return results;
      } catch (error) {
        _log(
          'provider=OpenSubtitles failed type=${error.runtimeType}; '
          'falling back to SubSource',
        );
        // Fall through to SubSource; subtitle search is best-effort.
      }
    }
    _log('provider=SubSource request');
    final results = await _searchSubSource(
      query: cleanQuery,
      language: language,
      season: season,
      episode: episode,
    );
    _log('provider=SubSource results=${results.length}');
    return results;
  }

  Future<List<OnlineSubtitleSearchResult>> _searchOpenSubtitles({
    required String query,
    required String language,
    int? season,
    int? episode,
    int? year,
  }) async {
    final params = <String, String>{
      'query': query,
      'languages': language,
      if (season != null && season > 0) 'season_number': '$season',
      if (episode != null && episode > 0) 'episode_number': '$episode',
      if (year != null && year > 0) 'year': '$year',
    };
    final response = await _jsonGet(
      Uri.parse(
        '$_openSubtitlesApi/subtitles',
      ).replace(queryParameters: params),
      headers: {
        'Api-Key': _openSubtitlesApiKey,
        'User-Agent': _openSubtitlesUserAgent,
      },
    );
    final data =
        (response['data'] as List?)?.whereType<Map>().toList() ?? const [];
    _log('OpenSubtitles rawResults=${data.length}');
    return [
      for (final item in data)
        if (((item['attributes'] as Map?)?['files'] as List?)?.isNotEmpty ??
            false)
          if (_matchesOpenSubtitleTarget(
            item,
            query: query,
            year: year,
            season: season,
            episode: episode,
          ))
            _openSubtitleResult(item, language, query),
    ];
  }

  OnlineSubtitleSearchResult _openSubtitleResult(
    Map item,
    String language,
    String query,
  ) {
    final attributes = (item['attributes'] as Map?) ?? const {};
    final files = (attributes['files'] as List?) ?? const [];
    final file = files.first as Map;
    final id = file['file_id'].toString();
    return OnlineSubtitleSearchResult(
      id: id,
      name: (attributes['release'] ?? query).toString(),
      language: language,
      source: 'OpenSubtitles',
      provider: 'opensubtitles',
      fileId: id,
      hearingImpaired: attributes['hearing_impaired'] == true,
    );
  }

  Future<List<OnlineSubtitleSearchResult>> _searchSubSource({
    required String query,
    required String language,
    int? season,
    int? episode,
  }) async {
    final search = await _jsonPost('$_subSourceApi/v1/movie/search', {
      'query': query,
      'includeSeasons': true,
      'limit': 10,
    });
    if (search['success'] != true) return const [];
    final found =
        (search['results'] as List?)?.whereType<Map>().toList() ?? const [];
    _log('SubSource movieCandidates=${found.length}');
    if (found.isEmpty) return const [];
    final selected = _selectSubSourceMovie(found, query);
    _log('SubSource selectedTitle=${selected?['title'] ?? '-'}');
    if (selected == null) return const [];
    final seasons =
        (selected['seasons'] as List?)?.whereType<Map>().toList() ?? const [];
    String? pagePath = selected['link'] as String?;
    if (seasons.isNotEmpty) {
      final wanted = season ?? 1;
      final match = seasons.firstWhere(
        (entry) => entry['season'] == wanted,
        orElse: () => seasons.first,
      );
      pagePath = (match['link'] as String?)?.replaceFirst('season=', 'season-');
    }
    _log('SubSource pagePath=${pagePath ?? '-'}');
    if (pagePath == null || pagePath.isEmpty) return const [];
    final page = await _textGet(
      pagePath.startsWith('http') ? pagePath : 'https://subsource.net$pagePath',
    );
    final wanted = _languageName(language);
    final results = <OnlineSubtitleSearchResult>[];
    // The Next.js page embeds its payload as an escaped JSON/RSC string
    // (`\"language\":...`). Normalize quote escaping before applying the
    // provider-independent parser so the same pattern works across page
    // render modes.
    final normalizedPage = page.replaceAll(r'\"', '"');
    final pattern = RegExp(
      r'"language":"' +
          RegExp.escape(wanted) +
          r'".{0,700}?"release_info":"([^"]*)".{0,500}?"link":"([^"]+)"',
      dotAll: true,
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(normalizedPage)) {
      final release = _unescape(match.group(1) ?? query);
      if (episode != null && !_matchesEpisode(release, episode)) continue;
      final detailPath = match.group(2);
      if (detailPath == null || detailPath.isEmpty) continue;
      results.add(
        OnlineSubtitleSearchResult(
          id: detailPath,
          name: release,
          language: language,
          source: 'SubSource',
          provider: 'subsource',
          detailPath: detailPath,
        ),
      );
    }
    _log(
      'SubSource parsedLanguage=$wanted parsedEpisodeResults=${results.length}',
    );
    return results;
  }

  /// Downloads and extracts a provider payload to a temporary subtitle file.
  /// The returned path is session-only and must not be persisted as a URL.
  Future<String> materialize(OnlineSubtitleSearchResult result) async {
    if (result.provider == 'opensubtitles') {
      return _materializeOpenSubtitles(result);
    }
    final detailPath = result.detailPath;
    if (detailPath == null || detailPath.isEmpty) {
      throw const FormatException('Subtitle detail path missing');
    }
    final detail = await _textGet('https://subsource.net/subtitle/$detailPath');
    final token = RegExp(
      r'https://api\.subsource\.net/v1/subtitle/download/[A-Za-z0-9]+',
    ).firstMatch(detail)?.group(0);
    if (token == null || token.isEmpty) {
      throw const FormatException('Subtitle token missing');
    }
    final payload = await _bytesGet(token);
    final content = _extractSubtitle(payload);
    final dir = await getTemporaryDirectory();
    final safeId = result.id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File('${dir.path}/fvcksubs-subtitle-$safeId.srt');
    await file.writeAsBytes(content, flush: true);
    return file.path;
  }

  Future<String> _materializeOpenSubtitles(
    OnlineSubtitleSearchResult result,
  ) async {
    final fileId = int.tryParse(result.fileId ?? result.id);
    if (fileId == null) throw const FormatException('Subtitle file id missing');
    final response = await _jsonPost(
      '$_openSubtitlesApi/download',
      {'file_id': fileId},
      headers: {
        'Api-Key': _openSubtitlesApiKey,
        'User-Agent': _openSubtitlesUserAgent,
      },
    );
    final link = (response['link'] as String?)?.trim();
    if (link == null || link.isEmpty) {
      throw const FormatException('OpenSubtitles download link missing');
    }
    final content = _extractSubtitle(await _bytesGet(link));
    final dir = await getTemporaryDirectory();
    final safeId = result.id.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final file = File('${dir.path}/fvcksubs-subtitle-$safeId.srt');
    await file.writeAsBytes(content, flush: true);
    return file.path;
  }

  Future<Map<String, dynamic>> _jsonPost(
    String url,
    Map<String, Object?> body, {
    Map<String, String>? headers,
  }) async {
    final bytes = await _request(
      'POST',
      Uri.parse(url),
      body: utf8.encode(jsonEncode(body)),
      headers: headers,
    );
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Invalid subtitle response');
    }
    return decoded.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> _jsonGet(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final decoded = jsonDecode(
      utf8.decode(await _request('GET', uri, headers: headers)),
    );
    if (decoded is! Map) {
      throw const FormatException('Invalid subtitle response');
    }
    return decoded.cast<String, dynamic>();
  }

  Future<Uint8List> _bytesGet(String url) => _request('GET', Uri.parse(url));

  Future<String> _textGet(String url) async =>
      utf8.decode(await _bytesGet(url), allowMalformed: true);

  Future<Uint8List> _request(
    String method,
    Uri uri, {
    List<int>? body,
    Map<String, String>? headers,
  }) async {
    final request = await _client.openUrl(method, uri);
    _headers.forEach(request.headers.set);
    headers?.forEach(request.headers.set);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.headers.contentLength = body.length;
      request.add(body);
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    _log(
      'http method=$method host=${uri.host} path=${uri.path} status=${response.statusCode}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Subtitle provider returned ${response.statusCode}',
        uri: uri,
      );
    }
    return Uint8List.fromList(bytes);
  }

  static Uint8List _extractSubtitle(Uint8List payload) {
    if (payload.length >= 2 && payload[0] == 0x1f && payload[1] == 0x8b) {
      payload = const GZipDecoder().decodeBytes(payload);
    }
    if (payload.length >= 4 && payload[0] == 0x50 && payload[1] == 0x4b) {
      final archive = ZipDecoder().decodeBytes(payload);
      final files = archive.files.where((file) {
        final name = file.name.toLowerCase();
        return !file.isDirectory &&
            (name.endsWith('.srt') || name.endsWith('.vtt'));
      }).toList()..sort((a, b) => a.name.length.compareTo(b.name.length));
      if (files.isEmpty) {
        throw const FormatException('Archive has no subtitle file');
      }
      return Uint8List.fromList(files.first.content as List<int>);
    }
    final text = utf8.decode(payload, allowMalformed: true);
    if (!text.contains('-->')) {
      throw const FormatException('Unsupported subtitle payload');
    }
    return payload;
  }

  static bool _matchesEpisode(String release, int episode) {
    final expected = episode.toString().padLeft(2, '0');
    final upper = release.toUpperCase();
    return RegExp('(?:^|[^A-Z0-9])E$expected(?:[^0-9]|\$)').hasMatch(upper) ||
        RegExp('S\\d{1,2}E$expected(?:[^0-9]|\$)').hasMatch(upper);
  }

  static Map? _selectSubSourceMovie(List<Map> results, String query) {
    final target = _titleTokens(query);
    if (target.isEmpty) return null;

    Map? best;
    var bestScore = -1;
    for (final result in results) {
      final tokens = _titleTokens(result['title']?.toString() ?? '');
      if (tokens.isEmpty) continue;
      final score = target.where(tokens.contains).length;
      final exact = score == target.length && tokens.length == target.length;
      final candidateScore = exact ? score + 100 : score;
      if (candidateScore > bestScore) {
        best = result;
        bestScore = candidateScore;
      }
    }
    return bestScore >= target.length ? best : null;
  }

  static bool _matchesOpenSubtitleTarget(
    Map item, {
    required String query,
    int? year,
    int? season,
    int? episode,
  }) {
    final attributes = (item['attributes'] as Map?) ?? const {};
    final details = (attributes['feature_details'] as Map?) ?? const {};
    final files = (attributes['files'] as List?) ?? const [];
    final candidates = <String>[
      details['title']?.toString() ?? '',
      details['movie_name']?.toString() ?? '',
      attributes['movie_name']?.toString() ?? '',
      attributes['release']?.toString() ?? '',
      for (final file in files)
        if (file is Map) file['file_name']?.toString() ?? '',
    ];
    final target = _titleTokens(query);
    final titleMatches = candidates.any((candidate) {
      final tokens = _titleTokens(candidate);
      return target.isNotEmpty && target.every(tokens.contains);
    });
    if (!titleMatches) return false;

    final rawYear = details['year'];
    if (year != null && rawYear is num && rawYear.toInt() != year) {
      return false;
    }
    final rawSeason = attributes['season_number'];
    if (season != null && rawSeason is num && rawSeason.toInt() != season) {
      return false;
    }
    final rawEpisode = attributes['episode_number'];
    if (episode != null && rawEpisode is num && rawEpisode.toInt() != episode) {
      return false;
    }
    return true;
  }

  static Set<String> _titleTokens(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((token) => token.length > 1 && token != 'the')
      .toSet();

  static String _languageName(String code) => switch (code.toLowerCase()) {
    'id' || 'in' || 'ind' => 'indonesian',
    'en' || 'eng' => 'english',
    _ => code.toLowerCase(),
  };

  static String _unescape(String value) =>
      value.replaceAll(r'\u0026', '&').replaceAll(r'\"', '"');
}
