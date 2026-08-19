import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('CategorySelectionStore', () {
    test('load returns null before anything is saved', () async {
      expect(
        await const SharedPreferencesCategorySelectionStore('home').load(),
        isNull,
      );
    });

    test('save then load round-trips', () async {
      const store = SharedPreferencesCategorySelectionStore('home');
      await store.save('sport');
      expect(await store.load(), 'sport');
    });

    test('saving null clears it', () async {
      const store = SharedPreferencesCategorySelectionStore('home');
      await store.save('sport');
      await store.save(null);
      expect(await store.load(), isNull);
    });

    test('two scopes do not clobber each other', () async {
      await const SharedPreferencesCategorySelectionStore('home').save('live');
      await const SharedPreferencesCategorySelectionStore(
        'discover',
      ).save('sport');

      expect(
        await const SharedPreferencesCategorySelectionStore('home').load(),
        'live',
      );
      expect(
        await const SharedPreferencesCategorySelectionStore('discover').load(),
        'sport',
      );
    });
  });

  group('PluginSelectionStore', () {
    test('load returns null before anything is saved', () async {
      expect(
        await const SharedPreferencesPluginSelectionStore().load(),
        isNull,
      );
    });

    test('save then load round-trips', () async {
      const store = SharedPreferencesPluginSelectionStore();
      await store.save('example_extension');
      expect(await store.load(), 'example_extension');
    });

    test('saving null clears it', () async {
      const store = SharedPreferencesPluginSelectionStore();
      await store.save('example_extension');
      await store.save(null);
      expect(await store.load(), isNull);
    });

    test('it is global — a fresh instance sees the same choice', () async {
      await const SharedPreferencesPluginSelectionStore().save(
        'example_extension',
      );
      expect(
        await const SharedPreferencesPluginSelectionStore().load(),
        'example_extension',
      );
    });
  });
}
