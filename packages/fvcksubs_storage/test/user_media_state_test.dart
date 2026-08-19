import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

void main() {
  const item = VideoItemV2(
    ref: MediaRef(
      extensionId: 'example',
      providerId: 'example.catalog',
      id: 'video-1',
    ),
    title: 'Video',
  );

  test('protocol-v2 record round-trips', () {
    final state = UserMediaState(
      item: item,
      favorite: true,
      progress: const Duration(seconds: 12),
      lastWatched: DateTime.utc(2026, 8, 19),
    );

    expect(UserMediaState.fromJson(state.toJson()), state);
  });

  test('copyWith can clear progress', () {
    const state = UserMediaState(item: item, progress: Duration(seconds: 12));

    expect(state.copyWith(progress: null).progress, isNull);
  });

  test('record key includes the complete reference', () {
    const other = MediaRef(
      extensionId: 'other',
      providerId: 'example.catalog',
      id: 'video-1',
    );

    expect(
      UserMediaState.keyFor(item.ref),
      isNot(UserMediaState.keyFor(other)),
    );
  });

  test('rejects legacy items', () {
    expect(
      () => UserMediaState.fromJson({
        'item': {'ref': item.ref.toJson(), 'kind': 'movie', 'title': 'Legacy'},
      }),
      throwsFormatException,
    );
  });

  test('rejects invalid state fields', () {
    expect(
      () => UserMediaState.fromJson({'item': item.toJson(), 'favorite': 'yes'}),
      throwsFormatException,
    );
  });
}
