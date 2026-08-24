String safePlaybackUrlForLog(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return '<invalid-url>';
  }

  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

String redactPlaybackLogText(Object? value) {
  final text = value?.toString() ?? '';
  return text.replaceAllMapped(RegExp(r'https?://[^\s\]\[<>{},]+'), (match) {
    final rawUrl = match.group(0)!;
    final trailing = rawUrl.endsWith('.') || rawUrl.endsWith(',')
        ? rawUrl.substring(rawUrl.length - 1)
        : '';
    final url = trailing.isEmpty
        ? rawUrl
        : rawUrl.substring(0, rawUrl.length - 1);
    return '${safePlaybackUrlForLog(url)}$trailing';
  });
}

/// Returns whether an mpv error belongs to the currently requested subtitle.
///
/// mpv reports a failed external subtitle fetch on the same error stream as
/// playback failures. Match the track URL, including its path, and require a
/// subtitle-shaped failure so a same-host video-open failure stays fatal.
bool isExternalSubtitleError(
  Object? error, {
  String? subtitleUrl,
  String? videoUrl,
}) {
  final text = (error?.toString() ?? '').toLowerCase();
  final subtitleMatches =
      _errorMentionsUrl(error, subtitleUrl, requirePath: true) ||
      (_differentHosts(subtitleUrl, videoUrl) &&
          _errorMentionsUrl(error, subtitleUrl));
  return subtitleMatches &&
      _hasAny(text, const [
        'subtitle',
        'caption',
        '.vtt',
        '.srt',
        '.ass',
        '.ssa',
        '.webvtt',
      ]);
}

/// Returns whether an mpv error belongs to the separate audio rendition.
///
/// Audio and video URLs commonly share a host. A host-only match is therefore
/// not enough to suppress a playback error; the error must identify the audio
/// URL path and look like an audio-track failure.
bool isExternalAudioError(Object? error, {String? audioUrl}) {
  final text = (error?.toString() ?? '').toLowerCase();
  return _errorMentionsUrl(error, audioUrl, requirePath: true) &&
      _hasAny(text, const [
        'audio',
        '.aac',
        '.m4a',
        '.mp3',
        '.opus',
        '.ac3',
        '.ec3',
      ]);
}

/// Whether a libmpv error line should tear playback down.
///
/// MediaKit's `Player.stream.error` forwards mpv log lines from several
/// subsystems, not only video playback. Known device warnings are non-fatal;
/// unknown errors before the first frame are fatal so codec, format, HTTP, and
/// source-open failures can trigger fallback or the error view.
bool isFatalPlayerError(
  Object? error, {
  required bool playbackStarted,
  String? subtitleUrl,
  String? audioUrl,
  String? videoUrl,
}) {
  if (isExternalSubtitleError(
        error,
        subtitleUrl: subtitleUrl,
        videoUrl: videoUrl,
      ) ||
      isExternalAudioError(error, audioUrl: audioUrl)) {
    return false;
  }
  final text = (error?.toString() ?? '').toLowerCase();
  if (_isKnownNonFatalWarning(text)) return false;
  if (playbackStarted) return false;

  // Before the first frame, an unknown error is a failed playback attempt.
  // This deliberately does not require the video URL: mpv often emits only
  // generic messages such as "failed to recognize file format".
  return true;
}

bool _isKnownNonFatalWarning(String text) =>
    _hasAny(text, const [
      'audio device',
      'no hardware device',
      'hardware device',
      'audio output',
    ]) &&
    !_hasAny(text, const [
      'could not open codec',
      'failed to recognize file format',
      'failed to open',
      'cannot open',
      'can not open',
    ]);

bool _hasAny(String text, List<String> needles) => needles.any(text.contains);

bool _errorMentionsUrl(
  Object? error,
  String? rawUrl, {
  bool requirePath = false,
}) {
  final uri = Uri.tryParse(rawUrl ?? '');
  final host = uri?.host.toLowerCase();
  if (host == null || host.isEmpty) return false;
  final text = (error?.toString() ?? '').toLowerCase();
  if (!text.contains(host)) return false;
  if (!requirePath) return true;
  final path = uri?.path.toLowerCase();
  return path != null && path.length > 1 && text.contains(path);
}

bool _differentHosts(String? firstUrl, String? secondUrl) {
  final first = Uri.tryParse(firstUrl ?? '')?.host.toLowerCase();
  final second = Uri.tryParse(secondUrl ?? '')?.host.toLowerCase();
  return first != null && first.isNotEmpty && first != second;
}
