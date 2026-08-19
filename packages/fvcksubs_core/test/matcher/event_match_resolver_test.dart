import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

import 'support/football_profile.dart';

void main() {
  final resolver = EventMatchResolver(profile: footballProfile());
  final kickoff = DateTime.utc(2026, 8, 19, 19);

  MatchQuery query({bool withKickoff = true}) => MatchQuery(
    teamA: 'Manchester United',
    teamB: 'Chelsea',
    kickoff: withKickoff ? kickoff : null,
  );

  EventCandidate<String> candidate({
    String teamA = 'Manchester United',
    String teamB = 'Chelsea',
    DateTime? startsAt,
    String payload = 'event-1',
  }) => EventCandidate<String>(
    teamA: teamA,
    teamB: teamB,
    startsAt: startsAt ?? kickoff,
    payload: payload,
  );

  group('resolve — positive cases', () {
    test('matches identical team names within the time window', () {
      final result = resolver.resolve(
        query: query(),
        candidates: [candidate()],
      );

      expect(result, isNotNull);
      expect(result!.payload, 'event-1');
      expect(result.confidence, closeTo(1.0, 0.001));
    });

    test('still matches when the candidate lists teams in reverse order', () {
      final result = resolver.resolve(
        query: query(),
        candidates: [candidate(teamA: 'Chelsea', teamB: 'Manchester United')],
      );

      expect(result, isNotNull);
      expect(result!.confidence, closeTo(1.0, 0.001));
    });

    test('matches through a team alias', () {
      final result = resolver.resolve(
        query: query(),
        candidates: [candidate(teamA: 'Man Utd', teamB: 'Chelsea')],
      );

      expect(result, isNotNull);
    });

    test('picks the highest-scoring candidate', () {
      // "Manchester Utd" isn't an exact alias (only "man utd"/"man united"
      // are in the table), so its score is fuzzy and strictly < 1.0 — while
      // the second candidate is an exact match (1.0). Deterministic: the
      // exact spelling always wins, regardless of list order.
      final result = resolver.resolve(
        query: query(),
        candidates: [
          candidate(
            teamA: 'Manchester Utd',
            teamB: 'Chelsea',
            payload: 'fuzzy',
          ),
          candidate(
            teamA: 'Manchester United',
            teamB: 'Chelsea',
            payload: 'exact',
          ),
        ],
      );

      expect(result!.payload, 'exact');
      expect(result.confidence, closeTo(1.0, 0.001));
    });

    test('matches a broadcast name that drops the club suffix', () {
      // The reported miss: the catalog spells both clubs in full, the
      // broadcast source lists both by their short name. Neither pair is
      // close enough on characters alone — "end north preston" vs "preston"
      // scores 0.50.
      final result = resolver.resolve(
        query: const MatchQuery(
          teamA: 'Bolton Wanderers',
          teamB: 'Preston North End',
        ),
        candidates: [
          const EventCandidate<String>(
            teamA: 'Bolton',
            teamB: 'Preston',
            payload: 'bolton-preston',
          ),
        ],
      );

      expect(result, isNotNull);
      expect(result!.payload, 'bolton-preston');
    });

    test('a short name from the catalog scores alongside the full name', () {
      final result = resolver.resolve(
        query: const MatchQuery(
          teamA: 'Bolton Wanderers',
          teamB: 'Preston North End',
          teamAShort: 'Bolton',
          teamBShort: 'Preston',
        ),
        candidates: [
          const EventCandidate<String>(
            teamA: 'Bolton',
            teamB: 'Preston',
            payload: 'bolton-preston',
          ),
        ],
      );

      // Exact against the short name, so this beats the abbreviation score.
      expect(result, isNotNull);
      expect(result!.confidence, closeTo(1.0, 0.001));
    });

    test('a short name that helps nothing never lowers the score', () {
      final result = resolver.resolve(
        query: MatchQuery(
          teamA: 'Manchester United',
          teamB: 'Chelsea',
          // Garbage on one side; the full name still matches exactly.
          teamAShort: 'Utd',
          kickoff: kickoff,
        ),
        candidates: [candidate()],
      );

      expect(result, isNotNull);
      expect(result!.confidence, closeTo(1.0, 0.001));
    });

    test('an abbreviation never outranks the exact spelling', () {
      final result = resolver.resolve(
        query: const MatchQuery(teamA: 'Bolton Wanderers', teamB: 'Chelsea'),
        candidates: [
          candidate(teamA: 'Bolton', teamB: 'Chelsea', payload: 'short'),
          candidate(
            teamA: 'Bolton Wanderers',
            teamB: 'Chelsea',
            payload: 'exact',
          ),
        ],
      );

      expect(result!.payload, 'exact');
    });

    test('a missing kickoff or startsAt skips the time filter', () {
      final resultNullQuery = resolver.resolve(
        query: query(withKickoff: false),
        candidates: [
          candidate(startsAt: kickoff.add(const Duration(hours: 5))),
        ],
      );
      final resultNullCandidate = resolver.resolve(
        query: query(),
        candidates: [candidate(startsAt: null)],
      );

      expect(resultNullQuery, isNotNull);
      expect(resultNullCandidate, isNotNull);
    });
  });

  group('resolve — negative cases (must be null, not a weak guess)', () {
    test('rejects when both times exist but fall outside the window', () {
      final result = resolver.resolve(
        query: query(),
        candidates: [
          candidate(startsAt: kickoff.add(const Duration(hours: 3))),
        ],
      );

      expect(result, isNull);
    });

    test('rejects when only one team matches', () {
      final result = resolver.resolve(
        query: query(),
        candidates: [candidate(teamA: 'Manchester United', teamB: 'Everton')],
      );

      expect(result, isNull);
    });

    test('rejects when neither team is similar at all', () {
      final result = resolver.resolve(
        query: query(),
        candidates: [candidate(teamA: 'Real Madrid', teamB: 'Barcelona')],
      );

      expect(result, isNull);
    });

    test('rejects an empty candidate list', () {
      expect(resolver.resolve(query: query(), candidates: const []), isNull);
    });

    test('rejects a query with an empty team name', () {
      final result = resolver.resolve(
        query: const MatchQuery(teamA: '', teamB: 'Chelsea'),
        candidates: [candidate()],
      );

      expect(result, isNull);
    });

    test('does not mispair two different clubs from the same city', () {
      // Man City vs Chelsea is queried, the candidate is Man Utd vs Chelsea —
      // one team is a different club despite sharing a city, must reject.
      final result = resolver.resolve(
        query: const MatchQuery(teamA: 'Manchester City', teamB: 'Chelsea'),
        candidates: [candidate(teamA: 'Manchester United', teamB: 'Chelsea')],
      );

      expect(result, isNull);
    });

    test('rejects a bare, single-word generic name', () {
      // "United" is contained by Manchester, Newcastle and Leeds United
      // alike. Matching it on containment would be a coin flip between them.
      final result = resolver.resolve(
        query: query(),
        candidates: [candidate(teamA: 'United', teamB: 'Chelsea')],
      );

      expect(result, isNull);
    });

    test('does not mispair clubs that share an opening word', () {
      // {real, madrid} and {real, sociedad}: neither contains the other, so
      // containment must not fire here.
      final result = resolver.resolve(
        query: const MatchQuery(teamA: 'Real Madrid', teamB: 'Barcelona'),
        candidates: [candidate(teamA: 'Real Sociedad', teamB: 'Barcelona')],
      );

      expect(result, isNull);
    });
  });

  group('custom thresholds', () {
    test(
      'minTeamScore is honored: a threshold above the max always rejects',
      () {
        // Similarity is capped at 1.0 (a perfect match), so a threshold above
        // 1.0 must reject even an identical candidate — proving the parameter
        // is actually used, not ignored.
        final impossible = EventMatchResolver(
          profile: footballProfile(),
          minTeamScore: 1.01,
        );
        final q = query();
        final candidates = [candidate()];

        expect(impossible.resolve(query: q, candidates: candidates), isNull);
        expect(resolver.resolve(query: q, candidates: candidates), isNotNull);
      },
    );

    test('a narrower timeWindow rejects a candidate that used to pass', () {
      final narrow = EventMatchResolver(
        profile: footballProfile(),
        timeWindow: const Duration(minutes: 5),
      );
      final result = narrow.resolve(
        query: query(),
        candidates: [
          candidate(startsAt: kickoff.add(const Duration(minutes: 20))),
        ],
      );

      expect(result, isNull);
    });
  });
}
