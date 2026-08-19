import 'package:fvcksubs_core/fvcksubs_core.dart';

/// The football [NormalizationProfile] ported from back-pass's
/// `TeamNameNormalizer`, kept as a test fixture.
///
/// This exact table will move to `extensions/sport` once it exists (M3a) —
/// it's vertical-owned data, not something the matcher itself should know.
/// Kept here so the generic matcher can be tested against a realistic table
/// before that extension exists.
NormalizationProfile footballProfile() => const NormalizationProfile(
  aliases: {
    'man utd': 'manchester united',
    'man united': 'manchester united',
    'man city': 'manchester city',
    'spurs': 'tottenham hotspur',
    'psg': 'paris saint germain',
    'barca': 'barcelona',
    'inter': 'internazionale',
    'juve': 'juventus',
    'atleti': 'atletico madrid',
    'wolves': 'wolverhampton wanderers',
    'west brom': 'west bromwich albion',
    'west bromwich': 'west bromwich albion',
  },
  stopTokens: {'fc', 'afc', 'cf', 'sc', 'ac', 'cd', 'club'},
  ambiguousAlone: {
    'united',
    'city',
    'town',
    'rovers',
    'wanderers',
    'albion',
    'athletic',
    'county',
    'real',
    'atletico',
    'sporting',
    'dynamo',
    'racing',
    'olympique',
  },
);
