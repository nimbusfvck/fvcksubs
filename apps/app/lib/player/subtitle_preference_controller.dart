import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

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
      (track) => _primarySubtag(track.language) == _primarySubtag(wanted),
    );
  }

  static String _primarySubtag(String tag) {
    final cut = tag.indexOf(RegExp('[-_]'));
    return (cut < 0 ? tag : tag.substring(0, cut)).toLowerCase();
  }
}
