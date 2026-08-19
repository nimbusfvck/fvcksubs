import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

import 'support/football_profile.dart';

void main() {
  final normalizer = TeamNameNormalizer(footballProfile());

  group('TeamNameNormalizer.normalize', () {
    test('equalizes case and word order', () {
      expect(
        normalizer.normalize('Manchester United'),
        normalizer.normalize('manchester united'),
      );
    });

    test('an unambiguous alias matches the full name', () {
      expect(
        normalizer.normalize('Man Utd'),
        normalizer.normalize('Manchester United'),
      );
      expect(
        normalizer.normalize('Spurs'),
        normalizer.normalize('Tottenham Hotspur'),
      );
      expect(
        normalizer.normalize('PSG'),
        normalizer.normalize('Paris Saint Germain'),
      );
    });

    test('does not equate Man Utd with Man City', () {
      expect(
        normalizer.normalize('Man Utd'),
        isNot(normalizer.normalize('Man City')),
      );
    });

    test('drops pure corporate suffixes but not distinguishing tokens', () {
      expect(
        normalizer.normalize('Real Madrid CF'),
        normalizer.normalize('Real Madrid'),
      );
      // "United" and "City" stay — they distinguish the clubs.
      expect(
        normalizer.normalize('Manchester United'),
        isNot(normalizer.normalize('Manchester City')),
      );
      // "United" is not a corporate suffix — must not be dropped either.
      expect(normalizer.normalize('Manchester United'), isNot('manchester'));
    });

    test('folds diacritics', () {
      expect(
        normalizer.normalize('São Paulo'),
        normalizer.normalize('Sao Paulo'),
      );
      expect(
        normalizer.normalize('Atlético Madrid'),
        normalizer.normalize('Atletico Madrid'),
      );
    });

    test('drops bracketed noise from broadcast feeds', () {
      expect(
        normalizer.normalize('Man Utd (Live)'),
        normalizer.normalize('Man Utd'),
      );
      expect(
        normalizer.normalize('Arsenal [HD]'),
        normalizer.normalize('Arsenal'),
      );
    });

    test('an empty name normalizes to an empty string', () {
      expect(normalizer.normalize(''), isEmpty);
      expect(normalizer.normalize('   '), isEmpty);
    });

    test('an empty profile applies no aliases or stop tokens', () {
      final bare = TeamNameNormalizer(NormalizationProfile.empty);
      expect(bare.normalize('Real Madrid CF'), 'cf madrid real');
      expect(
        bare.normalize('Man Utd'),
        isNot(bare.normalize('Manchester United')),
      );
    });
  });
}
