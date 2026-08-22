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
    ),
    seriesTitle: current.subtitle ?? current.title,
    groupTitle: nextGroup.title,
    episode: episode.position,
  );
}
