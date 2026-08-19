import 'jaro_winkler.dart';
import 'normalization_profile.dart';
import 'team_name_normalizer.dart';

/// The contest being searched for — the catalog side.
///
/// Doesn't depend on any catalog entity type, so the resolver can be tested
/// without one.
class MatchQuery {
  /// Creates a query.
  const MatchQuery({
    required this.teamA,
    required this.teamB,
    this.teamAShort,
    this.teamBShort,
    this.kickoff,
  });

  /// Home side's name, as given by the catalog.
  final String teamA;

  /// Away side's name, as given by the catalog.
  final String teamB;

  /// The catalog's short name for [teamA] ("Bolton" for "Bolton Wanderers"),
  /// when it has one. Broadcast sources list clubs by their short name far
  /// more often than their full one, so this is usually the closer spelling.
  ///
  /// Scored as an alternative to [teamA], never a replacement: whichever of
  /// the two scores higher wins, so a useless short name costs nothing.
  final String? teamAShort;

  /// The catalog's short name for [teamB]. See [teamAShort].
  final String? teamBShort;

  /// Kickoff time in UTC. `null` when the catalog doesn't provide one — the
  /// resolver skips the time-window check for this query.
  final DateTime? kickoff;
}

/// One candidate from the broadcast side, generic over its own payload type so
/// the resolver never needs to know the source's shape.
class EventCandidate<T> {
  /// Creates a candidate.
  const EventCandidate({
    required this.teamA,
    required this.teamB,
    required this.payload,
    this.startsAt,
  });

  /// First team's name, as given by the broadcast source.
  ///
  /// Broadcast sources don't guarantee the same side order as the catalog, so
  /// the resolver tries both pairings.
  final String teamA;

  /// Second team's name, as given by the broadcast source.
  final String teamB;

  /// Start time in UTC, if the broadcast source provides one.
  final DateTime? startsAt;

  /// The source's own object (e.g. a channel), returned as-is when this
  /// candidate wins.
  final T payload;
}

/// The winning candidate plus its confidence score.
class MatchResult<T> {
  /// Creates a result.
  const MatchResult({required this.payload, required this.confidence});

  /// The matched candidate's payload.
  final T payload;

  /// Combined confidence, 0..1. Always >= the resolver's `minTeamScore`.
  final double confidence;

  @override
  String toString() =>
      'MatchResult(confidence: ${confidence.toStringAsFixed(3)}, payload: $payload)';
}

/// Matches one [MatchQuery] against a list of [EventCandidate]s.
///
/// Deliberately conservative: both team names must clear [minTeamScore], and
/// when both sides have a start time, they must fall within [timeWindow]. No
/// candidate clears the bar → `null`, never a weak best guess.
///
/// Stateless (aside from its bound [profile]), so it's safe to share.
class EventMatchResolver {
  /// Creates a resolver with the given [profile] and conservative defaults.
  const EventMatchResolver({
    required this.profile,
    this.timeWindow = const Duration(minutes: 45),
    this.minTeamScore = 0.86,
  });

  /// Vertical-specific normalization (aliases, stop tokens, ambiguous-alone
  /// words) this resolver applies.
  final NormalizationProfile profile;

  /// Max allowed difference between kickoff and a candidate's start time.
  final Duration timeWindow;

  /// Minimum similarity score for **each** team (not the average).
  final double minTeamScore;

  TeamNameNormalizer get _normalizer => TeamNameNormalizer(profile);

  /// Finds the best candidate for [query] among [candidates].
  ///
  /// Returns `null` when nothing clears both the time window and the team
  /// score threshold.
  MatchResult<T>? resolve<T>({
    required MatchQuery query,
    required List<EventCandidate<T>> candidates,
  }) {
    final namesA = _variants(query.teamA, query.teamAShort);
    final namesB = _variants(query.teamB, query.teamBShort);
    if (namesA.isEmpty || namesB.isEmpty) return null;

    MatchResult<T>? best;
    for (final candidate in candidates) {
      if (!_withinWindow(query.kickoff, candidate.startsAt)) continue;

      final score = _pairScore(namesA, namesB, candidate);
      if (score == null) continue;
      if (best == null || score > best.confidence) {
        best = MatchResult<T>(payload: candidate.payload, confidence: score);
      }
    }
    return best;
  }

  bool _withinWindow(DateTime? kickoff, DateTime? candidateStart) {
    if (kickoff == null || candidateStart == null) {
      // Can't be judged from time — leave it entirely to the team-name score,
      // which still has to clear minTeamScore.
      return true;
    }
    return kickoff.difference(candidateStart).abs() <= timeWindow;
  }

  /// Normalized spellings to try for one team, best-of wins.
  ///
  /// Empty entries and duplicates are dropped, so a feed that repeats the
  /// full name as the short name costs no extra work.
  List<String> _variants(String name, String? shortName) {
    final variants = <String>[];
    for (final raw in [name, shortName]) {
      if (raw == null) continue;
      final normalized = _normalizer.normalize(raw);
      if (normalized.isNotEmpty && !variants.contains(normalized)) {
        variants.add(normalized);
      }
    }
    return variants;
  }

  /// Best score across the two possible pairings, or `null` when neither
  /// pairing clears [minTeamScore] on **both** sides.
  double? _pairScore<T>(
    List<String> namesA,
    List<String> namesB,
    EventCandidate<T> candidate,
  ) {
    final candA = _normalizer.normalize(candidate.teamA);
    final candB = _normalizer.normalize(candidate.teamB);
    if (candA.isEmpty || candB.isEmpty) return null;

    final straight = _bothPass(
      _bestSimilarity(namesA, candA),
      _bestSimilarity(namesB, candB),
    );
    final swapped = _bothPass(
      _bestSimilarity(namesA, candB),
      _bestSimilarity(namesB, candA),
    );

    final best = straight > swapped ? straight : swapped;
    return best > 0 ? best : null;
  }

  /// Combined score only when **both** sides clear [minTeamScore]; otherwise
  /// 0 (one team matching and the other not is still a reject).
  double _bothPass(double scoreA, double scoreB) {
    if (scoreA < minTeamScore || scoreB < minTeamScore) return 0;
    return (scoreA + scoreB) / 2;
  }

  /// Best score across every spelling held for one team.
  double _bestSimilarity(List<String> variants, String candidate) {
    var best = 0.0;
    for (final variant in variants) {
      final score = _similarity(variant, candidate);
      if (score > best) best = score;
    }
    return best;
  }

  /// Jaro-Winkler on the characters, plus a token-overlap bonus — enough to
  /// tolerate a different word order without a third-party library.
  double _similarity(String a, String b) {
    if (a == b) return 1;
    final jaroWinkler = JaroWinkler.similarity(a, b);
    final tokens = _tokenScore(a, b);
    return jaroWinkler > tokens ? jaroWinkler : tokens;
  }

  /// Set-based score for two names, layered on top of the character-level one.
  ///
  /// The case that matters is *containment*: one name is the other with words
  /// dropped ("Preston" ⊂ "Preston North End", "Bolton" ⊂ "Bolton
  /// Wanderers") — exactly how broadcast sources abbreviate. Jaro-Winkler
  /// can't see it: names are normalized word-sorted, so "Preston North End"
  /// reads as "end north preston" and scores 0.50 against "Preston". Being
  /// set-based, containment is immune to that ordering.
  ///
  /// Falls back to Jaccard overlap, which only buys word-order tolerance.
  double _tokenScore(String a, String b) {
    final tokensA = a.split(' ').toSet();
    final tokensB = b.split(' ').toSet();
    if (tokensA.isEmpty || tokensB.isEmpty) return 0;

    final aIsShorter = tokensA.length <= tokensB.length;
    final shorter = aIsShorter ? tokensA : tokensB;
    final longer = aIsShorter ? tokensB : tokensA;

    if (longer.containsAll(shorter) && !_ambiguousAlone(shorter)) {
      // Deliberately capped below 1.0, and scaled by how much of the longer
      // name survives, so an exact spelling always outranks an abbreviation.
      return 0.9 + 0.1 * (shorter.length / longer.length);
    }

    final intersection = tokensA.intersection(tokensB).length;
    final union = tokensA.union(tokensB).length;
    return union == 0 ? 0 : intersection / union;
  }

  /// Whether [tokens] is a single word that names no entity on its own.
  ///
  /// "United" is contained by Manchester United, Newcastle United, and Leeds
  /// United alike, so treating containment as a strong match there would be a
  /// coin flip. A name this bare falls back to Jaccard and almost certainly
  /// fails the threshold — the honest outcome.
  bool _ambiguousAlone(Set<String> tokens) =>
      tokens.length == 1 && profile.ambiguousAlone.contains(tokens.first);
}
