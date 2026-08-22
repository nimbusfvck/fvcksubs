import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

const supportedSubtitleLanguages =
    <(String code, String name, String description)>[
      ('id', 'Indonesia', 'Prefer Indonesian subtitles when available.'),
      ('en', 'English', 'Prefer English subtitles when available.'),
    ];

String subtitleLanguageKey(String value) {
  final normalized = value.trim().toLowerCase();
  final primary = normalized.split(RegExp('[-_]')).first;
  return switch (primary) {
    'indonesia' || 'indonesian' => 'id',
    'english' => 'en',
    _ => primary,
  };
}

bool isSupportedSubtitleTrack(SubtitleTrack track) =>
    supportedSubtitleLanguages.any(
      (language) =>
          subtitleLanguageKey(language.$1) ==
          subtitleLanguageKey(track.language),
    );

class SubtitlePreferenceController extends ChangeNotifier {
  SubtitlePreferenceController({required this.store, String? initial})
    : _languageCode = initial;

  final SubtitlePreferenceStore store;

  String? _languageCode;

  String? get languageCode => _languageCode;

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

  List<SubtitleTrack> tracksForPicker(List<SubtitleTrack> tracks) =>
      _languageCode == null
      ? tracks
      : tracks.where(isSupportedSubtitleTrack).toList();
}
