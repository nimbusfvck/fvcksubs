import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

import '../support/round_trip.dart';

void main() {
  test('round-trips the football-shaped profile from PLAN.md', () {
    const profile = NormalizationProfile(
      aliases: {'man utd': 'manchester united', 'spurs': 'tottenham hotspur'},
      stopTokens: {'fc', 'afc', 'cf', 'sc', 'ac', 'cd', 'club'},
      ambiguousAlone: {'united', 'city', 'town', 'rovers'},
    );

    expectRoundTrips(
      profile,
      toJson: (p) => p.toJson(),
      fromJson: NormalizationProfile.fromJson,
    );
  });

  test('an empty profile round-trips to itself', () {
    expectRoundTrips(
      NormalizationProfile.empty,
      toJson: (p) => p.toJson(),
      fromJson: NormalizationProfile.fromJson,
    );
  });
}
