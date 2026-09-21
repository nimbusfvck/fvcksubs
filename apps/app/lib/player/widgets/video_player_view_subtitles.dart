part of 'video_player_view.dart';

Future<_DownloadedCaptionFile> _downloadCaptionFile(
  String url, {
  Map<String, String> headers = const {},
}) async {
  final uri = Uri.tryParse(url);
  if (uri?.scheme == 'file' ||
      (uri?.scheme.isEmpty ?? true) && url.startsWith('/')) {
    final bytes = await (uri?.scheme == 'file' ? File.fromUri(uri!) : File(url))
        .readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    final parsedCaptions = _parseCaptions(text);
    _logSubtitlePayload(text, parsedCaptions, null);
    return _DownloadedCaptionFile(
      captionFile: _CaptionFile(parsedCaptions),
      format: _captionContentFormat(text, null),
      contentType: null,
    );
  }
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException('Subtitle request failed: ${response.statusCode}');
    }
    final contentType = response.headers.contentType?.mimeType.toLowerCase();
    final text = await utf8.decoder.bind(response).join();
    final parsedCaptions = _parseCaptions(text);
    if (kDebugMode) {
      final lineEnding = text.contains('\r\n')
          ? 'crlf'
          : text.contains('\n')
          ? 'lf'
          : text.contains('\r')
          ? 'cr'
          : 'none';
      final timingMarkers = RegExp(r'-->').allMatches(text).length;
      final firstTimingLine = text
          .split(RegExp(r'\r?\n'))
          .where((line) => line.contains('-->'))
          .firstOrNull;
      _logSubtitlePayload(
        text,
        parsedCaptions,
        contentType,
        lineEnding: lineEnding,
        timingMarkers: timingMarkers,
        timingShape: _timingShape(firstTimingLine),
      );
    }
    return _DownloadedCaptionFile(
      captionFile: _CaptionFile(parsedCaptions),
      format: _captionContentFormat(text, contentType),
      contentType: contentType,
    );
  } finally {
    client.close(force: true);
  }
}

String _subtitleFormat(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final extension = path.lastIndexOf('.') < 0
      ? ''
      : path.substring(path.lastIndexOf('.') + 1).toLowerCase();
  return extension.isEmpty ? 'unknown' : extension;
}

class _CaptionFile extends vp.ClosedCaptionFile {
  _CaptionFile(this.captions);

  @override
  final List<vp.Caption> captions;
}

class _DownloadedCaptionFile {
  const _DownloadedCaptionFile({
    required this.captionFile,
    required this.format,
    required this.contentType,
  });

  final _CaptionFile captionFile;
  final String format;
  final String? contentType;
}

class _UnsupportedCaptionFormat implements Exception {
  const _UnsupportedCaptionFormat({
    required this.format,
    required this.contentType,
  });

  final String format;
  final String? contentType;
}

void _logSubtitlePayload(
  String text,
  List<vp.Caption> captions,
  String? contentType, {
  String? lineEnding,
  int? timingMarkers,
  String? timingShape,
}) {
  if (!kDebugMode) return;
  debugPrint(
    '[VideoPlayerVOD] subtitle_payload '
    'chars=${text.length} '
    'content_type=${contentType ?? 'local'} '
    'line_ending=${lineEnding ?? 'unknown'} '
    'timing_markers=${timingMarkers ?? RegExp(r'-->').allMatches(text).length} '
    'timing_shape=${timingShape ?? 'unknown'} '
    'parsed_cues=${captions.length}',
  );
}

List<vp.Caption> _parseCaptions(String raw) {
  final captions = <vp.Caption>[];
  var normalized = raw
      .replaceFirst('\ufeff', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  // Some plain-text subtitle endpoints return escaped newlines rather than
  // actual line breaks. Decode that transport detail before parsing cues.
  if (!normalized.contains('\n') && normalized.contains(r'\n')) {
    normalized = normalized
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\n', '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
  }
  final blocks = normalized.split(RegExp(r'\n\s*\n'));
  for (final block in blocks) {
    final lines = block.split('\n');
    final timingIndex = lines.indexWhere((line) => line.contains('-->'));
    if (timingIndex < 0 || timingIndex + 1 >= lines.length) continue;
    final times = lines[timingIndex].split('-->');
    if (times.length != 2) continue;
    final start = _captionTime(times[0]);
    final end = _captionTime(times[1].trim().split(RegExp(r'\s+')).first);
    final text = lines.sublist(timingIndex + 1).join('\n').trim();
    if (start == null || end == null || end <= start || text.isEmpty) continue;
    captions.add(
      vp.Caption(
        number: captions.length + 1,
        start: start,
        end: end,
        text: text,
      ),
    );
  }
  return captions.isNotEmpty ? captions : _parseAssCaptions(raw);
}

List<vp.Caption> _parseAssCaptions(String raw) {
  final captions = <vp.Caption>[];
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    if (!line.startsWith('Dialogue:')) continue;
    final fields = line.substring('Dialogue:'.length).split(',');
    if (fields.length < 10) continue;
    final start = _assCaptionTime(fields[1]);
    final end = _assCaptionTime(fields[2]);
    final text = fields
        .sublist(9)
        .join(',')
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\n', '\n')
        .trim();
    if (start == null || end == null || end <= start || text.isEmpty) continue;
    captions.add(
      vp.Caption(
        number: captions.length + 1,
        start: start,
        end: end,
        text: text,
      ),
    );
  }
  return captions;
}

String _captionContentFormat(String raw, String? contentType) {
  final content = raw.trimLeft();
  if (content.startsWith('WEBVTT')) return 'vtt';
  if (content.startsWith('#EXTM3U')) return 'hls-playlist';
  if (RegExp(
    r'^\[Script Info\]|^Dialogue:',
    multiLine: true,
  ).hasMatch(content)) {
    return 'ass';
  }
  if (RegExp(
    r'<(?:tt:)?tt\b|<tt:p\b',
    caseSensitive: false,
  ).hasMatch(content)) {
    return 'ttml';
  }
  if (contentType == 'application/x-subrip' ||
      contentType == 'application/srt' ||
      contentType == 'text/srt') {
    return 'srt';
  }
  if (content.contains('-->')) return 'timed-text';
  return contentType ?? 'unknown';
}

Duration? _captionTime(String raw) {
  final numeric = RegExp(r'^\s*(\d+(?:[.,]\d+)?)\s*$').firstMatch(raw);
  if (numeric != null) {
    final value = double.tryParse(numeric.group(1)!.replaceAll(',', '.'));
    if (value != null) {
      // Small values are conventionally seconds; large integer values are
      // conventionally milliseconds (both variants occur in plain text feeds).
      final milliseconds = value > 1000
          ? value.round()
          : (value * 1000).round();
      return Duration(milliseconds: milliseconds);
    }
  }
  final match = RegExp(
    r'(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})(?:[.,:](\d{1,3}))?',
  ).firstMatch(raw.trim());
  if (match == null) return null;
  final fraction = match.group(4) ?? '0';
  return Duration(
    hours: int.parse(match.group(1) ?? '0'),
    minutes: int.parse(match.group(2)!),
    seconds: int.parse(match.group(3)!),
    milliseconds: int.parse(fraction.padRight(3, '0').substring(0, 3)),
  );
}

String _timingShape(String? line) {
  if (line == null) return 'none';
  final shape = line.replaceAll(RegExp(r'[^0-9:.,>\-]'), '');
  return shape.isEmpty ? 'unrecognized' : shape;
}

Duration? _assCaptionTime(String raw) {
  final match = RegExp(
    r'^(\d+):(\d{1,2}):(\d{2})[.](\d{1,2})$',
  ).firstMatch(raw.trim());
  if (match == null) return null;
  final fraction = match.group(4)!;
  return Duration(
    hours: int.parse(match.group(1)!),
    minutes: int.parse(match.group(2)!),
    seconds: int.parse(match.group(3)!),
    milliseconds: int.parse(fraction.padRight(3, '0').substring(0, 3)),
  );
}
