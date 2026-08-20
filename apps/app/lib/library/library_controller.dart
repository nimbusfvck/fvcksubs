import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class LibraryState {
  LibraryState({Map<String, UserMediaState> records = const {}})
    : records = Map.unmodifiable(records);

  final Map<String, UserMediaState> records;

  UserMediaState? recordFor(MediaRef ref) =>
      records[UserMediaState.keyFor(ref)];

  bool isFavorite(MediaRef ref) => recordFor(ref)?.favorite ?? false;

  List<UserMediaState> get favorites =>
      records.values.where((record) => record.favorite).toList()
        ..sort((a, b) => a.item.title.compareTo(b.item.title));

  List<UserMediaState> get continueWatching =>
      records.values
          .where((record) => (record.progress ?? Duration.zero) > Duration.zero)
          .toList()
        ..sort(_mostRecentFirst);

  List<UserMediaState> get history =>
      records.values.where((record) => record.lastWatched != null).toList()
        ..sort(_mostRecentFirst);

  static int _mostRecentFirst(UserMediaState first, UserMediaState second) =>
      second.lastWatched!.compareTo(first.lastWatched!);
}

class LibraryController extends Cubit<LibraryState> {
  LibraryController({
    required this.store,
    Map<String, UserMediaState> initial = const {},
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(LibraryState(records: initial));

  final LibraryStore store;
  final DateTime Function() _now;

  UserMediaState? recordFor(MediaRef ref) => state.recordFor(ref);

  bool isFavorite(MediaRef ref) => state.isFavorite(ref);

  List<UserMediaState> get favorites => state.favorites;

  List<UserMediaState> get continueWatching => state.continueWatching;

  List<UserMediaState> get history => state.history;

  void toggleFavorite(MediaItemV2 item) {
    final existing = recordFor(item.ref);
    _upsert(
      (existing ?? UserMediaState(item: item)).copyWith(
        item: item,
        favorite: !(existing?.favorite ?? false),
      ),
    );
  }

  void recordWatched(
    MediaItemV2 item, {
    Object? progress = _unspecified,
    Object? duration = _unspecified,
  }) {
    final existing = recordFor(item.ref);
    final base = existing ?? UserMediaState(item: item);
    var next = base.copyWith(item: item, lastWatched: _now());
    if (!identical(progress, _unspecified)) {
      next = next.copyWith(progress: progress);
    }
    if (!identical(duration, _unspecified)) {
      next = next.copyWith(duration: duration);
    }
    _upsert(next);
  }

  static const Object _unspecified = Object();

  void _upsert(UserMediaState record) {
    final records = Map<String, UserMediaState>.of(state.records);
    if (!record.favorite && record.lastWatched == null) {
      records.remove(record.key);
    } else {
      records[record.key] = record;
    }
    emit(LibraryState(records: records));
    unawaited(store.save(records));
  }
}
