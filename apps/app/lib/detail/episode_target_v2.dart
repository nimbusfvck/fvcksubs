import 'package:fvcksubs_core/fvcksubs_core.dart';

class NextEpisodeV2 {
  const NextEpisodeV2({
    required this.item,
    required this.seriesTitle,
    required this.groupTitle,
    required this.episode,
  });

  final EpisodeItemV2 item;
  final String seriesTitle;
  final String? groupTitle;
  final int episode;
}

String episodeSeriesTitle(EpisodeItemV2 item) => item.subtitle ?? item.title;

String episodeContextLabel({String? groupTitle, required int episode}) =>
    groupTitle == null ? 'Episode $episode' : '$groupTitle · Episode $episode';

/// The group name to put in front of an episode number, if any.
///
/// A series split into groups always needs one — the number alone does not say
/// which season. A lone group only earns one when its name says more than "the
/// episodes": an anime cour is a single group called "Episodes", and
/// "Episodes · Episode 1" is the same word twice, while "Season 2 · Episode 3"
/// still places the episode.
String? groupTitleFor(EpisodeGuide? guide, String groupId) {
  if (guide == null) return null;
  final title = guide.groups
      .where((group) => group.id == groupId)
      .map((group) => group.title)
      .firstOrNull;
  if (title == null || guide.groups.length > 1) return title;
  return RegExp(r'\d').hasMatch(title) ? title : null;
}

String currentEpisodeContextLabel(EpisodeItemV2 item, EpisodeGuide? guide) {
  final groupTitle = groupTitleFor(guide, item.episode.groupId);
  return episodeContextLabel(
    groupTitle: groupTitle,
    episode: item.episode.position,
  );
}

String nextEpisodeContextLabel(NextEpisodeV2 next) =>
    episodeContextLabel(groupTitle: next.groupTitle, episode: next.episode);

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
  for (
    var index = currentIndex + 1;
    index < currentGroup.episodes.length;
    index++
  ) {
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
      availableAt: episode.availableAt,
    ),
    seriesTitle: current.subtitle ?? current.title,
    groupTitle: groupTitleFor(guide, nextGroup.id),
    episode: episode.position,
  );
}
