import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.store,
    Map<String, UserMediaState> initial = const {},
  }) : _records = Map.of(initial);

  final LibraryStore store;

  final Map<String, UserMediaState> _records;

  bool isFavorite(MediaRef ref) =>
      _records[UserMediaState.keyFor(ref)]?.favorite ?? false;

  UserMediaState? recordFor(MediaRef ref) =>
      _records[UserMediaState.keyFor(ref)];

  void toggleFavorite(MediaItem item) {
    final existing = _records[UserMediaState.keyFor(item.ref)];
    _upsert(
      (existing ?? UserMediaState(ref: item.ref, item: item)).copyWith(
        item: item,
        favorite: !(existing?.favorite ?? false),
      ),
    );
  }

  void recordWatched(MediaItem item, {Object? progress = _unspecified}) {
    final existing = _records[UserMediaState.keyFor(item.ref)];
    final base = existing ?? UserMediaState(ref: item.ref, item: item);
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

  void _upsert(UserMediaState state) {
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

  List<UserMediaState> get favorites =>
      _records.values.where((s) => s.favorite).toList()
        ..sort((a, b) => a.item.title.compareTo(b.item.title));

  List<UserMediaState> get continueWatching =>
      _records.values
          .where((s) => (s.progress ?? Duration.zero) > Duration.zero)
          .toList()
        ..sort((a, b) => b.lastWatched!.compareTo(a.lastWatched!));

  List<UserMediaState> get history =>
      _records.values.where((s) => s.lastWatched != null).toList()
        ..sort((a, b) => b.lastWatched!.compareTo(a.lastWatched!));
}
