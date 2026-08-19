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
    final state = UserMediaStateV2(
      item: item,
      favorite: true,
      progress: const Duration(seconds: 12),
      lastWatched: DateTime.utc(2026, 8, 19),
    );

    expect(UserMediaStateV2.fromJson(state.toJson()), state);
  });

  test('copyWith can clear progress', () {
    const state = UserMediaStateV2(item: item, progress: Duration(seconds: 12));

    expect(state.copyWith(progress: null).progress, isNull);
  });

  test('record key includes the complete reference', () {
    const other = MediaRef(
      extensionId: 'other',
      providerId: 'example.catalog',
      id: 'video-1',
    );

    expect(
      UserMediaStateV2.keyFor(item.ref),
      isNot(UserMediaStateV2.keyFor(other)),
    );
  });

  test('rejects legacy items', () {
    expect(
      () => UserMediaStateV2.fromJson({
        'item': {'ref': item.ref.toJson(), 'kind': 'movie', 'title': 'Legacy'},
      }),
      throwsFormatException,
    );
  });

  test('rejects invalid state fields', () {
    expect(
      () => UserMediaStateV2.fromJson({
        'item': item.toJson(),
        'favorite': 'yes',
      }),
      throwsFormatException,
    );
  });
}
