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
}
