import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import '../models/app_player_controller.dart';

/// Maximum video heights offered by the app, in descending display order.
const preferredQualityHeights = <int>[2160, 1440, 1080, 720, 480, 360];

class QualityPreferenceController extends ChangeNotifier {
  QualityPreferenceController({required this.store, int? initial})
    : _maxHeight = normalizePreferredQuality(initial);

  final QualityPreferenceStore store;
  int? _maxHeight;

  /// The maximum height to select automatically, or `null` for Auto.
  int? get maxHeight => _maxHeight;

  void select(int? maxHeight) {
    final normalized = normalizePreferredQuality(maxHeight);
    if (_maxHeight == normalized) return;
    _maxHeight = normalized;
    unawaited(store.save(normalized));
    notifyListeners();
  }
}

int? normalizePreferredQuality(int? maxHeight) =>
    maxHeight == null || preferredQualityHeights.contains(maxHeight)
    ? maxHeight
    : null;

/// Picks the highest available rendition at or below the preference.
///
/// If a provider exposes no rendition under the cap, the lowest available
/// rendition is safer than silently allowing Auto to select a larger one.
AppQualityTrack? preferredQualityTrack({
  required List<AppQualityTrack> tracks,
  required int? maxHeight,
}) {
  if (maxHeight == null) return null;
  final usable = tracks.where((track) => track.height > 0).toList();
  if (usable.isEmpty) return null;
  usable.sort((a, b) {
    final height = b.height.compareTo(a.height);
    if (height != 0) return height;
    return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
  });
  for (final track in usable) {
    if (track.height <= maxHeight) return track;
  }
  return usable.last;
}
