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

class NextEpisodeV2 {
  const NextEpisodeV2({
    required this.item,
    required this.seriesTitle,
    required this.groupTitle,
    required this.episode,
  });

  final EpisodeItemV2 item;
  final String seriesTitle;
  final String groupTitle;
  final int episode;
}

NextEpisodeV2? nextEpisodeOfV2(
  EpisodeItemV2 current,
  EpisodeGuide guide, {
  DateTime? now,
}) {
  final identity = current.episode;
  final availableAt = now ?? DateTime.now().toUtc();

  bool available(EpisodeSummary episode) =>
      episode.availableAt == null || !episode.availableAt!.isAfter(availableAt);

  final currentGroupIndex = guide.groups.indexWhere(
    (group) => group.id == identity.groupId,
  );
  if (currentGroupIndex == -1) return null;

  EpisodeGroup? nextGroup;
  var nextIndex = -1;
  final currentGroup = guide.groups[currentGroupIndex];
  final currentIndex = currentGroup.episodes.indexWhere(
    (episode) => episode.ref == current.ref,
  );
  if (currentIndex == -1) return null;
  for (var index = currentIndex + 1; index < currentGroup.episodes.length; index++) {
    if (available(currentGroup.episodes[index])) {
      nextGroup = currentGroup;
      nextIndex = index;
      break;
    }
  }
  for (
    var groupIndex = currentGroupIndex + 1;
    nextGroup == null && groupIndex < guide.groups.length;
    groupIndex++
  ) {
    final group = guide.groups[groupIndex];
    final index = group.episodes.indexWhere(available);
    if (index >= 0) {
      nextGroup = group;
      nextIndex = index;
    }
  }

  if (nextGroup == null || nextIndex < 0) return null;
  final episode = nextGroup.episodes[nextIndex];
  return NextEpisodeV2(
    item: EpisodeItemV2(
      ref: episode.ref,
      title: episode.title,
      subtitle: current.subtitle,
      artwork: episode.artwork ?? current.artwork,
      episode: EpisodeIdentity(
        parentRef: identity.parentRef,
        groupId: nextGroup.id,
        position: episode.position,
      ),
    ),
    seriesTitle: current.subtitle ?? current.title,
    groupTitle: nextGroup.title,
    episode: episode.position,
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
