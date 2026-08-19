@TestOn('vm')
library;

import 'dart:convert';

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_js_runtime/fvcksubs_js_runtime.dart';
import 'package:test/test.dart';

/// The matcher (PLAN.md §12) as a host primitive.
///
/// The algorithm is the host's so every extension matches a fixture the same
/// way; the vertical knowledge is the extension's, passed as a
/// `NormalizationProfile`. These check both halves of that split — and that
/// the primitive agrees with the Dart resolver it wraps, which is the point
/// of sharing it at all.
void main() {
  late JsEngine engine;

  setUp(() {
    engine = JsEngine();
    HostApi.install(engine);
  });

  tearDown(() => engine.dispose());

  /// Football's own knowledge, the same shape `fvck` declares.
  const profile = {
    'aliases': {'man utd': 'manchester united'},
    'stopTokens': ['fc', 'afc'],
    'ambiguousAlone': ['united', 'city'],
  };

  Object? matchFrom(
    Map<String, Object?> query,
    List<Map<String, Object?>> candidates, {
    Object? options = const {},
  }) => jsonDecode(
    engine.eval(
      'host.match.resolve(${jsonEncode(query)}, ${jsonEncode(candidates)}, '
      '${jsonEncode(options)})',
    ),
  );

  test('the winner comes back as an index, not a payload', () {
    // An extension's payload is its own object; round-tripping it through
    // the host just to hand it straight back would be pointless.
    final result = matchFrom(
      {'teamA': 'Manchester United', 'teamB': 'Chelsea'},
      [
        {'teamA': 'Real Madrid', 'teamB': 'Barcelona'},
        {'teamA': 'Manchester United', 'teamB': 'Chelsea'},
      ],
    );

    expect(
      result,
      isA<Map<String, Object?>>().having((m) => m['index'], 'index', 1),
    );
    expect((result! as Map)['confidence'], greaterThan(0.86));
  });

  test('no match returns null rather than a bad guess', () {
    expect(
      matchFrom(
        {'teamA': 'Manchester United', 'teamB': 'Chelsea'},
        [
          {'teamA': 'Real Madrid', 'teamB': 'Barcelona'},
        ],
      ),
      isNull,
    );
  });

  test("the extension's profile is what resolves an alias", () {
    const query = {'teamA': 'Manchester United', 'teamB': 'Chelsea'};
    const candidates = [
      {'teamA': 'Man Utd', 'teamB': 'Chelsea FC'},
    ];

    // Without the profile the host has no idea "Man Utd" is the same club...
    expect(matchFrom(query, candidates), isNull);
    // ...with it, the same algorithm matches.
    expect(
      matchFrom(query, candidates, options: {'profile': profile}),
      isA<Map<String, Object?>>().having((m) => m['index'], 'index', 0),
    );
  });

  test('the time window is honoured, and configurable', () {
    const query = {
      'teamA': 'Manchester United',
      'teamB': 'Chelsea',
      'kickoff': '2026-08-16T14:00:00Z',
    };
    const farOff = [
      {
        'teamA': 'Manchester United',
        'teamB': 'Chelsea',
        'startsAt': '2026-08-16T18:00:00Z',
      },
    ];

    expect(matchFrom(query, farOff), isNull, reason: 'four hours apart');
    expect(
      matchFrom(query, farOff, options: {'timeWindowMinutes': 300}),
      isA<Map<String, Object?>>(),
      reason: 'a wider window admits it',
    );
  });

  test('the host primitive agrees with the Dart resolver', () {
    // Host and core matching must produce the same result.
    const query = MatchQuery(
      teamA: 'Manchester United',
      teamB: 'Chelsea',
      teamAShort: 'Man Utd',
    );
    const candidates = [
      EventCandidate<int>(teamA: 'Real Madrid', teamB: 'Barcelona', payload: 0),
      EventCandidate<int>(teamA: 'Man Utd', teamB: 'Chelsea FC', payload: 1),
    ];

    final fromDart = const EventMatchResolver(
      profile: NormalizationProfile(
        aliases: {'man utd': 'manchester united'},
        stopTokens: {'fc', 'afc'},
        ambiguousAlone: {'united', 'city'},
      ),
    ).resolve<int>(query: query, candidates: candidates);

    final fromJs =
        matchFrom(
              {
                'teamA': query.teamA,
                'teamB': query.teamB,
                'teamAShort': query.teamAShort,
              },
              [
                for (final c in candidates)
                  {'teamA': c.teamA, 'teamB': c.teamB},
              ],
              options: {'profile': profile},
            )!
            as Map<String, Object?>;

    expect(fromDart, isNotNull);
    expect(fromJs['index'], fromDart!.payload);
    expect(fromJs['confidence'], closeTo(fromDart.confidence, 1e-9));
  });

  test('an empty candidate list is not an error', () {
    expect(matchFrom({'teamA': 'A', 'teamB': 'B'}, const []), isNull);
  });

  test('a malformed query fails loudly rather than matching nothing', () {
    // Silently returning null would look identical to "no match", and hide
    // a bundle bug behind an empty sources list.
    expect(
      () => engine.eval('host.match.resolve({ teamA: "A" }, [], {})'),
      throwsA(isA<JsEvalException>()),
    );
  });
}
