import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

int defaultSeasonIndex(List<SeriesSeason> seasons, int? lastAiredSeason) {
  if (seasons.isEmpty) return 0;
  if (lastAiredSeason != null) {
    final matchIndex = seasons.indexWhere((s) => s.number == lastAiredSeason);
    if (matchIndex != -1) return matchIndex;
  }
  var latest = 0;
  for (var i = 1; i < seasons.length; i++) {
    if (seasons[i].number > seasons[latest].number) latest = i;
  }
  return latest;
}

bool isUnreleased(
  SeriesEpisode episode, {
  required int seasonNumber,
  required int episodeNum,
  int? lastAiredSeason,
  int? lastAiredEpisode,
  DateTime? now,
}) {
  final releaseDate = episode.releaseDate;
  if (releaseDate != null) return releaseDate.isAfter(now ?? DateTime.now());
  if (lastAiredSeason == null || lastAiredEpisode == null) return false;
  return seasonNumber > lastAiredSeason ||
      (seasonNumber == lastAiredSeason && episodeNum > lastAiredEpisode);
}

class EpisodeTarget {
  const EpisodeTarget({
    required this.season,
    required this.episode,
    required this.title,
    required this.resuming,
  });

  final int season;

  final int episode;

  final String title;

  final bool resuming;

  String get label => 'S${season}E$episode';

  MediaItem itemFor(MediaItem series) => MediaItem(
    ref: series.ref,
    kind: MediaKind.episode,
    title: '$title ($label)',
    poster: series.poster,
    thumbnail: series.thumbnail,
    extra: {
      ...series.extra,
      'season': season,
      'episode': episode,
      'seriesTitle': series.title,
    },
  );
}

EpisodeTarget? episodeTargetFor(
  List<SeriesSeason> seasons,
  LegacyUserMediaState? watched, {
  int? lastAiredSeason,
  int? lastAiredEpisode,
}) {
  final playable = [
    for (final season in seasons)
      if (season.episodes.isNotEmpty) season,
  ];
  if (playable.isEmpty) return null;

  final resumed = _resume(playable, watched);
  if (resumed != null) return resumed;

  if (lastAiredSeason != null && lastAiredEpisode != null) {
    final lastAired = _episodeAt(playable, lastAiredSeason, lastAiredEpisode);
    if (lastAired != null) return lastAired;
  }

  final latest = [...playable]
    ..sort((a, b) => b.number.compareTo(a.number));
  final season = latest.first;
  return EpisodeTarget(
    season: season.number,
    episode: season.episodes.length,
    title: season.episodes.last.title,
    resuming: false,
  );
}

EpisodeTarget? nextEpisodeTarget(
  List<SeriesSeason> seasons,
  int season,
  int episode,
) {
  for (final candidate in seasons) {
    if (candidate.number != season) continue;
    if (episode >= candidate.episodes.length) break;
    return EpisodeTarget(
      season: season,
      episode: episode + 1,
      title: candidate.episodes[episode].title,
      resuming: false,
    );
  }

  final laterSeasons = [
    for (final candidate in seasons)
      if (candidate.number > season && candidate.episodes.isNotEmpty) candidate,
  ]..sort((a, b) => a.number.compareTo(b.number));
  if (laterSeasons.isEmpty) return null;
  final next = laterSeasons.first;
  return EpisodeTarget(
    season: next.number,
    episode: 1,
    title: next.episodes.first.title,
    resuming: false,
  );
}

class NextEpisode {
  const NextEpisode({
    required this.item,
    required this.seriesTitle,
    required this.season,
    required this.episode,
    required this.episodeTitle,
  });

  final MediaItem item;
  final String seriesTitle;
  final int season;
  final int episode;
  final String episodeTitle;
}

NextEpisode? nextEpisodeOf(MediaItem current, List<SeriesSeason> seasons) {
  final extra = current.extra;
  final season = extra['season'];
  final episode = extra['episode'];
  if (season is! int || episode is! int) return null;

  final target = nextEpisodeTarget(seasons, season, episode);
  if (target == null) return null;

  final seriesTitle = extra['seriesTitle'];
  final seriesTitleString = seriesTitle is String ? seriesTitle : current.title;
  final item = target.itemFor(
    MediaItem(
      ref: current.ref,
      kind: MediaKind.series,
      title: seriesTitleString,
      poster: current.poster,
      thumbnail: current.thumbnail,
      extra: extra,
    ),
  );
  return NextEpisode(
    item: item,
    seriesTitle: seriesTitleString,
    season: target.season,
    episode: target.episode,
    episodeTitle: target.title,
  );
}

EpisodeTarget? _resume(
  List<SeriesSeason> seasons,
  LegacyUserMediaState? watched,
) {
  final extra = watched?.item.extra;
  final season = extra?['season'];
  final episode = extra?['episode'];
  if (season is! int || episode is! int) return null;
  final target = _episodeAt(seasons, season, episode);
  if (target == null) return null;
  return EpisodeTarget(
    season: target.season,
    episode: target.episode,
    title: target.title,
    resuming: true,
  );
}

EpisodeTarget? _episodeAt(List<SeriesSeason> seasons, int season, int episode) {
  for (final candidate in seasons) {
    if (candidate.number != season) continue;
    if (episode < 1 || episode > candidate.episodes.length) return null;
    return EpisodeTarget(
      season: season,
      episode: episode,
      title: candidate.episodes[episode - 1].title,
      resuming: false,
    );
  }
  return null;
}
