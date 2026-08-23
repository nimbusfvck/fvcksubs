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

/// Whether a libmpv error line should tear playback down.
///
/// MediaKit's `Player.stream.error` does not report "playback failed" — it
/// forwards mpv *log lines* whose level happens to be `error`, from the
/// `file`, `ffmpeg`, `vd`, `ad`, `cplayer`, and `stream` prefixes. mpv logs
/// those for transient conditions it recovers from on its own, so treating
/// every one as fatal replaces working video with a failure screen.
///
/// Two things make a line non-fatal:
///
/// * **Audio device failures cost sound, not playback.** mpv says
///   `Could not open/initialize audio device -> no sound.` and keeps
///   decoding video; the iOS Simulator produces this on every launch.
/// * **Frames already flowing prove the source works.** After playback has
///   started, a later error line is a warning about a hiccup, not a verdict
///   on the source. This mirrors the app's own rule that a failure before
///   playback initializes may fall through to the next source, while after
///   it starts nothing auto-advances and retry stays in the user's hands.
///
/// A genuine open failure still arrives as a thrown error from `Player.open`,
/// which is reported regardless of this classification.
bool isFatalPlayerError(Object? error, {required bool playbackStarted}) {
  final text = (error?.toString() ?? '').toLowerCase();
  if (text.contains('audio device')) return false;
  return !playbackStarted;
}
