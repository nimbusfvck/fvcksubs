import 'package:better_player_plus/better_player_plus.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../state/subtitle_preference_controller.dart';

BetterPlayerDataSource betterPlayerDataSource(
  PlayableStream stream, {
  required bool isLive,
  String? preferredSubtitleLanguage,
  bool preview = false,
}) => BetterPlayerDataSource(
  BetterPlayerDataSourceType.network,
  stream.url,
  headers: stream.headers,
  liveStream: isLive,
  videoFormat: _format(stream.format),
  drmConfiguration: _drm(stream),
  subtitles: isLive
      ? null
      : _subtitles(stream.subtitles, preferredSubtitleLanguage),
  // Keep signed and header-authenticated streams on the native network path.
  cacheConfiguration: const BetterPlayerCacheConfiguration(useCache: false),
  bufferingConfiguration: preview
      ? const BetterPlayerBufferingConfiguration(
          minBufferMs: 1500,
          maxBufferMs: 5000,
          bufferForPlaybackMs: 350,
          bufferForPlaybackAfterRebufferMs: 750,
        )
      : const BetterPlayerBufferingConfiguration(),
);

BetterPlayerVideoFormat _format(StreamFormat format) => switch (format) {
  StreamFormat.dash => BetterPlayerVideoFormat.dash,
  StreamFormat.hls => BetterPlayerVideoFormat.hls,
  StreamFormat.other => BetterPlayerVideoFormat.other,
};

List<BetterPlayerSubtitlesSource>? _subtitles(
  List<SubtitleTrack> tracks,
  String? preferredLanguage,
) {
  final sorted = subtitlesForPicker(tracks);
  if (sorted.isEmpty) return null;

  final preferred = preferredSubtitleSource(tracks, preferredLanguage);

  return [
    for (var i = 0; i < sorted.length; i++)
      subtitleSourceFor(
        sorted[i],
        selectedByDefault: preferred?.urls?.first == sorted[i].url,
      ),
  ];
}

/// Returns the matching stream-provided subtitle track, if the user has one.
BetterPlayerSubtitlesSource? preferredSubtitleSource(
  List<SubtitleTrack> tracks,
  String? preferredLanguage,
) {
  if (preferredLanguage == null) return null;
  for (final track in subtitlesForPicker(tracks)) {
    if (subtitleLanguageKey(track.language) ==
        subtitleLanguageKey(preferredLanguage)) {
      return subtitleSourceFor(track, selectedByDefault: true);
    }
  }
  return null;
}

BetterPlayerSubtitlesSource subtitleSourceFor(
  SubtitleTrack track, {
  bool selectedByDefault = false,
}) => BetterPlayerSubtitlesSource(
  type: BetterPlayerSubtitlesSourceType.network,
  name: _subtitleLabel(track),
  urls: [track.url],
  selectedByDefault: selectedByDefault,
);

List<SubtitleTrack> subtitlesForPicker(List<SubtitleTrack> tracks) {
  final filtered = tracks.toList();

  filtered.sort((a, b) {
    final pa = _primary(a.language);
    final pb = _primary(b.language);
    final c = pa.compareTo(pb);
    if (c != 0) return c;
    final d = a.language.compareTo(b.language);
    if (d != 0) return d;
    return a.url.compareTo(b.url);
  });

  final seenUrls = <String>{};
  return [
    for (final track in filtered)
      if (seenUrls.add(track.url)) track,
  ];
}

String _primary(String lang) {
  final dash = lang.indexOf('-');
  return dash == -1
      ? lang.toLowerCase()
      : lang.substring(0, dash).toLowerCase();
}

String _subtitleLabel(SubtitleTrack track) =>
    subtitleLanguageLabel(track.language);

/// Returns the compact label used for the active subtitle control.
String subtitleIndicatorLabel(String? sourceName) {
  final label = sourceName?.trim() ?? '';
  if (label.isEmpty) return 'CC';

  final firstToken = label.split(RegExp(r'\s+')).first;
  if (!RegExp(r'[a-zA-Z0-9]').hasMatch(firstToken)) return firstToken;

  final normalized = label.toLowerCase();
  final languageCode = normalized.split(RegExp(r'[\s(_-]')).first;
  final coded = _kLangMap[languageCode];
  if (coded != null) return coded.$1;

  if (normalized.startsWith('indonesian')) return _kLangMap['id']!.$1;
  for (final entry in _kLangMap.values) {
    final name = entry.$2.toLowerCase();
    if (normalized == name ||
        normalized.startsWith('$name ') ||
        normalized.startsWith('$name(')) {
      return entry.$1;
    }
  }
  return 'CC';
}

String subtitleLanguageLabel(String languageCode) {
  final lang = languageCode.toLowerCase();
  final entry = _kLangMap[lang] ?? _kLangMap[_primary(lang)];
  if (entry == null) return languageCode.toUpperCase();
  final (flag, name) = entry;
  final region = lang.contains('-')
      ? ' (${lang.split('-').last.toUpperCase()})'
      : '';
  return '$flag $name$region';
}

const _kLangMap = <String, (String, String)>{
  'af': ('🇿🇦', 'Afrikaans'),
  'ar': ('🇸🇦', 'العربية'),
  'bg': ('🇧🇬', 'Български'),
  'bn': ('🇧🇩', 'বাংলা'),
  'ca': ('🏴󠁥󠁳󠁣󠁴󠁿', 'Català'),
  'cs': ('🇨🇿', 'Čeština'),
  'da': ('🇩🇰', 'Dansk'),
  'de': ('🇩🇪', 'Deutsch'),
  'el': ('🇬🇷', 'Ελληνικά'),
  'en': ('🇬🇧', 'English'),
  'en-us': ('🇺🇸', 'English'),
  'en-gb': ('🇬🇧', 'English'),
  'es': ('🇪🇸', 'Español'),
  'es-419': ('🌎', 'Español'),
  'et': ('🇪🇪', 'Eesti'),
  'fa': ('🇮🇷', 'فارسی'),
  'fi': ('🇫🇮', 'Suomi'),
  'fr': ('🇫🇷', 'Français'),
  'fr-ca': ('🇨🇦', 'Français'),
  'he': ('🇮🇱', 'עברית'),
  'hi': ('🇮🇳', 'हिन्दी'),
  'hr': ('🇭🇷', 'Hrvatski'),
  'hu': ('🇭🇺', 'Magyar'),
  'id': ('🇮🇩', 'Indonesia'),
  'it': ('🇮🇹', 'Italiano'),
  'ja': ('🇯🇵', '日本語'),
  'ko': ('🇰🇷', '한국어'),
  'lt': ('🇱🇹', 'Lietuvių'),
  'lv': ('🇱🇻', 'Latviešu'),
  'ms': ('🇲🇾', 'Melayu'),
  'nl': ('🇳🇱', 'Nederlands'),
  'no': ('🇳🇴', 'Norsk'),
  'pl': ('🇵🇱', 'Polski'),
  'pt': ('🇵🇹', 'Português'),
  'pt-br': ('🇧🇷', 'Português'),
  'pt-pt': ('🇵🇹', 'Português'),
  'ro': ('🇷🇴', 'Română'),
  'ru': ('🇷🇺', 'Русский'),
  'sk': ('🇸🇰', 'Slovenčina'),
  'sl': ('🇸🇮', 'Slovenščina'),
  'sr': ('🇷🇸', 'Српски'),
  'sv': ('🇸🇪', 'Svenska'),
  'th': ('🇹🇭', 'ไทย'),
  'tr': ('🇹🇷', 'Türkçe'),
  'uk': ('🇺🇦', 'Українська'),
  'vi': ('🇻🇳', 'Tiếng Việt'),
  'zh': ('🇨🇳', '中文'),
  'zh-cn': ('🇨🇳', '中文'),
  'zh-tw': ('🇹🇼', '中文'),
  'zh-hk': ('🇭🇰', '中文'),
};

BetterPlayerDrmConfiguration? _drm(PlayableStream stream) {
  final drm = stream.drm;
  if (drm == null) return null;
  return switch (drm.scheme) {
    DrmScheme.clearKey => BetterPlayerDrmConfiguration(
      drmType: BetterPlayerDrmType.clearKey,
      clearKey: drm.clearKeyJson,
    ),
    DrmScheme.widevine => BetterPlayerDrmConfiguration(
      drmType: BetterPlayerDrmType.widevine,
      licenseUrl: drm.licenseUrl,
      headers: stream.headers,
    ),
    DrmScheme.unsupported => null,
  };
}
