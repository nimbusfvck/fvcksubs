import 'package:flutter/widgets.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../app_scope.dart';
import '../library/library_controller.dart';
import '../player/workflow/play_item.dart';
import '../player/workflow/primary_episode_target.dart';

/// What the primary action on a Shorts card does and says.
enum ShortsActionKind { remindMe, watch, watchLive, details }

/// The primary action derived from an item's typed availability state.
class ShortsPrimaryAction {
  const ShortsPrimaryAction({required this.kind, required this.label});

  final ShortsActionKind kind;
  final String label;
}

/// Derives the availability-aware primary action for [item].
///
/// [detail] is only consulted for a [SeriesItemV2] — every other kind is
/// fully knowable from [item] and [library] alone. While [detail] is still
/// unresolved (the Cubit's prefetch hasn't finished), a series shows
/// [ShortsActionKind.details]: its playable state genuinely cannot be
/// determined without the episode guide.
ShortsPrimaryAction primaryActionFor(
  MediaItemV2 item, {
  required MediaDetailV2? detail,
  required LibraryState library,
}) {
  if (item.isUpcoming) {
    return const ShortsPrimaryAction(kind: ShortsActionKind.remindMe, label: 'Remind Me');
  }
  return switch (item) {
    EventItemV2() || ChannelItemV2() => const ShortsPrimaryAction(
      kind: ShortsActionKind.watchLive,
      label: 'Watch Live',
    ),
    VideoItemV2() || EpisodeItemV2() => _watchOrContinue(
      library.recordFor(item.ref)?.progress,
    ),
    SeriesItemV2() => _seriesAction(item, detail, library),
  };
}

ShortsPrimaryAction _seriesAction(
  SeriesItemV2 item,
  MediaDetailV2? detail,
  LibraryState library,
) {
  if (detail == null) {
    return const ShortsPrimaryAction(kind: ShortsActionKind.details, label: 'Details');
  }
  final target = primaryEpisodeTarget(detail.episodeGuide, item.ref, library);
  if (target == null && hasEpisodes(detail.episodeGuide)) {
    return const ShortsPrimaryAction(kind: ShortsActionKind.details, label: 'Details');
  }
  return ShortsPrimaryAction(
    kind: ShortsActionKind.watch,
    label: target?.resuming == true ? 'Continue' : 'Watch',
  );
}

ShortsPrimaryAction _watchOrContinue(Duration? progress) => ShortsPrimaryAction(
  kind: ShortsActionKind.watch,
  label: (progress ?? Duration.zero) > Duration.zero ? 'Continue' : 'Watch',
);

/// Sends [item] into the app's existing full-playback workflow.
///
/// Mirrors `open_versioned_item.dart`'s routing: everything except
/// [SeriesItemV2] goes straight to [playItemV2]. A series first needs its
/// episode guide — fetched here via [BuildContext] if [detail] wasn't
/// already prefetched — to resolve which episode Watch should land on. Throws
/// if nothing is playable yet; the caller (the Shorts page) is responsible
/// for turning that into the existing usable error and staying on Shorts,
/// never for treating a preview as a substitute for real playback.
Future<void> watchShortsItem(
  BuildContext context,
  MediaItemV2 item, {
  required MediaDetailV2? detail,
}) async {
  if (item is! SeriesItemV2) {
    await playItemV2(context, item);
    return;
  }
  final registry = AppScope.of(context).registry;
  final resolvedDetail = detail ?? await _fetchDetail(registry, item);
  final target = primaryEpisodeTarget(
    resolvedDetail.episodeGuide,
    item.ref,
    AppScope.of(context).libraryController.state,
  );
  final playable = primaryPlaybackTarget(resolvedDetail, target);
  if (playable == null) {
    throw StateError('No playable episode is available for "${item.title}" yet.');
  }
  if (!context.mounted) return;
  await playItemV2(context, playable, episodeGuide: resolvedDetail.episodeGuide);
}

Future<MediaDetailV2> _fetchDetail(
  ExtensionRegistry registry,
  MediaItemV2 item,
) async {
  try {
    return await registry.meta(item.ref);
  } catch (_) {
    // Catalogs may provide playable items without a separate metadata role —
    // mirrors DetailPageV2._loadDetail's same fallback.
    return MediaDetailV2(item: item);
  }
}
