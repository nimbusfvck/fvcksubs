import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'episode_target.dart';

const int _probeBatchSize = 5;

const int _maxProbes = 40;

Future<EpisodeTarget?> latestAvailableEpisodeTarget(
  ExtensionRegistry registry,
  MediaItem series,
  List<SeriesSeason> seasons, {
  int? lastAiredSeason,
  int? lastAiredEpisode,
}) async {
  final candidates = _candidatesNewestFirst(
    seasons,
    lastAiredSeason: lastAiredSeason,
    lastAiredEpisode: lastAiredEpisode,
  ).take(_maxProbes).toList();

  for (var start = 0; start < candidates.length; start += _probeBatchSize) {
    final batch = candidates.skip(start).take(_probeBatchSize).toList();
    final results = await Future.wait([
      for (final candidate in batch) _hasSources(registry, series, candidate),
    ]);
    for (var i = 0; i < batch.length; i++) {
      if (results[i]) return batch[i];
    }
  }
  return null;
}

Future<bool> _hasSources(
  ExtensionRegistry registry,
  MediaItem series,
  EpisodeTarget candidate,
) async {
  try {
    final sources = await registry.sources(candidate.itemFor(series));
    return sources.isNotEmpty;
  } catch (_) {
    return false;
  }
}

List<EpisodeTarget> _candidatesNewestFirst(
  List<SeriesSeason> seasons, {
  int? lastAiredSeason,
  int? lastAiredEpisode,
}) {
  final ordered = [
    for (final season in seasons)
      if (season.number >= 1 && season.episodes.isNotEmpty) season,
  ]..sort((a, b) => b.number.compareTo(a.number));

  return [
    for (final season in ordered)
      for (var i = season.episodes.length; i >= 1; i--)
        if (lastAiredSeason == null ||
            lastAiredEpisode == null ||
            season.number < lastAiredSeason ||
            (season.number == lastAiredSeason && i <= lastAiredEpisode))
          EpisodeTarget(
            season: season.number,
            episode: i,
            title: season.episodes[i - 1].title,
            resuming: false,
          ),
  ];
}
