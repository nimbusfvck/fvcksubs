import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../state/subtitle_preference_controller.dart';

/// Returns subtitle tracks in a stable picker order without duplicate URLs.
List<SubtitleTrack> subtitlesForPicker(List<SubtitleTrack> tracks) {
  final sorted = tracks.toList()
    ..sort((a, b) {
      final primaryComparison = _primary(
        a.language,
      ).compareTo(_primary(b.language));
      if (primaryComparison != 0) return primaryComparison;
      final languageComparison = a.language.compareTo(b.language);
      if (languageComparison != 0) return languageComparison;
      return a.url.compareTo(b.url);
    });

  final seenUrls = <String>{};
  return [
    for (final track in sorted)
      if (seenUrls.add(track.url)) track,
  ];
}

/// Returns the human-readable label used in subtitle pickers.
String subtitleLanguageLabel(String languageCode) {
  final lang = languageCode.toLowerCase();
  final entry =
      _kLangMap[lang] ??
      _kLangMap[_primary(lang)] ??
      _kLangMap[subtitleLanguageKey(lang)];
  if (entry == null) return languageCode.toUpperCase();
  final (flag, name) = entry;
  final region = lang.contains('-')
      ? ' (${lang.split('-').last.toUpperCase()})'
      : '';
  return '$flag $name$region';
}

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

String _primary(String lang) {
  final dash = lang.indexOf('-');
  return dash == -1
      ? lang.toLowerCase()
      : lang.substring(0, dash).toLowerCase();
}

const _kLangMap = <String, (String, String)>{
  'af': ('🇿🇦', 'Afrikaans'),
  'ar': ('🇸🇦', 'العربية'),
  'bg': ('🇧🇬', 'Български'),
  'bn': ('🇧🇩', 'বাংলা'),
  'ca': ('🏴', 'Català'),
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
