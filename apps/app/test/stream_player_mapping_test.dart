import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/mappers/stream_player_mapping.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

void main() {
  group('subtitlesForPicker', () {
    test('keeps every language and sorts by language tag', () {
      final result = subtitlesForPicker(const [
        SubtitleTrack(language: 'fr', url: 'https://subs/fr.srt'),
        SubtitleTrack(language: 'id', url: 'https://subs/id.srt'),
        SubtitleTrack(language: 'en', url: 'https://subs/en.srt'),
      ]);
      expect(result.map((track) => track.language), ['en', 'fr', 'id']);
    });

    test('drops duplicate URLs while preserving the first track', () {
      final result = subtitlesForPicker(const [
        SubtitleTrack(
          language: 'id',
          url: 'https://subs/id.srt',
          label: 'Indonesian',
        ),
        SubtitleTrack(
          language: 'id',
          url: 'https://subs/id.srt',
          label: 'Bahasa Indonesia',
        ),
      ]);
      expect(result, hasLength(1));
      expect(result.single.label, 'Indonesian');
    });

    test('keeps multiple tracks for the same language', () {
      final result = subtitlesForPicker(const [
        SubtitleTrack(
          language: 'en',
          url: 'https://subs/en-1.srt',
          label: 'English',
        ),
        SubtitleTrack(
          language: 'en',
          url: 'https://subs/en-2.srt',
          label: 'English SDH',
        ),
      ]);
      expect(result, hasLength(2));
    });
  });

  group('subtitleLanguageLabel', () {
    test('known languages get flag and native name', () {
      expect(subtitleLanguageLabel('en'), '🇬🇧 English');
      expect(subtitleLanguageLabel('id'), '🇮🇩 Indonesia');
    });

    test('region-tagged codes get a disambiguator', () {
      expect(subtitleLanguageLabel('en-US'), '🇺🇸 English (US)');
    });

    test('unknown codes fall back to the raw code, upper-cased', () {
      expect(subtitleLanguageLabel('xx-yy'), 'XX-YY');
    });
  });

  group('subtitleIndicatorLabel', () {
    test('keeps a leading flag without the language name', () {
      expect(subtitleIndicatorLabel('🇮🇩 Indonesia'), '🇮🇩');
    });

    test('normalizes built-in language names to their flag', () {
      expect(subtitleIndicatorLabel('INDONESIA'), '🇮🇩');
      expect(subtitleIndicatorLabel('Indonesian SDH'), '🇮🇩');
    });

    test('falls back to CC when the source name is unknown', () {
      expect(subtitleIndicatorLabel('Custom captions'), 'CC');
    });
  });
}
