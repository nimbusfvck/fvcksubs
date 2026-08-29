import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../library/library_controller.dart';

/// Coordinates of a series' primary/resume episode within its guide.
typedef PrimaryEpisodeTarget = ({EpisodeGroup group, int index, bool resuming});

/// Resolves the episode a Play/Watch action should land on.
///
/// An in-progress resume episode wins first ([resumedEpisodeTarget]);
/// otherwise the guide's own declared default, if it's available; otherwise
/// the most recent available episode. `null` means nothing in [guide] is
/// playable yet. Shared by Detail and Shorts so both derive the same target
/// from the same episode guide and library state.
PrimaryEpisodeTarget? primaryEpisodeTarget(
  EpisodeGuide? guide,
  MediaRef parentRef,
  LibraryState library,
) {
  if (guide == null || guide.groups.isEmpty) return null;
  final resumed = resumedEpisodeTarget(guide, parentRef, library);
  if (resumed != null) return resumed;
  final target = guide.defaultEpisodeRef;
  if (target != null) {
    for (final group in guide.groups) {
      final index = group.episodes.indexWhere(
        (episode) => episode.ref == target,
      );
      if (index >= 0 && isEpisodeAvailable(group.episodes[index])) {
        return (group: group, index: index, resuming: false);
      }
    }
  }
  for (final group in guide.groups.reversed) {
    for (final entry in group.episodes.indexed.toList().reversed) {
      if (isEpisodeAvailable(entry.$2)) {
        return (group: group, index: entry.$1, resuming: false);
      }
    }
  }
  return null;
}

/// The most recently watched, still-in-progress episode of [parentRef]
/// that's still available in [guide], or `null` if nothing qualifies.
PrimaryEpisodeTarget? resumedEpisodeTarget(
  EpisodeGuide guide,
  MediaRef parentRef,
  LibraryState library,
) {
  final watchedEpisodes =
      library.records.values
          .where(
            (record) =>
                record.progress != null &&
                record.progress! > Duration.zero &&
                record.item is EpisodeItemV2 &&
                (record.item as EpisodeItemV2).episode.parentRef == parentRef,
          )
          .toList()
        ..sort(
          (a, b) => (b.lastWatched ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                a.lastWatched ?? DateTime.fromMillisecondsSinceEpoch(0),
              ),
        );
  for (final record in watchedEpisodes) {
    for (final group in guide.groups) {
      final index = group.episodes.indexWhere(
        (candidate) => candidate.ref == record.item.ref,
      );
      if (index >= 0 && isEpisodeAvailable(group.episodes[index])) {
        return (group: group, index: index, resuming: true);
      }
    }
  }
  return null;
}

/// Whether [episode] has actually released, not just been announced.
bool isEpisodeAvailable(EpisodeSummary episode) {
  final availableAt = episode.availableAt;
  return availableAt == null || !availableAt.isAfter(DateTime.now().toUtc());
}

/// Whether [guide] declares any episode at all.
bool hasEpisodes(EpisodeGuide? guide) =>
    guide?.groups.any((group) => group.episodes.isNotEmpty) ?? false;

/// The concrete item a Play/Watch action should send into full playback:
/// [target] converted to a real [EpisodeItemV2], or [detail]'s own item when
/// there's no episode guide at all. `null` means nothing is playable yet
/// (episodes exist but none are available).
MediaItemV2? primaryPlaybackTarget(
  MediaDetailV2 detail,
  PrimaryEpisodeTarget? target,
) {
  if (target == null) return hasEpisodes(detail.episodeGuide) ? null : detail.item;
  return episodeItemFrom(detail.item, target.group, target.index);
}

/// Builds the playable [EpisodeItemV2] for episode [index] of [group],
/// carrying [parent]'s artwork as a fallback and its title as the subtitle.
EpisodeItemV2 episodeItemFrom(MediaItemV2 parent, EpisodeGroup group, int index) {
  final episode = group.episodes[index];
  return EpisodeItemV2(
    ref: episode.ref,
    title: episode.title,
    subtitle: parent.title,
    artwork: episode.artwork ?? parent.artwork,
    episode: EpisodeIdentity(
      parentRef: parent.ref,
      groupId: group.id,
      position: episode.position,
    ),
    availableAt: episode.availableAt,
  );
}
