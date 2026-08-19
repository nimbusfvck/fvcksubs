import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const ref = MediaRef(extensionId: 'fvck', providerId: 'fvck.p', id: 'e1');

  group('CachedSourceList', () {
    test('round-trips sources and fetchedAt', () {
      final cached = CachedSourceList(
        ref: ref,
        sources: const [
          StreamSource(id: 'a', label: 'Kora HD', provider: 'fvck.kora'),
          StreamSource(id: 'b', label: 'Cricfy SD'),
        ],
        fetchedAt: DateTime.utc(2026, 8, 16, 9),
      );
      final decoded = CachedSourceList.fromJson(
        jsonDecode(jsonEncode(cached.toJson())) as Map<String, Object?>,
      );
      expect(decoded, cached);
      expect(decoded.sources, hasLength(2));
      expect(decoded.sources.first.provider, 'fvck.kora');
      expect(decoded.fetchedAt, DateTime.utc(2026, 8, 16, 9));
    });

    test('keyFor includes extension and provider, not just the opaque id', () {
      const refA = MediaRef(extensionId: 'a', providerId: 'a.p', id: 'x');
      const refB = MediaRef(extensionId: 'b', providerId: 'b.p', id: 'x');
      expect(CachedSourceList.keyFor(refA), isNot(CachedSourceList.keyFor(refB)));
    });
  });

  group('SharedPreferencesSourceListStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('an empty store loads to an empty map', () async {
      final store = SharedPreferencesSourceListStore();
      expect(await store.load(), isEmpty);
    });

    test('save then load round-trips every entry', () async {
      final store = SharedPreferencesSourceListStore();
      final a = CachedSourceList(
        ref: ref,
        sources: const [StreamSource(id: 'a', label: 'HD')],
        fetchedAt: DateTime.utc(2026, 8, 16),
      );
      final b = CachedSourceList(
        ref: const MediaRef(extensionId: 'fvck', providerId: 'fvck.p', id: 'e2'),
        sources: const [StreamSource(id: 'b', label: 'SD')],
        fetchedAt: DateTime.utc(2026, 8, 17),
      );

      await store.save({a.key: a, b.key: b});
      final loaded = await store.load();

      expect(loaded, hasLength(2));
      expect(loaded[a.key], a);
      expect(loaded[b.key], b);
    });

    test('save replaces the previous full set, not merges into it', () async {
      final store = SharedPreferencesSourceListStore();
      final a = CachedSourceList(
        ref: ref,
        sources: const [StreamSource(id: 'a', label: 'HD')],
        fetchedAt: DateTime.utc(2026, 8, 16),
      );
      await store.save({a.key: a});
      await store.save({});

      expect(await store.load(), isEmpty);
    });
  });
}
