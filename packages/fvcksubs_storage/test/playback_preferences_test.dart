import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('source priority defaults empty and round-trips provider ids', () async {
    const store = SharedPreferencesSourcePriorityStore();

    expect(await store.load(), isEmpty);
    await store.save(['nimora.cricfy', 'nimora.kora']);

    expect(await store.load(), ['nimora.cricfy', 'nimora.kora']);
  });

  test('external subtitle selections round-trip per media item', () async {
    final store = SharedPreferencesSubtitlePreferenceStore();
    const first = MediaRef(
      extensionId: 'ext',
      providerId: 'movies',
      id: 'first',
    );
    const second = MediaRef(
      extensionId: 'ext',
      providerId: 'movies',
      id: 'second',
    );
    const track = SubtitleTrack(
      language: 'id',
      label: 'Indonesia',
      url: 'https://subs.example/first.vtt',
    );
    const secondTrack = SubtitleTrack(
      language: 'en',
      label: 'English',
      url: 'https://subs.example/first-en.vtt',
    );

    await store.saveExternalSelection(first, track);

    final loaded = await store.loadExternalSelections();
    expect(loaded, hasLength(1));
    expect(loaded.values.single, track);

    await store.saveExternalTracks(first, [track, secondTrack]);
    final tracks = await store.loadExternalTracks();
    expect(tracks, hasLength(1));
    expect(tracks.values.single, [track, secondTrack]);

    await store.saveExternalSelection(second, track);
    await store.saveExternalSelection(first, null);
    expect(await store.loadExternalSelections(), hasLength(1));
  });

  test('subtitle appearance preferences round-trip', () async {
    final store = SharedPreferencesSubtitlePreferenceStore();
    const appearance = SubtitleAppearancePreferences(
      fontSize: 36,
      textColorValue: 0xffffeb3b,
      backgroundColorValue: 0xdd10243d,
      outline: true,
    );

    await store.saveAppearance(appearance);

    expect(await store.loadAppearance(), appearance);
  });

  test(
    'external subtitle track cache evicts the oldest media entries',
    () async {
      final store = SharedPreferencesSubtitlePreferenceStore();
      const track = SubtitleTrack(
        language: 'id',
        url: 'https://subs.example/id.vtt',
      );

      for (var index = 0; index <= 10; index++) {
        await store.saveExternalTracks(
          MediaRef(extensionId: 'ext', providerId: 'movies', id: 'item-$index'),
          const [track],
        );
      }

      final loaded = await store.loadExternalTracks();
    expect(loaded, hasLength(10));
      expect(loaded.keys.any((key) => key.endsWith('\u0000item-0')), isFalse);
    expect(loaded.keys.any((key) => key.endsWith('\u0000item-10')), isTrue);
    },
  );
}
