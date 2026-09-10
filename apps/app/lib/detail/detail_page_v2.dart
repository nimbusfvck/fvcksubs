import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../catalog/artwork_placeholder.dart';
import '../catalog/media_card_actions.dart';
import '../catalog/media_card_v2.dart';
import '../catalog/media_hero.dart';
import '../library/library_controller.dart';
import '../player/models/playback_media.dart';
import '../player/widgets/trailer_preview.dart';
import '../player/workflow/play_item.dart';
import '../player/workflow/primary_episode_target.dart';
import '../theme/tokens.dart';
import '../utils/date_formatters.dart';
import '../widgets/centered_content.dart';
import '../widgets/clickable.dart';
import '../widgets/media_hero_layout.dart';
import '../widgets/media_hero_card.dart';
import '../widgets/media_hero_flexible_space.dart';
import '../widgets/media_hero_summary.dart';
import '../widgets/shimmer_placeholder.dart';
import 'open_versioned_item.dart';

class DetailPageV2 extends StatefulWidget {
  const DetailPageV2({
    super.key,
    required this.item,
    this.heroTag,
    this.contentRating = ContentRating.unknown,
  });

  final MediaItemV2 item;
  final Object? heroTag;
  final ContentRating contentRating;

  @override
  State<DetailPageV2> createState() => _DetailPageV2State();
}

class _DetailPageV2State extends State<DetailPageV2> {
  /// How many episodes one range chip covers. A long-running series is
  /// unscrollable in one list — One Piece is past 1175 — and every episode
  /// tile is built eagerly, so the chips bound the work as well as the scroll.
  static const int _episodesPerRange = 100;

  Future<MediaDetailV2>? _detail;
  String? _selectedGroupId;
  int? _selectedRangeIndex;
  bool _descriptionExpanded = false;
  bool _sourcePrefetchStarted = false;
  final ValueNotifier<double> _heroToolbarOpacity = ValueNotifier(0);

  @override
  void dispose() {
    _heroToolbarOpacity.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detail ??= _loadDetail();
  }

  Future<MediaDetailV2> _loadDetail() async {
    try {
      return await AppScope.of(context).registry.meta(widget.item.ref);
    } catch (_) {
      // Catalogs may provide playable items without a separate metadata role.
      // Keep the listing snapshot usable so the item's Play action still works.
      return MediaDetailV2(item: widget.item);
    }
  }

  String _playLabel(
    MediaDetailV2 detail,
    PrimaryEpisodeTarget? target,
    Duration? movieProgress,
  ) {
    if (target == null) {
      if (hasEpisodes(detail.episodeGuide)) return 'Coming soon';
      return (movieProgress ?? Duration.zero) > Duration.zero
          ? 'Continue Watching'
          : 'Watch Now';
    }
    final season = RegExp(
      r'\b(?:season|s)\s*([0-9]+)\b',
      caseSensitive: false,
    ).firstMatch(target.group.title)?.group(1);
    final position = target.group.episodes[target.index].position;
    // A group with no season in its title is still a numbered run — an anime
    // cour is one group called "Episodes". Dropping to a bare "Continue" threw
    // away the one thing the button should say: which episode.
    final label = season == null ? 'E$position' : 'S${season}E$position';
    return target.resuming ? 'Continue $label' : 'Watch $label';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.surfaceDark,
    body: FutureBuilder<MediaDetailV2>(
      future: _detail,
      builder: (context, snapshot) {
        final detail = snapshot.data ?? MediaDetailV2(item: widget.item);
        return _buildDetail(
          detail,
          metadataLoading: snapshot.connectionState != ConnectionState.done,
        );
      },
    ),
  );

  Widget _buildDetail(MediaDetailV2 detail, {required bool metadataLoading}) {
    if (!metadataLoading) _prefetchPrimarySources(detail);
    final item = detail.item;
    final trailers = detail.trailers
        .where((trailer) => !_isAutoplayTrailer(trailer))
        .toList(growable: false);
    final guide = detail.episodeGuide;
    final groups = guide?.groups ?? const <EpisodeGroup>[];
    final libraryController = AppScope.of(context).libraryController;
    final alignStart = MediaHeroLayout.isLargeScreen(context);

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onDetailScrollNotification,
          child: CustomScrollView(
            slivers: [
              _DetailHeroSliver(
                detail: detail,
                heroTag: widget.heroTag,
                actions: _heroActions(
                  detail: detail,
                  item: item,
                  guide: guide,
                  libraryController: libraryController,
                  alignStart: alignStart,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                sliver: SliverToBoxAdapter(
                  child: CenteredContent(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.isUpcoming && item.releaseDate != null) ...[
                          Text(
                            'Releases ${formatReleaseDate(item.releaseDate!.toLocal())}',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.onDarkSoft,
                            ),
                          ),
                        ],
                        if (metadataLoading || detail.description != null) ...[
                          SizedBox(
                            height: item.isUpcoming && item.releaseDate != null
                                ? AppSpacing.md
                                : AppSpacing.sm,
                          ),
                          if (metadataLoading)
                            const _DescriptionShimmer()
                          else
                            Text(
                              detail.description!,
                              maxLines: _descriptionExpanded ? null : 4,
                              overflow: _descriptionExpanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onDark,
                                height: 1.5,
                              ),
                            ),
                          if (!metadataLoading)
                            TextButton(
                              onPressed: () => setState(
                                () => _descriptionExpanded =
                                    !_descriptionExpanded,
                              ),
                              child: Text(
                                _descriptionExpanded
                                    ? 'Show less'
                                    : 'Show more',
                              ),
                            ),
                        ],
                        if (trailers.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          const _SectionTitle('Trailers'),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            height: 192,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: trailers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: AppSpacing.sm),
                              itemBuilder: (context, index) {
                                final trailer = trailers[index];
                                return _TrailerCard(
                                  trailer: trailer,
                                  onTap: () => _openTrailer(context, trailer),
                                );
                              },
                            ),
                          ),
                        ],
                        if (detail.facts.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          _Facts(values: detail.facts),
                        ],
                        if (detail.credits.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          const _SectionTitle('Credits'),
                          const SizedBox(height: AppSpacing.sm),
                          _Credits(values: detail.credits),
                        ],
                        _episodesSection(
                          detail: detail,
                          guide: guide,
                          groups: groups,
                          libraryController: libraryController,
                        ),
                        if (detail.collection case final collection?
                            when collection.items.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          _SectionTitle(collection.name),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            height: 228 + Clickable.ringBleed * 2,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: collection.items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: AppSpacing.sm),
                              itemBuilder: (context, index) {
                                final collectionItem = collection.items[index];
                                final heroTag = Object();
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: Clickable.ringBleed,
                                  ),
                                  child: SizedBox(
                                    width: 152,
                                    child: MediaCardV2(
                                      item: collectionItem,
                                      heroTag: heroTag,
                                      onTap: () => openVersionedItem(
                                        context,
                                        VersionedMediaItem(
                                          item: collectionItem,
                                        ),
                                        heroTag: heroTag,
                                        contentRating: widget.contentRating,
                                      ),
                                      onLongPress: () => showMediaCardActions(
                                        context,
                                        collectionItem,
                                        onViewDetails: () => openDetails(
                                          context,
                                          collectionItem,
                                          heroTag: heroTag,
                                          contentRating: widget.contentRating,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        if (detail.recommendations.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          const _SectionTitle('You Might Also Like'),
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            height: 228 + Clickable.ringBleed * 2,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: detail.recommendations.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: AppSpacing.sm),
                              itemBuilder: (context, index) {
                                final recommendation =
                                    detail.recommendations[index];
                                final heroTag = Object();
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: Clickable.ringBleed,
                                  ),
                                  child: SizedBox(
                                    width: 152,
                                    child: MediaCardV2(
                                      item: recommendation,
                                      heroTag: heroTag,
                                      onTap: () => openVersionedItem(
                                        context,
                                        VersionedMediaItem(
                                          item: recommendation,
                                        ),
                                        heroTag: heroTag,
                                        contentRating: widget.contentRating,
                                      ),
                                      onLongPress: () => showMediaCardActions(
                                        context,
                                        recommendation,
                                        onViewDetails: () => openDetails(
                                          context,
                                          recommendation,
                                          heroTag: heroTag,
                                          contentRating: widget.contentRating,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _DetailBackToolbar(
          opacity: _heroToolbarOpacity,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  bool _onDetailScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final heroHeight = MediaHeroLayout.heightForViewport(
      MediaQuery.sizeOf(context),
    );
    final fadeDistance = MediaHeroLayout.homeOverlayFadeDistance;
    final fadeStart = math.max(0.0, heroHeight - fadeDistance);
    _heroToolbarOpacity.value =
        ((notification.metrics.pixels - fadeStart) / fadeDistance)
            .clamp(0.0, 1.0)
            .toDouble();
    return false;
  }

  void _prefetchPrimarySources(MediaDetailV2 detail) {
    if (_sourcePrefetchStarted) return;
    _sourcePrefetchStarted = true;
    if (detail.item.isUpcoming) return;
    final scope = AppScope.of(context);
    final target = primaryEpisodeTarget(
      detail.episodeGuide,
      detail.item.ref,
      scope.libraryController.state,
    );
    final item = primaryPlaybackTarget(detail, target);
    if (item != null) {
      unawaited(prefetchPlaybackSources(scope, PlaybackMedia(item)));
    }
  }

  Widget _heroActions({
    required MediaDetailV2 detail,
    required MediaItemV2 item,
    required EpisodeGuide? guide,
    required LibraryController libraryController,
    required bool alignStart,
  }) => Wrap(
    alignment: alignStart ? WrapAlignment.start : WrapAlignment.center,
    spacing: AppSpacing.xs,
    runSpacing: AppSpacing.xs,
    children: [
      _primaryAction(
        detail: detail,
        item: item,
        guide: guide,
        libraryController: libraryController,
      ),
      _FavoriteAction(item: item),
    ],
  );

  Widget _primaryAction({
    required MediaDetailV2 detail,
    required MediaItemV2 item,
    required EpisodeGuide? guide,
    required LibraryController libraryController,
  }) => BlocBuilder<LibraryController, LibraryState>(
    bloc: libraryController,
    builder: (context, state) {
      if (item.isUpcoming) {
        return _RemindMeButton(
          active: state.isReminded(item.ref),
          onPressed: () => libraryController.toggleReminder(item),
        );
      }
      final target = primaryEpisodeTarget(
        detail.episodeGuide,
        detail.item.ref,
        state,
      );
      final primaryTarget = primaryPlaybackTarget(detail, target);
      return _PrimaryPlayButton(
        onPressed: primaryTarget == null
            ? null
            : () => playItemV2(
                context,
                primaryTarget,
                episodeGuide: guide,
                contentRating: widget.contentRating,
                returnToDetail: true,
              ),
        label: _playLabel(detail, target, state.recordFor(item.ref)?.progress),
      );
    },
  );

  Widget _episodesSection({
    required MediaDetailV2 detail,
    required EpisodeGuide? guide,
    required List<EpisodeGroup> groups,
    required LibraryController libraryController,
  }) => BlocBuilder<LibraryController, LibraryState>(
    bloc: libraryController,
    builder: (context, state) {
      final selectedGroup = _selectedGroup(detail, groups, state);
      if (selectedGroup == null) return const SizedBox.shrink();
      final rangeCount = (selectedGroup.episodes.length / _episodesPerRange)
          .ceil();
      final rangeIndex = _rangeIndexFor(
        detail,
        selectedGroup,
        state,
        rangeCount,
      );
      final rangeStart = rangeIndex * _episodesPerRange;
      final rangeEnd = math.min(
        rangeStart + _episodesPerRange,
        selectedGroup.episodes.length,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              const Expanded(child: _SectionTitle('Episodes')),
              if (groups.length > 1)
                Flexible(
                  child: DropdownButton<String>(
                    value: selectedGroup.id,
                    isExpanded: true,
                    dropdownColor: AppColors.surfaceDarkElevated,
                    items: [
                      for (final group in groups)
                        DropdownMenuItem(
                          value: group.id,
                          child: Text(
                            group.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _selectedGroupId = value;
                      // Another season's ranges are its own; keeping the index
                      // would land on an arbitrary hundred of it.
                      _selectedRangeIndex = null;
                    }),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (rangeCount > 1) ...[
            _EpisodeRangeChips(
              labels: [
                for (var index = 0; index < rangeCount; index++)
                  _rangeLabel(selectedGroup.episodes, index),
              ],
              selected: rangeIndex,
              onSelected: (index) =>
                  setState(() => _selectedRangeIndex = index),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final entry
              in selectedGroup.episodes
                  .sublist(rangeStart, rangeEnd)
                  .indexed
                  .map((entry) => (entry.$1 + rangeStart, entry.$2)))
            _EpisodeTile(
              episode: entry.$2,
              progress: _progressFraction(state.recordFor(entry.$2.ref)),
              onTap: () => playItemV2(
                context,
                episodeItemFrom(detail.item, selectedGroup, entry.$1),
                episodeGuide: guide,
                contentRating: widget.contentRating,
                returnToDetail: true,
              ),
            ),
        ],
      );
    },
  );

  EpisodeGroup? _selectedGroup(
    MediaDetailV2 detail,
    List<EpisodeGroup> groups,
    LibraryState library,
  ) {
    if (groups.isEmpty) return null;
    final selectedId = _selectedGroupId;
    if (selectedId != null) {
      for (final group in groups) {
        if (group.id == selectedId) return group;
      }
    }
    final resumed = detail.episodeGuide == null
        ? null
        : resumedEpisodeTarget(detail.episodeGuide!, detail.item.ref, library);
    return resumed?.group ?? groups.last;
  }

  /// The range the list opens on: the one holding whatever Play would start,
  /// so resuming episode 900 does not begin with a scroll from episode 1.
  int _rangeIndexFor(
    MediaDetailV2 detail,
    EpisodeGroup group,
    LibraryState library,
    int rangeCount,
  ) {
    final selected = _selectedRangeIndex;
    if (selected != null && selected < rangeCount) return selected;
    final target = primaryEpisodeTarget(
      detail.episodeGuide,
      detail.item.ref,
      library,
    );
    if (target == null || target.group.id != group.id) return 0;
    return (target.index ~/ _episodesPerRange).clamp(0, rangeCount - 1);
  }

  String _rangeLabel(List<EpisodeSummary> episodes, int index) {
    final start = index * _episodesPerRange;
    final end = math.min(start + _episodesPerRange, episodes.length) - 1;
    // Positions, not indices: a group need not start numbering at one.
    return '${episodes[start].position}–${episodes[end].position}';
  }

  Future<void> _openTrailer(BuildContext context, MediaTrailer trailer) async {
    final uri = Uri.tryParse(trailer.url);
    var opened =
        uri != null && await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!opened && uri != null) {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open trailer.')));
    }
  }

  double? _progressFraction(UserMediaState? record) {
    final progress = record?.progress;
    final duration = record?.duration;
    if (progress == null || duration == null || duration <= Duration.zero) {
      return null;
    }
    return (progress.inMilliseconds / duration.inMilliseconds)
        .clamp(0, 1)
        .toDouble();
  }
}

class _PrimaryPlayButton extends StatelessWidget {
  const _PrimaryPlayButton({required this.onPressed, required this.label});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.play_arrow_rounded, size: 28),
    label: Text(label),
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
    ),
  );
}

class _RemindMeButton extends StatelessWidget {
  const _RemindMeButton({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(
      active
          ? Icons.notifications_active_rounded
          : Icons.notifications_none_rounded,
      size: 24,
    ),
    label: Text(active ? 'Reminder Set' : 'Remind Me'),
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.actions, this.heroTag});

  final MediaDetailV2 detail;
  final Widget actions;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    final image = item.artwork?.portrait ?? item.artwork?.landscape;
    final preview = _autoplayTrailer(detail);
    final viewport = MediaQuery.sizeOf(context);
    final alignStart = MediaHeroLayout.isLargeScreen(context);
    return SizedBox(
      key: const Key('detail-poster-header'),
      height: MediaHeroLayout.heightForViewport(viewport),
      child: MediaHeroCard(
        item: item,
        heroTag: image == null
            ? null
            : heroTag ?? mediaArtworkHeroTag(item.ref),
        fallback: const ArtworkPlaceholder(icon: Icons.movie_outlined),
        preview: preview == null ? null : TrailerPreview(trailer: preview),
        foreground: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.md,
              bottom: MediaHeroLayout.summaryBottom,
              child: MediaHeroSummary(
                item: item,
                alignStart: alignStart,
                extra: detail.tags.isEmpty
                    ? null
                    : _Tags(values: detail.tags, alignStart: alignStart),
                actions: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailBackToolbar extends StatelessWidget {
  const _DetailBackToolbar({required this.opacity, required this.onPressed});

  final ValueListenable<double> opacity;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: SizedBox(
      height: MediaQuery.paddingOf(context).top + kToolbarHeight,
      child: ValueListenableBuilder<double>(
        valueListenable: opacity,
        builder: (context, value, _) => Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: ColoredBox(
                key: const Key('detail-toolbar-scrim'),
                color: AppColors.surfaceDark.withValues(alpha: value),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: onPressed,
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailHeroSliver extends StatelessWidget {
  const _DetailHeroSliver({
    required this.detail,
    required this.actions,
    this.heroTag,
  });

  final MediaDetailV2 detail;
  final Widget actions;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final height = MediaHeroLayout.heightForViewport(
      MediaQuery.sizeOf(context),
    );
    return SliverAppBar(
      expandedHeight: height,
      primary: false,
      collapsedHeight: 0,
      toolbarHeight: 0,
      pinned: false,
      floating: false,
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.surfaceDark,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: MediaHeroFlexibleSpace(
        expandedHeight: height,
        child: CenteredContent(
          child: _Header(detail: detail, actions: actions, heroTag: heroTag),
        ),
      ),
    );
  }
}

MediaTrailer? _autoplayTrailer(MediaDetailV2 detail) {
  for (final trailer in detail.trailers) {
    if (_isAutoplayTrailer(trailer)) {
      return trailer;
    }
  }
  return null;
}

bool _isAutoplayTrailer(MediaTrailer trailer) =>
    trailer.mimeType?.toLowerCase().startsWith('video/') ?? false;

class _DescriptionShimmer extends StatelessWidget {
  const _DescriptionShimmer();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShimmerPlaceholder(
          width: double.infinity,
          height: 16,
          borderRadius: AppRadius.sm,
        ),
        const SizedBox(height: AppSpacing.xs),
        ShimmerPlaceholder(
          width: double.infinity,
          height: 16,
          borderRadius: AppRadius.sm,
        ),
        const SizedBox(height: AppSpacing.xs),
        FractionallySizedBox(
          widthFactor: 0.7,
          alignment: Alignment.centerLeft,
          child: ShimmerPlaceholder(height: 16, borderRadius: AppRadius.sm),
        ),
      ],
    ),
  );
}

class _FavoriteAction extends StatelessWidget {
  const _FavoriteAction({required this.item});

  final MediaItemV2 item;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).libraryController;
    return BlocBuilder<LibraryController, LibraryState>(
      bloc: controller,
      builder: (context, state) {
        final active = state.isFavorite(item.ref);
        return IconButton(
          tooltip: active ? 'In favorites' : 'Add to favorites',
          onPressed: () => controller.toggleFavorite(item),
          icon: Icon(active ? Icons.check : Icons.add),
          style: IconButton.styleFrom(
            foregroundColor: AppColors.onDark,
            side: const BorderSide(color: AppColors.outlineDark),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
          ),
        );
      },
    );
  }
}

class _TrailerCard extends StatelessWidget {
  const _TrailerCard({required this.trailer, required this.onTap});

  final MediaTrailer trailer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: AppColors.surfaceDarkElevated,
      child: Semantics(
        button: true,
        label: 'Play ${trailer.title}',
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: trailer.thumbnail == null
                    ? const _TrailerImageFallback()
                    : CachedNetworkImage(
                        imageUrl: trailer.thumbnail!.url,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const _TrailerImageFallback(),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trailer.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onDark,
                      ),
                    ),
                    if (trailer.site case final site?)
                      Text(
                        site,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onDarkSoft,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TrailerImageFallback extends StatelessWidget {
  const _TrailerImageFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.surfaceDark,
    child: Center(
      child: Icon(Icons.play_circle_outline, color: AppColors.onDarkSoft),
    ),
  );
}

class _Tags extends StatelessWidget {
  const _Tags({required this.values, required this.alignStart});

  final List<String> values;
  final bool alignStart;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: alignStart ? WrapAlignment.start : WrapAlignment.center,
    spacing: AppSpacing.xs,
    runSpacing: AppSpacing.xs,
    children: [
      for (final value in values)
        Text(
          '• $value',
          style: AppTypography.bodySm.copyWith(color: AppColors.onDarkSoft),
        ),
    ],
  );
}

class _Facts extends StatelessWidget {
  const _Facts({required this.values});

  final List<MediaFact> values;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final fact in values)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 112,
                child: Text(
                  fact.label,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onDarkSoft,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  fact.value,
                  style: AppTypography.bodySm.copyWith(color: AppColors.onDark),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _Credits extends StatelessWidget {
  const _Credits({required this.values});

  final List<MediaCredit> values;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 88,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: values.length,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
      itemBuilder: (context, index) {
        final credit = values[index];
        return Container(
          width: 160,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceDarkElevated,
            borderRadius: AppRadius.md,
          ),
          child: Row(
            children: [
              _CreditAvatar(credit: credit),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      credit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onDark,
                      ),
                    ),
                    if (credit.role case final role?)
                      Text(
                        role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onDarkSoft,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _CreditAvatar extends StatelessWidget {
  const _CreditAvatar({required this.credit});

  final MediaCredit credit;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: AppColors.surfaceDark,
      child: Center(
        child: Text(
          credit.name.characters.first.toUpperCase(),
          style: AppTypography.titleSm.copyWith(color: AppColors.onDark),
        ),
      ),
    );
    return Semantics(
      image: credit.image != null,
      label: '${credit.name} profile image',
      child: ClipOval(
        child: SizedBox.square(
          dimension: 48,
          child: credit.image == null
              ? fallback
              : CachedNetworkImage(
                  imageUrl: credit.image!.url,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => fallback,
                  errorWidget: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

/// Range picker for a group too long to scroll — "1–100", "101–200", …
class _EpisodeRangeChips extends StatelessWidget {
  const _EpisodeRangeChips({
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;

  final int selected;

  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, label) in labels.indexed)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: ChoiceChip(
              label: Text(
                label,
                style: AppTypography.titleSm.copyWith(
                  color: index == selected
                      ? AppColors.surfaceDark
                      : AppColors.onDark,
                ),
              ),
              selected: index == selected,
              onSelected: (_) => onSelected(index),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.surfaceDarkElevated,
              selectedColor: AppColors.onDark,
              side: BorderSide.none,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.pill),
            ),
          ),
      ],
    ),
  );
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.progress,
    required this.onTap,
  });

  final EpisodeSummary episode;
  final double? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final availableAt = episode.availableAt;
    final unreleased =
        availableAt != null && availableAt.isAfter(DateTime.now().toUtc());
    final image = episode.artwork?.landscape ?? episode.artwork?.portrait;
    // The protocol requires a title, so a provider with no episode names sends
    // the position back as one. Printing both lines then says "Episode 5"
    // twice; the number carries the tile on its own instead.
    final position = 'Episode ${episode.position}';
    final name = episode.title.trim();
    final named = name.isNotEmpty && name != position;
    return Opacity(
      opacity: unreleased ? 0.5 : 1,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: AppSpacing.sm,
        leading: ClipRRect(
          borderRadius: AppRadius.sm,
          child: SizedBox(
            width: 104,
            height: 60,
            child: image == null
                ? const _EpisodeImageFallback()
                : CachedNetworkImage(
                    imageUrl: image.url,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const _EpisodeImageFallback(),
                    errorWidget: (_, _, _) => const _EpisodeImageFallback(),
                  ),
          ),
        ),
        title: Text(
          position,
          style: named
              ? AppTypography.caption.copyWith(color: AppColors.onDarkSoft)
              : AppTypography.bodyMd.copyWith(color: AppColors.onDark),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (named)
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMd.copyWith(color: AppColors.onDark),
              ),
            if (unreleased)
              Text(
                'Releases ${formatReleaseDate(availableAt.toLocal())}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.onDarkSoft,
                ),
              )
            else if (episode.description case final description?)
              Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (progress case final value?) ...[
              const SizedBox(height: AppSpacing.xs),
              Semantics(
                label: '${(value * 100).round()} percent watched',
                child: ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: AppRadius.pill,
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 3,
                      color: AppColors.brandAccent,
                      backgroundColor: AppColors.surfaceDarkHighest,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: unreleased ? null : const Icon(Icons.play_circle_outline),
        onTap: unreleased ? null : onTap,
      ),
    );
  }
}

class _EpisodeImageFallback extends StatelessWidget {
  const _EpisodeImageFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.surfaceDarkElevated,
    child: Icon(Icons.movie_outlined, color: AppColors.onDarkSoft),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.value);

  final String value;

  @override
  Widget build(BuildContext context) => Text(
    value,
    style: AppTypography.titleMd.copyWith(color: AppColors.onDark),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Could not load details.'),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: onBack, child: const Text('Go back')),
        ],
      ),
    ),
  );
}
