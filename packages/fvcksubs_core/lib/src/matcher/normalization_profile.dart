import 'package:equatable/equatable.dart';

import '../json_util.dart';

/// The vertical-specific knowledge [TeamNameNormalizer] needs.
///
/// Ported from back-pass's `TeamNameNormalizer`, which hardcoded all three
/// tables for football. Here they're data, carried by whichever extension
/// declares a vertical — the matcher itself stays sport-agnostic (see
/// PLAN.md, Prinsip #3). Diacritic folding is universal and stays built into
/// the normalizer, not part of this profile.
class NormalizationProfile extends Equatable {
  /// Creates a profile.
  const NormalizationProfile({
    this.aliases = const {},
    this.stopTokens = const {},
    this.ambiguousAlone = const {},
  });

  /// No aliases, stop tokens, or ambiguous-alone words — every name is
  /// compared as given.
  static const NormalizationProfile empty = NormalizationProfile();

  /// Builds a [NormalizationProfile] from decoded JSON.
  factory NormalizationProfile.fromJson(Map<String, Object?> json) =>
      NormalizationProfile(
        aliases: (json['aliases'] as Map?)?.cast<String, String>() ?? const {},
        stopTokens: stringList(json['stopTokens']).toSet(),
        ambiguousAlone: stringList(json['ambiguousAlone']).toSet(),
      );

  /// Unambiguous shorthand → full name (e.g. `"man utd"` → `"manchester
  /// united"`). Only forms that name exactly one entity in the real world
  /// belong here — never a shorthand shared by several (that's what
  /// [ambiguousAlone] is for).
  final Map<String, String> aliases;

  /// Tokens that add no distinguishing information (e.g. `"fc"`, `"afc"`) and
  /// are dropped after normalizing.
  final Set<String> stopTokens;

  /// Single words that name no entity on their own (e.g. `"united"`,
  /// `"city"`) — containment matching is refused when the shorter name is
  /// just one of these, so it falls back to Jaccard instead of guessing.
  final Set<String> ambiguousAlone;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    if (aliases.isNotEmpty) 'aliases': aliases,
    if (stopTokens.isNotEmpty) 'stopTokens': stopTokens.toList(),
    if (ambiguousAlone.isNotEmpty) 'ambiguousAlone': ambiguousAlone.toList(),
  };

  @override
  List<Object?> get props => [aliases, stopTokens, ambiguousAlone];
}
