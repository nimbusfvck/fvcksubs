import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/state/subtitle_preference_controller.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'support/harness.dart';

void main() {
  test(
    'remembers external subtitle per media and clears it for source picks',
    () async {
      final store = FakeSubtitlePreferenceStore();
      final controller = SubtitlePreferenceController(store: store);
      const first = MediaRef(
        extensionId: 'ext',
        providerId: 'movies',
        id: 'one',
      );
      const second = MediaRef(
        extensionId: 'ext',
        providerId: 'movies',
        id: 'two',
      );
      const track = SubtitleTrack(
        language: 'id',
        url: 'https://subs.example/one.vtt',
      );

      controller.rememberSubtitle(first, track: track, external: true);
      await Future<void>.delayed(Duration.zero);

      expect(controller.rememberedExternalSubtitle(first), track);
      expect(controller.rememberedExternalSubtitle(second), isNull);
      expect(store.externalSelections, hasLength(1));

      const secondTrack = SubtitleTrack(
        language: 'en',
        url: 'https://subs.example/one-en.vtt',
      );
      controller.rememberExternalSubtitles(first, [track, secondTrack]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.rememberedExternalSubtitles(first), [
        track,
        secondTrack,
      ]);
      expect(store.externalTracks, hasLength(1));

      controller.rememberSubtitle(first, track: track, external: false);
      expect(controller.rememberedExternalSubtitle(first), isNull);
    },
  );

  group('language key', () {
    test('folds the tags and labels upstreams use for one language', () {
      for (final value in const [
        'id',
        'ID',
        'id-ID',
        'in',
        'ind',
        'Indonesian',
        'Indonesia',
        'Indonesian SDH',
        'Bahasa Indonesia',
      ]) {
        expect(subtitleLanguageKey(value), 'id', reason: value);
      }
      for (final value in const [
        'en',
        'eng',
        'English',
        'English (Forced)',
        'en_US',
      ]) {
        expect(subtitleLanguageKey(value), 'en', reason: value);
      }
    });

    test('leaves an unrelated language on its own primary subtag', () {
      expect(subtitleLanguageKey('pt-BR'), 'pt');
      expect(subtitleLanguageKey('fr'), 'fr');
    });
  });

  test('a labelled track satisfies and survives the picker filter', () {
    final controller = SubtitlePreferenceController(
      store: FakeSubtitlePreferenceStore(),
      initial: 'id',
    );
    const tracks = [
      SubtitleTrack(language: 'Indonesian', url: 'https://subs.example/id.srt'),
      SubtitleTrack(language: 'pt-BR', url: 'https://subs.example/pt.srt'),
    ];

    expect(controller.isSatisfiedBy(tracks), isTrue);
    expect(controller.tracksForPicker(tracks), [tracks.first]);
  });

  test('the preferred external match is the one in the wanted language', () {
    const ref = MediaRef(extensionId: 'ext', providerId: 'movies', id: 'one');
    const english = SubtitleTrack(
      language: 'en',
      url: 'https://subs.example/en.srt',
    );
    const indonesian = SubtitleTrack(
      language: 'Indonesian',
      url: 'https://subs.example/id.srt',
    );
    final controller = SubtitlePreferenceController(
      store: FakeSubtitlePreferenceStore(),
      initial: 'id',
    );
    controller.rememberExternalSubtitles(ref, const [english, indonesian]);

    expect(controller.preferredExternalMatch(ref), indonesian);

    controller.select('fr');
    expect(controller.preferredExternalMatch(ref), isNull);
    controller.select(null);
    expect(controller.preferredExternalMatch(ref), isNull);
  });
}
