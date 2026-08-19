import 'normalization_profile.dart';

/// Normalizes a name so it can be compared across sources.
///
/// A catalog (e.g. "Manchester United") and a broadcast source (e.g. "Man
/// Utd", sometimes with noise like "Man Utd (Live)") rarely spell the same
/// name identically. This equalizes case, diacritics, uninformative corporate
/// suffixes, and unambiguous aliases — all from [profile], except diacritic
/// folding, which is universal.
///
/// Deliberately does **not** drop tokens like "united", "city", "real", or
/// "athletic" by default — those are exactly what distinguishes clubs in the
/// same city (Manchester United vs Manchester City, Real Madrid vs Real
/// Sociedad). A [profile] that dropped them would make the resolver pair the
/// wrong entities.
class TeamNameNormalizer {
  /// Creates a normalizer bound to [profile].
  const TeamNameNormalizer(this.profile);

  /// The vertical-specific tables this normalizer applies.
  final NormalizationProfile profile;

  static const Map<String, String> _diacritics = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
    'ý': 'y',
    'ß': 'ss',
  };

  /// Cleans then normalizes [name].
  ///
  /// The result is space-separated, alphabetically sorted words, so a
  /// different word order (rare, but cheap to tolerate) still compares equal.
  ///
  /// The sort is load-bearing beyond that — do not drop it: it also denies
  /// Jaro-Winkler its shared-prefix bonus for same-city rivals. Unsorted,
  /// "manchester city" against "manchester united" scores 0.96 and the
  /// resolver pairs the wrong club; sorted to "city manchester" the prefix
  /// disappears and the pair is correctly rejected. Abbreviated names, which
  /// the sort does hurt, are handled set-wise by the resolver instead.
  String normalize(String name) {
    var text = name.toLowerCase().trim();
    if (text.isEmpty) return '';

    _diacritics.forEach((from, to) {
      text = text.replaceAll(from, to);
    });

    // Common broadcast-feed noise: "(Live)", "[HD]", stray punctuation.
    text = text.replaceAll(RegExp(r'[\(\[][^)\]]*[\)\]]'), ' ');
    text = text.replaceAll(RegExp(r"[^a-z0-9\s']"), ' ');

    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final aliased = profile.aliases[collapsed] ?? collapsed;

    final tokens =
        aliased
            .split(' ')
            .where((t) => t.isNotEmpty && !profile.stopTokens.contains(t))
            .toList()
          ..sort();

    return tokens.join(' ');
  }
}
