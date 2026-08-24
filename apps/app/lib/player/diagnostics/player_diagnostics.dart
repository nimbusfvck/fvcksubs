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
/// playback failures. Match the active subtitle host so a source-open failure
/// is still surfaced when the player happens to have a subtitle selected.
bool isExternalSubtitleError(Object? error, {String? subtitleUrl}) {
  final host = Uri.tryParse(subtitleUrl ?? '')?.host.toLowerCase();
  if (host == null || host.isEmpty) return false;
  return (error?.toString() ?? '').toLowerCase().contains(host);
}

/// Whether a libmpv error line should tear playback down.
///
/// MediaKit's `Player.stream.error` forwards mpv log lines from several
/// subsystems, not only video playback. Only a line tied to the active video
/// is fatal before playback starts; subtitle, audio, unrelated, and post-start
/// lines stay out of the error view.
bool isFatalPlayerError(
  Object? error, {
  required bool playbackStarted,
  String? subtitleUrl,
  String? audioUrl,
  String? videoUrl,
}) {
  // A genuine open failure still arrives as a thrown error from `Player.open`,
  // which is reported regardless of this classification.
  if (isExternalSubtitleError(error, subtitleUrl: subtitleUrl) ||
      _errorMentionsUrl(error, audioUrl)) {
    return false;
  }
  final text = (error?.toString() ?? '').toLowerCase();
  if (text.contains('audio device')) return false;
  if (playbackStarted) return false;

  // MediaKit's error stream contains mpv log lines from several subsystems.
  // Only a line tied to the active video is allowed to reach the error view.
  return videoUrl == null || _errorMentionsUrl(error, videoUrl);
}

bool _errorMentionsUrl(Object? error, String? rawUrl) {
  final host = Uri.tryParse(rawUrl ?? '')?.host.toLowerCase();
  if (host == null || host.isEmpty) return false;
  return (error?.toString() ?? '').toLowerCase().contains(host);
}
