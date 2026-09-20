import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:path_provider/path_provider.dart';

/// Translates an SRT/WebVTT subtitle file into a target language through the
/// Lingva REST API. The app only consumes the API; it does not embed Lingva.
///
/// Cue timestamps are preserved. Repeated cue text is translated once and a
/// failed line keeps its original text, so translation never removes a usable
/// subtitle track.
class SubtitleTranslateService {
  SubtitleTranslateService._();
  static final SubtitleTranslateService instance = SubtitleTranslateService._();

  // Keep the endpoint replaceable for a self-hosted Lingva instance.
  static const _lingvaBaseUrl = 'https://lingva.ml';
  // Lingva instances depend on scraping Google Translate and can go down
  // independently of the app. MyMemory is used only as a public fallback.
  static const _myMemoryBaseUrl = 'https://api.mymemory.translated.net/get';

  final Dio _dio = Dio(
    BaseOptions(
      responseType: ResponseType.plain,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
    ),
  );

  // Keyed by source/target ISO codes and cue text.
  final Map<String, String> _cache = {};

  static const _batchCueLimit = 10;
  static const _batchCharacterLimit = 1200;

  /// Translates [content] to [targetIso] (ISO-639-1, for example `id`).
  /// Reports progress from 0 to 1 and throws when cues cannot be translated.
  Future<String> translate(
    String content,
    String targetIso, {
    String? sourceIso,
    void Function(double)? onProgress,
  }) => _translateContent(
    content,
    targetIso,
    sourceIso: sourceIso,
    onProgress: onProgress,
  );

  /// Translates a subtitle track and materializes the result for the native
  /// player. The returned file is session-only and must not be persisted.
  Future<SubtitleTrack> translateTrack(
    SubtitleTrack source, {
    required String targetIso,
  }) async {
    final content = await _readContent(source.url);
    final translated = await translate(
      content,
      targetIso,
      sourceIso: _languageCode(source.language),
    );
    final directory = await getTemporaryDirectory();
    final safeTarget = targetIso.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(
      '${directory.path}/fvcksubs-translated-$safeTarget-'
      '${DateTime.now().microsecondsSinceEpoch}.srt',
    );
    await file.writeAsString(translated, flush: true);
    return SubtitleTrack(
      language: targetIso,
      url: file.path,
      label:
          'Translated ${source.label.isEmpty ? source.language : source.label}',
    );
  }

  Future<String> _translateContent(
    String content,
    String targetIso, {
    required String? sourceIso,
    void Function(double)? onProgress,
  }) async {
    final cues = _parse(content);
    if (cues.isEmpty) {
      throw const FormatException('No SRT/VTT cues found to translate');
    }

    final unique = <String>[];
    final seen = <String>{};
    for (final cue in cues) {
      if (seen.add(cue.text)) unique.add(cue.text);
    }

    final result = <String, String>{};
    var done = 0;
    final batches = _makeBatches(unique);
    var next = 0;
    var translatedCount = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= batches.length) break;
        final batch = batches[index];
        final translated = await _translateBatch(
          batch,
          targetIso,
          sourceIso: sourceIso,
        );
        for (final entry in translated.entries) {
          result[entry.key] = entry.value.text;
          if (entry.value.wasTranslated) translatedCount++;
        }
        done += batch.length;
        onProgress?.call(done / unique.length);
      }
    }

    const concurrency = 3;
    await Future.wait(List.generate(concurrency, (_) => worker()));
    if (translatedCount == 0) {
      throw StateError('Translation service returned no translations');
    }
    if (kDebugMode) {
      debugPrint(
        '[translate] target=$targetIso translated_cues='
        '$translatedCount/${unique.length}',
      );
    }

    final output = StringBuffer();
    for (var i = 0; i < cues.length; i++) {
      final cue = cues[i];
      output
        ..writeln(i + 1)
        ..writeln('${cue.start} --> ${cue.end}')
        ..writeln(result[cue.text] ?? cue.text)
        ..writeln();
    }
    return output.toString();
  }

  List<List<String>> _makeBatches(List<String> texts) {
    final batches = <List<String>>[];
    var current = <String>[];
    var characters = 0;
    for (final text in texts) {
      final contribution = text.length + 32;
      final wouldExceed =
          current.isNotEmpty &&
          (current.length >= _batchCueLimit ||
              characters + contribution > _batchCharacterLimit);
      if (wouldExceed) {
        batches.add(current);
        current = <String>[];
        characters = 0;
      }
      current.add(text);
      characters += contribution;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  Future<Map<String, _TranslatedLine>> _translateBatch(
    List<String> texts,
    String target, {
    required String? sourceIso,
  }) async {
    final translated = <String, _TranslatedLine>{};
    final pending = <String>[];
    for (final text in texts) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        translated[text] = _TranslatedLine(text, false);
        continue;
      }
      final key = '${sourceIso ?? 'auto'}\u0000$target\u0000$trimmed';
      final cached = _cache[key];
      if (cached != null) {
        translated[text] = _TranslatedLine(cached, true);
      } else {
        pending.add(text);
      }
    }

    if (pending.isEmpty) return translated;

    try {
      final joined = [
        for (var i = 0; i < pending.length; i++)
          '${batchMarker(i)}\n${pending[i].trim()}',
      ].join('\n');
      final uri = Uri.parse(
        '$_lingvaBaseUrl/api/v1/auto/$target/${Uri.encodeComponent(joined)}',
      );
      final response = await _dio.get<String>(uri.toString());
      final body = parseLingvaBody(response.data);
      final parts = body == null
          ? null
          : splitBatchTranslation(body, pending.length);
      if (parts != null) {
        for (var i = 0; i < pending.length; i++) {
          final text = pending[i];
          final trimmed = text.trim();
          final key = '${sourceIso ?? 'auto'}\u0000$target\u0000$trimmed';
          _cache[key] = parts[i];
          translated[text] = _TranslatedLine(parts[i], true);
        }
        return translated;
      }
    } catch (_) {
      // Fall back to individual requests below.
    }

    for (final text in pending) {
      translated[text] = await _translateLine(
        text,
        target,
        sourceIso: sourceIso,
      );
    }
    return translated;
  }

  Future<String> _readContent(String url) async {
    final uri = Uri.tryParse(url);
    if (uri?.scheme == 'file' ||
        ((uri?.scheme.isEmpty ?? true) && url.startsWith('/'))) {
      final file = uri?.scheme == 'file' ? File.fromUri(uri!) : File(url);
      return file.readAsString();
    }
    final response = await _dio.get<String>(url);
    final content = response.data;
    if (content == null || content.trim().isEmpty) {
      throw const FormatException('Subtitle response was empty');
    }
    return content;
  }

  Future<_TranslatedLine> _translateLine(
    String text,
    String target, {
    required String? sourceIso,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return _TranslatedLine(text, false);
    final key = '${sourceIso ?? 'auto'}\u0000$target\u0000$trimmed';
    final cached = _cache[key];
    if (cached != null) return _TranslatedLine(cached, true);

    final lingvaUri = Uri.parse(
      '$_lingvaBaseUrl/api/v1/auto/$target/${Uri.encodeComponent(trimmed)}',
    );
    try {
      final response = await _dio.get<String>(lingvaUri.toString());
      final translated = parseLingvaBody(response.data);
      if (translated != null) {
        _cache[key] = translated;
        return _TranslatedLine(translated, true);
      }
    } catch (_) {
      // Try the fallback service below.
    }

    final source = sourceIso;
    if (source == null || source.isEmpty || source == target) {
      return _TranslatedLine(text, false);
    }
    try {
      final uri = Uri.parse(
        _myMemoryBaseUrl,
      ).replace(queryParameters: {'q': trimmed, 'langpair': '$source|$target'});
      final response = await _dio.get<String>(uri.toString());
      final translated = parseMyMemoryBody(response.data);
      if (translated != null) {
        _cache[key] = translated;
        return _TranslatedLine(translated, true);
      }
    } catch (_) {
      // Preserve the original cue when both services fail.
    }
    return _TranslatedLine(text, false);
  }

  @visibleForTesting
  static String batchMarker(int index) => '[[FVCKSUBS_CUE_$index]]';

  @visibleForTesting
  static List<String>? splitBatchTranslation(String translation, int count) {
    final parts = <String>[];
    var cursor = 0;
    for (var i = 0; i < count; i++) {
      final marker = batchMarker(i);
      final markerIndex = translation.indexOf(marker, cursor);
      if (markerIndex < 0) return null;
      final start = markerIndex + marker.length;
      final nextMarker = i + 1 < count
          ? translation.indexOf(batchMarker(i + 1), start)
          : -1;
      final end = nextMarker < 0 ? translation.length : nextMarker;
      final part = translation.substring(start, end).trim();
      if (part.isEmpty) return null;
      parts.add(part);
      cursor = end;
    }
    return parts.length == count ? parts : null;
  }

  /// Extracts the translation from Lingva's REST response, or null for its
  /// `{ "error": "..." }` response and malformed payloads.
  @visibleForTesting
  static String? parseLingvaBody(String? body) {
    final raw = body?.trim();
    if (raw == null || raw.isEmpty || raw.startsWith('<')) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final translation = data['translation'];
      return translation is String && translation.isNotEmpty
          ? translation
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts the translation from MyMemory's public REST response.
  @visibleForTesting
  static String? parseMyMemoryBody(String? body) {
    final raw = body?.trim();
    if (raw == null || raw.isEmpty || raw.startsWith('<')) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['responseStatus'].toString() != '200') {
        return null;
      }
      final responseData = data['responseData'];
      if (responseData is! Map) return null;
      final translation = responseData['translatedText'];
      return translation is String && translation.isNotEmpty
          ? translation
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts translated segments from the legacy Google response shape.
  /// Kept for compatibility with existing parser coverage and fixtures.
  @visibleForTesting
  static String? parseTranslatedBody(String? body) {
    final raw = body?.trim();
    if (raw == null || raw.isEmpty || raw.startsWith('<')) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! List || data.isEmpty || data[0] is! List) return null;
      return (data[0] as List)
          .map(
            (segment) => segment is List && segment.isNotEmpty
                ? (segment[0]?.toString() ?? '')
                : '',
          )
          .join();
    } catch (_) {
      return null;
    }
  }

  static final RegExp _htmlTag = RegExp(r'<[^>]*>');
  static final RegExp _assTag = RegExp(r'\{[^}]*\}');
  static final RegExp _timestampPair = RegExp(
    r'(\d{1,2}:\d{2}:\d{2}[.,]\d{1,3}|\d{1,2}:\d{2}[.,]\d{1,3})\s*-->'
    r'\s*(\d{1,2}:\d{2}:\d{2}[.,]\d{1,3}|\d{1,2}:\d{2}[.,]\d{1,3})',
  );

  List<_Cue> _parse(String content) {
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final cues = <_Cue>[];
    var index = 0;
    while (index < lines.length) {
      final match = _timestampPair.firstMatch(lines[index]);
      if (match == null) {
        index++;
        continue;
      }
      final start = _normalizeTimestamp(match.group(1)!);
      final end = _normalizeTimestamp(match.group(2)!);
      index++;
      final text = <String>[];
      while (index < lines.length && lines[index].trim().isNotEmpty) {
        text.add(lines[index]);
        index++;
      }
      final clean = text
          .join('\n')
          .replaceAll(_assTag, '')
          .replaceAll(_htmlTag, '')
          .trim();
      if (clean.isNotEmpty) cues.add(_Cue(start, end, clean));
    }
    return cues;
  }

  String _normalizeTimestamp(String timestamp) {
    final value = timestamp.trim().replaceAll('.', ',');
    final parts = value.split(',');
    var hms = parts[0];
    var milliseconds = parts.length > 1 ? parts[1] : '000';
    if (hms.split(':').length == 2) hms = '00:$hms';
    milliseconds = milliseconds.padRight(3, '0').substring(0, 3);
    return '$hms,$milliseconds';
  }

  static String _languageCode(String value) {
    final primary = value.trim().toLowerCase().split(RegExp(r'[-_\s(]'))[0];
    return switch (primary) {
      'in' || 'ind' || 'indonesia' || 'indonesian' => 'id',
      'eng' || 'english' => 'en',
      _ => primary,
    };
  }
}

class _TranslatedLine {
  const _TranslatedLine(this.text, this.wasTranslated);

  final String text;
  final bool wasTranslated;
}

class _Cue {
  const _Cue(this.start, this.end, this.text);

  final String start;
  final String end;
  final String text;
}
