import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class LibraryStateV2 {
  LibraryStateV2({Map<String, UserMediaStateV2> records = const {}})
    : records = Map.unmodifiable(records);

  final Map<String, UserMediaStateV2> records;

  UserMediaStateV2? recordFor(MediaRef ref) =>
      records[UserMediaStateV2.keyFor(ref)];

  bool isFavorite(MediaRef ref) => recordFor(ref)?.favorite ?? false;

  List<UserMediaStateV2> get favorites =>
      records.values.where((record) => record.favorite).toList()
        ..sort((a, b) => a.item.title.compareTo(b.item.title));

  List<UserMediaStateV2> get continueWatching =>
      records.values
          .where((record) => (record.progress ?? Duration.zero) > Duration.zero)
          .toList()
        ..sort(_mostRecentFirst);

  List<UserMediaStateV2> get history =>
      records.values.where((record) => record.lastWatched != null).toList()
        ..sort(_mostRecentFirst);

  static int _mostRecentFirst(
    UserMediaStateV2 first,
    UserMediaStateV2 second,
  ) => second.lastWatched!.compareTo(first.lastWatched!);
}

class LibraryControllerV2 extends Cubit<LibraryStateV2> {
  LibraryControllerV2({
    required this.store,
    Map<String, UserMediaStateV2> initial = const {},
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(LibraryStateV2(records: initial));

  final LibraryStoreV2 store;
  final DateTime Function() _now;

  UserMediaStateV2? recordFor(MediaRef ref) => state.recordFor(ref);

  bool isFavorite(MediaRef ref) => state.isFavorite(ref);

  List<UserMediaStateV2> get favorites => state.favorites;

  List<UserMediaStateV2> get continueWatching => state.continueWatching;

  List<UserMediaStateV2> get history => state.history;

  void toggleFavorite(MediaItemV2 item) {
    final existing = recordFor(item.ref);
    _upsert(
      (existing ?? UserMediaStateV2(item: item)).copyWith(
        item: item,
        favorite: !(existing?.favorite ?? false),
      ),
    );
  }

  void recordWatched(MediaItemV2 item, {Object? progress = _unspecified}) {
    final existing = recordFor(item.ref);
    final base = existing ?? UserMediaStateV2(item: item);
    _upsert(
      identical(progress, _unspecified)
          ? base.copyWith(item: item, lastWatched: _now())
          : base.copyWith(
              item: item,
              progress: progress as Duration?,
              lastWatched: _now(),
            ),
    );
  }

  static const Object _unspecified = Object();

  void _upsert(UserMediaStateV2 record) {
    final records = Map<String, UserMediaStateV2>.of(state.records);
    if (!record.favorite && record.lastWatched == null) {
      records.remove(record.key);
    } else {
      records[record.key] = record;
    }
    emit(LibraryStateV2(records: records));
    unawaited(store.save(records));
  }
}
