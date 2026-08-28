import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/models/playback_media.dart';
import 'package:fvcksubs_app/player/state/subtitle_preference_controller.dart';
import 'package:fvcksubs_app/player/workflow/play_item.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'support/harness.dart';

void main() {
  const ref = MediaRef(
    extensionId: 'test',
    providerId: 'test.provider',
    id: 'movie-1',
  );
  const movie = PlaybackMedia(VideoItemV2(ref: ref, title: 'Movie'));
  const channel = PlaybackMedia(ChannelItemV2(ref: ref, title: 'Channel'));

  SubtitlePreferenceController controllerFor(String? language) =>
      SubtitlePreferenceController(
        store: FakeSubtitlePreferenceStore(),
        initial: language,
      );

  test('a VOD item with a language preference is looked up', () {
    expect(needsExternalSubtitleLookup(controllerFor('id'), movie), isTrue);
  });

  test('no preference and live streams are not looked up', () {
    expect(needsExternalSubtitleLookup(controllerFor(null), movie), isFalse);
    expect(needsExternalSubtitleLookup(controllerFor('id'), channel), isFalse);
  });

  test('a lookup that already found the language is not repeated', () {
    final preference = controllerFor('id');
    preference.rememberExternalSubtitles(ref, const [
      SubtitleTrack(language: 'id', url: 'https://shegu.example/id.srt'),
    ]);

    expect(needsExternalSubtitleLookup(preference, movie), isFalse);
  });

  test('a lookup that found only another language is retried', () {
    final preference = controllerFor('id');
    preference.rememberExternalSubtitles(ref, const [
      SubtitleTrack(language: 'en', url: 'https://shegu.example/en.srt'),
    ]);

    expect(needsExternalSubtitleLookup(preference, movie), isTrue);
  });
}
