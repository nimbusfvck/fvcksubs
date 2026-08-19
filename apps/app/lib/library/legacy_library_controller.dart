import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class LegacyLibraryController extends ChangeNotifier {
  LegacyLibraryController({
    required this.store,
    Map<String, LegacyUserMediaState> initial = const {},
  }) : _records = Map.of(initial);

  final LegacyLibraryStore store;

  final Map<String, LegacyUserMediaState> _records;

  bool isFavorite(MediaRef ref) =>
      _records[LegacyUserMediaState.keyFor(ref)]?.favorite ?? false;

  LegacyUserMediaState? recordFor(MediaRef ref) =>
      _records[LegacyUserMediaState.keyFor(ref)];

  void toggleFavorite(MediaItem item) {
    final existing = _records[LegacyUserMediaState.keyFor(item.ref)];
    _upsert(
      (existing ?? LegacyUserMediaState(ref: item.ref, item: item)).copyWith(
        item: item,
        favorite: !(existing?.favorite ?? false),
      ),
    );
  }

  void recordWatched(MediaItem item, {Object? progress = _unspecified}) {
    final existing = _records[LegacyUserMediaState.keyFor(item.ref)];
    final base = existing ?? LegacyUserMediaState(ref: item.ref, item: item);
    _upsert(
      identical(progress, _unspecified)
          ? base.copyWith(item: item, lastWatched: DateTime.now())
          : base.copyWith(
              item: item,
              progress: progress as Duration?,
              lastWatched: DateTime.now(),
            ),
    );
  }

  static const Object _unspecified = Object();

  void _upsert(LegacyUserMediaState state) {
    if (!state.favorite && state.lastWatched == null) {
      _records.remove(state.key);
    } else {
      _records[state.key] = state;
    }
    _persist();
    notifyListeners();
  }

  void _persist() {
    // Keep UI state responsive even if persistence fails.
    unawaited(store.save(Map.of(_records)));
  }

  List<LegacyUserMediaState> get favorites =>
      _records.values.where((s) => s.favorite).toList()
        ..sort((a, b) => a.item.title.compareTo(b.item.title));

  List<LegacyUserMediaState> get continueWatching =>
      _records.values
          .where((s) => (s.progress ?? Duration.zero) > Duration.zero)
          .toList()
        ..sort((a, b) => b.lastWatched!.compareTo(a.lastWatched!));

  List<LegacyUserMediaState> get history =>
      _records.values.where((s) => s.lastWatched != null).toList()
        ..sort((a, b) => b.lastWatched!.compareTo(a.lastWatched!));
}
