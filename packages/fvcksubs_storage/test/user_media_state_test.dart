import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

void main() {
  MediaItem item({String id = 'e1'}) => MediaItem(
    ref: MediaRef(extensionId: 'fvck', providerId: 'fvck.matches', id: id),
    kind: MediaKind.liveEvent,
    title: 'Home vs Away',
  );

  group('UserMediaState', () {
    test('round-trips a bare (never-watched, not favorited) record', () {
      final state = UserMediaState(ref: item().ref, item: item());
      final decoded = UserMediaState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>,
      );
      expect(decoded, state);
      expect(decoded.favorite, isFalse);
      expect(decoded.progress, isNull);
      expect(decoded.lastWatched, isNull);
    });

    test('round-trips a favorited, in-progress record', () {
      final state = UserMediaState(
        ref: item().ref,
        item: item(),
        favorite: true,
        progress: const Duration(minutes: 12, seconds: 34),
        lastWatched: DateTime.utc(2026, 8, 16, 15),
      );
      final decoded = UserMediaState.fromJson(
        jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>,
      );
      expect(decoded, state);
      expect(decoded.progress, const Duration(minutes: 12, seconds: 34));
      expect(decoded.lastWatched, DateTime.utc(2026, 8, 16, 15));
    });

    test('keyFor includes extension and provider, not just the opaque id', () {
      const refA = MediaRef(extensionId: 'a', providerId: 'a.p', id: 'x');
      const refB = MediaRef(extensionId: 'b', providerId: 'b.p', id: 'x');
      expect(UserMediaState.keyFor(refA), isNot(UserMediaState.keyFor(refB)));
    });

    group('copyWith', () {
      test('leaves fields untouched when not passed', () {
        final state = UserMediaState(
          ref: item().ref,
          item: item(),
          favorite: true,
        );
        final copy = state.copyWith(item: item(id: 'e2'));
        expect(copy.favorite, isTrue);
        expect(copy.item.ref.id, 'e2');
      });

      test('can explicitly clear progress/lastWatched back to null', () {
        final state = UserMediaState(
          ref: item().ref,
          item: item(),
          progress: const Duration(minutes: 5),
          lastWatched: DateTime.utc(2026, 8, 16),
        );
        final cleared = state.copyWith(progress: null, lastWatched: null);
        expect(cleared.progress, isNull);
        expect(cleared.lastWatched, isNull);
      });
    });
  });
}
