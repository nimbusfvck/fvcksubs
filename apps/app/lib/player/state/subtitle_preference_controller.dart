import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

const supportedSubtitleLanguages =
    <(String code, String name, String description)>[
      ('id', 'Indonesia', 'Prefer Indonesian subtitles when available.'),
      ('en', 'English', 'Prefer English subtitles when available.'),
    ];

/// Aliases the supported languages are known by upstream.
///
/// Providers pass the upstream's own language string through untouched, and
/// it arrives in every shape: MovieBox sends `lan` (`"in"`, the legacy ISO
/// 639-1 tag for Indonesian) or falls back to `lanName` (`"Indonesian"`),
/// VidEasy sends the display label (`"Indonesian - Forced"`), Shegu sends a
/// clean `"id"`. All of them have to key to the same language.
const _subtitleLanguageAliases = <String, String>{
  'in': 'id',
  'ind': 'id',
  'indonesia': 'id',
  'indonesian': 'id',
  'bahasa': 'id',
  'eng': 'en',
  'english': 'en',
};

/// Reduces a subtitle language string to a primary subtag (`"id"`, `"en"`).
///
/// Splits on the qualifier separators a label can carry — `pt-BR`,
/// `Indonesian SDH`, `English (Forced)` — so a track is keyed by its
/// language and not by the release detail appended to it.
String subtitleLanguageKey(String value) {
  final normalized = value.trim().toLowerCase();
  final whole = _subtitleLanguageAliases[normalized];
  if (whole != null) return whole;
  final primary = normalized.split(RegExp(r'[-_\s(]')).first;
  return _subtitleLanguageAliases[primary] ?? primary;
}

bool isSupportedSubtitleTrack(SubtitleTrack track) =>
    supportedSubtitleLanguages.any(
      (language) =>
          subtitleLanguageKey(language.$1) ==
          subtitleLanguageKey(track.language),
    );

class SubtitlePreferenceController extends ChangeNotifier {
  SubtitlePreferenceController({
    required this.store,
    String? initial,
    SubtitleAppearancePreferences? initialAppearance,
    Map<String, SubtitleTrack>? initialExternalSelections,
    Map<String, List<SubtitleTrack>>? initialExternalTracks,
  }) : _languageCode = initial,
       _appearance = SubtitleAppearance.fromStorage(initialAppearance),
       _externalSelections = {...?initialExternalSelections},
       _externalTracks = {...?initialExternalTracks};

  final SubtitlePreferenceStore store;

  String? _languageCode;
  SubtitleAppearance _appearance;
  final Map<String, SubtitleTrack> _externalSelections;
  final Map<String, List<SubtitleTrack>> _externalTracks;

  String? get languageCode => _languageCode;

  SubtitleAppearance get appearance => _appearance;

  void setAppearance(SubtitleAppearance appearance) {
    if (_appearance == appearance) return;
    _appearance = appearance;
    unawaited(store.saveAppearance(appearance.toStorage()));
    notifyListeners();
  }

  void resetAppearance() => setAppearance(const SubtitleAppearance());

  SubtitleTrack? rememberedExternalSubtitle(MediaRef ref) =>
      _externalSelections[_mediaKey(ref)];

  List<SubtitleTrack> rememberedExternalSubtitles(MediaRef ref) =>
      List.unmodifiable(_externalTracks[_mediaKey(ref)] ?? const []);

  void rememberExternalSubtitles(MediaRef ref, List<SubtitleTrack> tracks) {
    if (tracks.isEmpty) return;
    final key = _mediaKey(ref);
    final merged = _mergeTracks([...?_externalTracks[key], ...tracks]);
    _externalTracks[key] = merged;
    unawaited(store.saveExternalTracks(ref, merged));
    notifyListeners();
  }

  void restoreExternalTracks(Map<String, List<SubtitleTrack>> tracks) {
    if (tracks.isEmpty) return;
    for (final entry in tracks.entries) {
      _externalTracks[entry.key] = _mergeTracks([
        ...?_externalTracks[entry.key],
        ...entry.value,
      ]);
    }
    notifyListeners();
  }

  void rememberSubtitle(
    MediaRef ref, {
    required SubtitleTrack? track,
    required bool external,
  }) {
    final key = _mediaKey(ref);
    final next = external && track != null ? track : null;
    if (next == null) {
      if (_externalSelections.remove(key) == null) return;
    } else {
      if (_externalSelections[key] == next) return;
      _externalSelections[key] = next;
    }
    unawaited(store.saveExternalSelection(ref, next));
    notifyListeners();
  }

  void select(String? languageCode) {
    if (_languageCode == languageCode) return;
    _languageCode = languageCode;
    unawaited(store.save(languageCode));
    notifyListeners();
  }

  bool isSatisfiedBy(List<SubtitleTrack> tracks) {
    final wanted = _languageCode;
    if (wanted == null) return true;
    return tracks.any(
      (track) =>
          subtitleLanguageKey(track.language) == subtitleLanguageKey(wanted),
    );
  }

  /// The external track already looked up for [ref] in the preferred
  /// language, or `null` when none was found or no preference is set.
  SubtitleTrack? preferredExternalMatch(MediaRef ref) {
    final wanted = _languageCode;
    if (wanted == null) return null;
    final key = subtitleLanguageKey(wanted);
    for (final track in _externalTracks[_mediaKey(ref)] ?? const []) {
      if (subtitleLanguageKey(track.language) == key) return track;
    }
    return null;
  }

  List<SubtitleTrack> tracksForPicker(List<SubtitleTrack> tracks) =>
      _languageCode == null
      ? tracks
      : tracks.where(isSupportedSubtitleTrack).toList();

  static String _mediaKey(MediaRef ref) =>
      '${ref.extensionId}\u0000${ref.providerId}\u0000${ref.id}';

  static List<SubtitleTrack> _mergeTracks(List<SubtitleTrack> tracks) {
    final seen = <String>{};
    return [
      for (final track in tracks)
        if (seen.add(track.url)) track,
    ];
  }
}

class SubtitleAppearance {
  const SubtitleAppearance({
    this.fontSize = 24,
    this.textColor = Colors.white,
    this.backgroundColor = const Color(0xaa000000),
    this.outline = false,
  });

  factory SubtitleAppearance.fromStorage(
    SubtitleAppearancePreferences? value,
  ) => value == null
      ? const SubtitleAppearance()
      : SubtitleAppearance(
          fontSize: value.fontSize,
          textColor: Color(value.textColorValue),
          backgroundColor: Color(value.backgroundColorValue),
          outline: value.outline,
        );

  final double fontSize;
  final Color textColor;
  final Color backgroundColor;
  final bool outline;

  SubtitleAppearance copyWith({
    double? fontSize,
    Color? textColor,
    Color? backgroundColor,
    bool? outline,
  }) => SubtitleAppearance(
    fontSize: fontSize ?? this.fontSize,
    textColor: textColor ?? this.textColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    outline: outline ?? this.outline,
  );

  SubtitleAppearancePreferences toStorage() => SubtitleAppearancePreferences(
    fontSize: fontSize,
    textColorValue: textColor.toARGB32(),
    backgroundColorValue: backgroundColor.toARGB32(),
    outline: outline,
  );

  TextStyle get textStyle => TextStyle(
    height: 1.4,
    fontSize: fontSize,
    letterSpacing: 0,
    wordSpacing: 0,
    color: textColor,
    fontWeight: FontWeight.normal,
    backgroundColor: backgroundColor,
    shadows: outline
        ? const [
            Shadow(offset: Offset(1, 0), color: Colors.black),
            Shadow(offset: Offset(-1, 0), color: Colors.black),
            Shadow(offset: Offset(0, 1), color: Colors.black),
            Shadow(offset: Offset(0, -1), color: Colors.black),
          ]
        : null,
  );

  @override
  bool operator ==(Object other) =>
      other is SubtitleAppearance &&
      other.fontSize == fontSize &&
      other.textColor == textColor &&
      other.backgroundColor == backgroundColor &&
      other.outline == outline;

  @override
  int get hashCode =>
      Object.hash(fontSize, textColor, backgroundColor, outline);
}
