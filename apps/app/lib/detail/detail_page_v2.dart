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
import 'detail_controller.dart';
import 'detail_state.dart';
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

  DetailController? _detailController;
  String? _selectedGroupId;
  int? _selectedRangeIndex;
  bool _descriptionExpanded = false;
  final ValueNotifier<double> _heroToolbarOpacity = ValueNotifier(0);

  @override
  void dispose() {
    _detailController?.close();
    _heroToolbarOpacity.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_detailController == null) {
      final controller = DetailController(
        registry: AppScope.of(context).registry,
        item: widget.item,
      );
      _detailController = controller;
      controller.load();
    }
  }

  String _playLabel(
    MediaDetailV2 detail,
    PrimaryEpisodeTarget? target,
    Duration? movieProgress,
  ) {
    if (target == null) {
      if (detail.episodeGuide != null) {
        final loading = detail.episodeGuide!.groups.any(
          (group) => !group.loaded,
        );
        return loading ? 'Loading episodes…' : 'Coming soon';
      }
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
  Widget build(BuildContext context) {
    final controller = _detailController;
    if (controller == null) {
      return const Scaffold(backgroundColor: AppColors.surfaceDark);
    }
    return BlocConsumer<DetailController, DetailState>(
      bloc: controller,
      listenWhen: (previous, current) =>
          previous.status != current.status ||
          previous.detail != current.detail,
      listener: (context, state) => _ensureSelectedGroupLoaded(state),
      builder: (context, state) {
        final detail = state.detail ?? MediaDetailV2(item: widget.item);
        return Scaffold(
          backgroundColor: AppColors.surfaceDark,
          body: _buildDetail(detail, metadataLoading: state.metadataLoading),
        );
      },
    );
  }

  void _ensureSelectedGroupLoaded(DetailState state) {
    final detail = state.detail;
    final guide = detail?.episodeGuide;
    if (detail == null || guide == null) return;
    final library = AppScope.of(context).libraryController.state;
    final group = _selectedGroup(detail, guide.groups, library);
    if (group == null ||
        group.loaded ||
        state.isGroupLoading(group.id) ||
        state.groupErrorFor(group.id) != null) {
      return;
    }
    _detailController?.loadGroup(group.id);
  }

  void _requestGroupLoad(String? groupId) {
    if (groupId == null) return;
    final controller = _detailController;
    final groups = controller?.state.detail?.episodeGuide?.groups;
    if (controller == null || groups == null) return;
    final group = groups
        .where((candidate) => candidate.id == groupId)
        .firstOrNull;
    if (group == null ||
        group.loaded ||
        controller.state.isGroupLoading(group.id)) {
      return;
    }
    controller.loadGroup(group.id);
  }

  Widget _buildDetail(MediaDetailV2 detail, {required bool metadataLoading}) {
    final item = detail.item;
    final trailers = detail.trailers
        .where((trailer) => !_isAutoplayTrailer(trailer))
        .toList(growable: false);
    final guide = detail.episodeGuide;
    final groups = guide?.groups ?? const <EpisodeGroup>[];
    final libraryController = AppScope.of(context).libraryController;
    final alignStart = MediaHeroLayout.isLargeScreen(context);
    // Cover the sliver compositing edge with two physical pixels. One pixel
    // can still expose the antialiased boundary while the hero is scrolling.
    final contentOverlap = 2 / MediaQuery.devicePixelRatioOf(context);

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onDetailScrollNotification,
          child: CustomScrollView(
            slivers: [
              _DetailHeroSliver(
                detail: detail,
                fallbackItem: widget.item,
                heroTag: widget.heroTag,
                descriptionExpanded: _descriptionExpanded,
                onToggleDescription: () => setState(
                  () => _descriptionExpanded = !_descriptionExpanded,
                ),
                actions: _heroActions(
                  detail: detail,
                  item: item,
                  guide: guide,
                  libraryController: libraryController,
                  alignStart: alignStart,
                ),
              ),
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: Offset(0, -contentOverlap),
                  child: Material(
                    color: AppColors.surfaceDark,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.xs,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: CenteredContent(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: metadataLoading
                              ? const [_DetailMetadataShimmer()]
                              : [
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
                                            const SizedBox(
                                              width: AppSpacing.sm,
                                            ),
                                        itemBuilder: (context, index) {
                                          final trailer = trailers[index];
                                          return _TrailerCard(
                                            trailer: trailer,
                                            onTap: () =>
                                                _openTrailer(context, trailer),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                  if (detail.facts.isNotEmpty) ...[
                                    const SizedBox(height: AppSpacing.xl),
                                    _Facts(values: detail.facts),
                                  ],
                                  if ((alignStart
                                          ? detail.credits
                                          : detail.credits
                                                .where(
                                                  (credit) =>
                                                      !_isDirector(credit),
                                                )
                                                .toList())
                                      .isNotEmpty) ...[
                                    const SizedBox(height: AppSpacing.xl),
                                    const _SectionTitle('Credits'),
                                    const SizedBox(height: AppSpacing.sm),
                                    _Credits(
                                      values: alignStart
                                          ? detail.credits
                                          : detail.credits
                                                .where(
                                                  (credit) =>
                                                      !_isDirector(credit),
                                                )
                                                .toList(),
                                    ),
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
                                      height:
                                          mediaCardPosterHeight(152) +
                                          Clickable.ringBleed * 2,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: collection.items.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(
                                              width: AppSpacing.sm,
                                            ),
                                        itemBuilder: (context, index) {
                                          final collectionItem =
                                              collection.items[index];
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
                                                  contentRating:
                                                      widget.contentRating,
                                                ),
                                                onLongPress: () =>
                                                    showMediaCardActions(
                                                      context,
                                                      collectionItem,
                                                      onViewDetails: () =>
                                                          openDetails(
                                                            context,
                                                            collectionItem,
                                                            heroTag: heroTag,
                                                            contentRating: widget
                                                                .contentRating,
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
                                      height:
                                          mediaRecommendationCardHeight(216) +
                                          Clickable.ringBleed * 2,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        clipBehavior: Clip.none,
                                        itemCount:
                                            detail.recommendations.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(
                                              width: AppSpacing.sm,
                                            ),
                                        itemBuilder: (context, index) {
                                          final recommendation =
                                              detail.recommendations[index];
                                          final heroTag = Object();
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: Clickable.ringBleed,
                                            ),
                                            child: MediaRecommendationCard(
                                              item: recommendation,
                                              heroTag: heroTag,
                                              onTap: () => openVersionedItem(
                                                context,
                                                VersionedMediaItem(
                                                  item: recommendation,
                                                ),
                                                heroTag: heroTag,
                                                contentRating:
                                                    widget.contentRating,
                                              ),
                                              onLongPress: () =>
                                                  showMediaCardActions(
                                                    context,
                                                    recommendation,
                                                    onViewDetails: () =>
                                                        openDetails(
                                                          context,
                                                          recommendation,
                                                          heroTag: heroTag,
                                                          contentRating: widget
                                                              .contentRating,
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
    final heroHeight = MediaHeroLayout.snapToDevicePixel(
      context,
      MediaHeroLayout.heightForViewport(MediaQuery.sizeOf(context)),
    );
    final fadeDistance = MediaHeroLayout.homeOverlayFadeDistance;
    final fadeStart = math.max(0.0, heroHeight - fadeDistance);
    _heroToolbarOpacity.value =
        ((notification.metrics.pixels - fadeStart) / fadeDistance)
            .clamp(0.0, 1.0)
            .toDouble();
    return false;
  }

  Widget _heroActions({
    required MediaDetailV2 detail,
    required MediaItemV2 item,
    required EpisodeGuide? guide,
    required LibraryController libraryController,
    required bool alignStart,
  }) {
    final primary = _primaryAction(
      detail: detail,
      item: item,
      guide: guide,
      libraryController: libraryController,
    );
    return Wrap(
      alignment: alignStart ? WrapAlignment.start : WrapAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        primary,
        _FavoriteAction(item: item),
      ],
    );
  }

  Widget _primaryAction({
    required MediaDetailV2 detail,
    required MediaItemV2 item,
    required EpisodeGuide? guide,
    required LibraryController libraryController,
  }) => BlocBuilder<LibraryController, LibraryState>(
    bloc: libraryController,
    builder: (context, state) {
      final target = primaryEpisodeTarget(
        detail.episodeGuide,
        detail.item.ref,
        state,
        preferFirstAvailable: true,
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
      if (!selectedGroup.loaded) {
        final detailController = _detailController;
        final groupError = detailController?.state.groupErrorFor(
          selectedGroup.id,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.xl),
            _episodeGroupHeader(groups, selectedGroup),
            const SizedBox(height: AppSpacing.md),
            if (groupError == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              const Text('Could not load episodes.'),
              TextButton(
                onPressed: () => detailController?.loadGroup(selectedGroup.id),
                child: const Text('Retry'),
              ),
            ],
          ],
        );
      }
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
          _episodeGroupHeader(groups, selectedGroup),
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
    if (resumed != null) return resumed.group;

    // Lazy groups have no episodes yet, so resumedEpisodeTarget cannot match
    // the saved episode ref. Its EpisodeIdentity still carries the exact
    // season, which lets the controller load the right group first.
    final resumedGroupId = _latestWatchedGroupId(detail.item.ref, library);
    if (resumedGroupId != null) {
      final resumedGroup = groups
          .where((group) => group.id == resumedGroupId)
          .firstOrNull;
      if (resumedGroup != null) return resumedGroup;
    }
    return groups.first;
  }

  String? _latestWatchedGroupId(MediaRef parentRef, LibraryState library) {
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
      final groupId = (record.item as EpisodeItemV2).episode.groupId;
      if (groupId != null) return groupId;
    }
    return null;
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
      preferFirstAvailable: true,
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

  Widget _episodeGroupHeader(
    List<EpisodeGroup> groups,
    EpisodeGroup selectedGroup,
  ) => Row(
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
                  child: Text(group.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedGroupId = value;
                // Another season's ranges are its own; keeping the index would
                // land on an arbitrary hundred of it.
                _selectedRangeIndex = null;
              });
              _requestGroupLoad(value);
            },
          ),
        ),
    ],
  );
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

class _Header extends StatelessWidget {
  const _Header({
    required this.detail,
    required this.fallbackItem,
    required this.actions,
    required this.descriptionExpanded,
    required this.onToggleDescription,
    this.heroTag,
  });

  final MediaDetailV2 detail;
  final MediaItemV2 fallbackItem;
  final Widget actions;
  final bool descriptionExpanded;
  final VoidCallback onToggleDescription;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    final tags = detail.tags.isNotEmpty ? detail.tags : item.genres;
    final image = item.artwork?.portrait ?? item.artwork?.landscape;
    final preview = _autoplayTrailer(detail);
    final ratings = _mergeRatings(item.ratings, fallbackItem.ratings);
    final viewport = MediaQuery.sizeOf(context);
    final alignStart = MediaHeroLayout.isLargeScreen(context);
    final heroHeight = MediaHeroLayout.snapToDevicePixel(
      context,
      MediaHeroLayout.heightForViewport(viewport),
    );
    return SizedBox(
      key: const Key('detail-poster-header'),
      height: heroHeight,
      child: MediaHeroCard(
        item: item,
        heroTag: image == null
            ? null
            : heroTag ?? mediaArtworkHeroTag(item.ref),
        fallback: const ArtworkPlaceholder(icon: Icons.movie_outlined),
        preview: preview == null ? null : TrailerPreview(trailer: preview),
        overlayGradient: MediaHeroCard.detailGradient,
        rotateBackdrops: false,
        bottomBlurSigma: 30,
        bottomBlurHeightFactor: 0.58,
        bottomBlurFadeStop: 0.25,
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
                showRatings: alignStart,
                ratingsOverride: ratings,
                actionsBeforeMeta: !alignStart,
                description: alignStart
                    ? detail.description ?? item.overview
                    : null,
                extra: tags.isEmpty
                    ? null
                    : _Tags(values: tags, alignStart: alignStart),
                actions: actions,
                afterActions: alignStart
                    ? null
                    : _DetailHeroAfterActions(
                        detail: detail,
                        ratings: ratings,
                        expanded: descriptionExpanded,
                        onToggleDescription: onToggleDescription,
                      ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 2 / MediaQuery.devicePixelRatioOf(context),
              child: const IgnorePointer(
                child: ColoredBox(color: AppColors.surfaceDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailHeroAfterActions extends StatelessWidget {
  const _DetailHeroAfterActions({
    required this.detail,
    required this.ratings,
    required this.expanded,
    required this.onToggleDescription,
  });

  final MediaDetailV2 detail;
  final List<MediaRating> ratings;
  final bool expanded;
  final VoidCallback onToggleDescription;

  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    final directors = detail.credits
        .where(_isDirector)
        .map((credit) => credit.name)
        .toList(growable: false);
    final directorFacts = detail.facts
        .where((fact) => _hasFactLabel(fact, 'director'))
        .map((fact) => fact.value)
        .toList(growable: false);
    final parentalFacts = detail.facts
        .where((fact) => _hasFactLabel(fact, 'parent'))
        .map((fact) => fact.value)
        .toList(growable: false);
    final heroFacts = detail.facts
        .where(_isCompactHeroFact)
        .toList(growable: false);
    final description = detail.description ?? item.overview;
    final allDirectors = [...directors, ...directorFacts].toSet().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _DetailHeroFacts(item: item, facts: heroFacts),
        if (allDirectors.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Director: ${allDirectors.join(', ')}',
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onDarkSoft,
              shadows: MediaHeroSummary.textShadows,
            ),
          ),
        ],
        if (parentalFacts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            parentalFacts.join(' · '),
            textAlign: TextAlign.center,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onDarkSoft,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              shadows: MediaHeroSummary.textShadows,
            ),
          ),
        ],
        if (description case final value? when value.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final style = AppTypography.bodySm.copyWith(
                color: AppColors.onDarkSoft,
                height: 1.35,
                shadows: MediaHeroSummary.textShadows,
              );
              final painter = TextPainter(
                text: TextSpan(text: value.trim(), style: style),
                maxLines: 3,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: constraints.maxWidth);
              final truncated = painter.didExceedMaxLines;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value.trim(),
                    maxLines: expanded ? null : 3,
                    overflow: expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: style,
                  ),
                  if (truncated)
                    TextButton(
                      onPressed: onToggleDescription,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.onDark,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xxs,
                        ),
                      ),
                      child: Text(expanded ? 'Hide More' : 'Read More'),
                    ),
                ],
              );
            },
          ),
        ],
        if (ratings.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              for (final rating in ratings) _DetailHeroRating(rating: rating),
            ],
          ),
        ],
      ],
    );
  }
}

class _DetailHeroFacts extends StatelessWidget {
  const _DetailHeroFacts({required this.item, required this.facts});

  final MediaItemV2 item;
  final List<MediaFact> facts;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (item.releaseYear case final year?) _HeroFactText('$year'),
      for (final fact in facts) _HeroFactText(fact.value, fact: fact),
      if (item.rating case final rating?)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, size: 17, color: Colors.amber),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              rating.toStringAsFixed(1),
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onDark,
                fontWeight: FontWeight.w700,
                shadows: MediaHeroSummary.textShadows,
              ),
            ),
          ],
        ),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

class _HeroFactText extends StatelessWidget {
  const _HeroFactText(this.value, {this.fact});

  final String value;
  final MediaFact? fact;

  @override
  Widget build(BuildContext context) {
    final label = fact?.label.toLowerCase() ?? '';
    final boxed =
        label.contains('rating') ||
        label.contains('quality') ||
        label.contains('resolution') ||
        label.contains('certification');
    final text = Text(
      value,
      style: AppTypography.bodySm.copyWith(
        color: AppColors.onDark,
        fontWeight: FontWeight.w700,
        shadows: MediaHeroSummary.textShadows,
      ),
    );
    return Semantics(
      label: fact == null ? value : '${fact!.label}: $value',
      child: boxed
          ? DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.onDarkSoft),
                borderRadius: AppRadius.sm,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxs,
                ),
                child: text,
              ),
            )
          : text,
    );
  }
}

class _DetailHeroRating extends StatelessWidget {
  const _DetailHeroRating({required this.rating});

  final MediaRating rating;

  @override
  Widget build(BuildContext context) {
    final score = rating.scale == 10
        ? '${rating.score.toStringAsFixed(1)}/10'
        : '${rating.score.toStringAsFixed(0)}/${rating.scale.toStringAsFixed(0)}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rating.icon case final icon?)
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: CachedNetworkImage(
              imageUrl: icon.url,
              width: 18,
              height: 18,
              fit: BoxFit.contain,
              errorWidget: (_, _, _) =>
                  RatingSourceBadge(source: rating.source),
            ),
          )
        else
          RatingSourceBadge(source: rating.source),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          '$score',
          style: AppTypography.bodySm.copyWith(
            color: AppColors.onDark,
            fontWeight: FontWeight.w700,
            shadows: MediaHeroSummary.textShadows,
          ),
        ),
      ],
    );
  }
}

bool _isDirector(MediaCredit credit) =>
    credit.role?.toLowerCase().contains('director') ?? false;

bool _hasFactLabel(MediaFact fact, String value) =>
    fact.label.toLowerCase().contains(value);

List<MediaRating> _mergeRatings(
  List<MediaRating> detailRatings,
  List<MediaRating> catalogRatings,
) {
  final merged = <String, MediaRating>{
    for (final rating in catalogRatings) rating.source: rating,
  };
  for (final rating in detailRatings) {
    final catalogRating = merged[rating.source];
    merged[rating.source] = catalogRating == null
        ? rating
        : MediaRating(
            source: rating.source,
            score: rating.score,
            scale: rating.scale,
            votes: rating.votes ?? catalogRating.votes,
            kind: rating.kind ?? catalogRating.kind,
            icon: rating.icon ?? catalogRating.icon,
          );
  }
  return merged.values.toList(growable: false);
}

bool _isCompactHeroFact(MediaFact fact) {
  final label = fact.label.toLowerCase();
  return label.contains('runtime') ||
      label.contains('duration') ||
      label.contains('quality') ||
      label.contains('resolution') ||
      label.contains('certification') ||
      label.contains('content rating') ||
      label == 'rated' ||
      label == 'rating';
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
    required this.fallbackItem,
    required this.actions,
    required this.descriptionExpanded,
    required this.onToggleDescription,
    this.heroTag,
  });

  final MediaDetailV2 detail;
  final MediaItemV2 fallbackItem;
  final Widget actions;
  final bool descriptionExpanded;
  final VoidCallback onToggleDescription;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final height = MediaHeroLayout.snapToDevicePixel(
      context,
      MediaHeroLayout.heightForViewport(MediaQuery.sizeOf(context)),
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
      shadowColor: Colors.transparent,
      forceMaterialTransparency: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: MediaHeroFlexibleSpace(
        expandedHeight: height,
        child: CenteredContent(
          child: _Header(
            detail: detail,
            fallbackItem: fallbackItem,
            actions: actions,
            descriptionExpanded: descriptionExpanded,
            onToggleDescription: onToggleDescription,
            heroTag: heroTag,
          ),
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

class _DetailMetadataShimmer extends StatelessWidget {
  const _DetailMetadataShimmer();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: AppSpacing.xl),
      const _DetailShimmerHeading(width: 76),
      const SizedBox(height: AppSpacing.sm),
      SizedBox(
        height: 192,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 2,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, _) => const _DetailTrailerShimmer(),
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      const _DetailShimmerHeading(width: 64),
      const SizedBox(height: AppSpacing.sm),
      for (var index = 0; index < 4; index++)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            children: [
              ShimmerPlaceholder(width: 92, height: 14),
              SizedBox(width: AppSpacing.md),
              Expanded(child: ShimmerPlaceholder(height: 14)),
            ],
          ),
        ),
      const SizedBox(height: AppSpacing.xl),
      const _DetailShimmerHeading(width: 70),
      const SizedBox(height: AppSpacing.sm),
      SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, _) => const _DetailCreditShimmer(),
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      const _DetailShimmerHeading(width: 72),
      const SizedBox(height: AppSpacing.sm),
      for (var index = 0; index < 3; index++) const _DetailEpisodeShimmer(),
      const SizedBox(height: AppSpacing.xl),
      const _DetailShimmerHeading(width: 150),
      const SizedBox(height: AppSpacing.sm),
      SizedBox(
        height: 216,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, _) => SizedBox(
            width: 152,
            child: ShimmerPlaceholder(height: 216, borderRadius: AppRadius.md),
          ),
        ),
      ),
    ],
  );
}

class _DetailShimmerHeading extends StatelessWidget {
  const _DetailShimmerHeading({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) => ShimmerPlaceholder(
    width: width,
    height: 20,
    borderRadius: const BorderRadius.all(Radius.circular(4)),
  );
}

class _DetailTrailerShimmer extends StatelessWidget {
  const _DetailTrailerShimmer();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 220,
    child: Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerPlaceholder(height: 124),
          Padding(
            padding: EdgeInsets.all(AppSpacing.sm),
            child: ShimmerPlaceholder(width: 132, height: 14),
          ),
        ],
      ),
    ),
  );
}

class _DetailCreditShimmer extends StatelessWidget {
  const _DetailCreditShimmer();

  @override
  Widget build(BuildContext context) => Container(
    width: 160,
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.surfaceDarkElevated,
      borderRadius: AppRadius.md,
    ),
    child: const Row(
      children: [
        ShimmerPlaceholder(
          width: 48,
          height: 48,
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerPlaceholder(width: 76, height: 12),
              SizedBox(height: AppSpacing.xs),
              ShimmerPlaceholder(width: 52, height: 10),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DetailEpisodeShimmer extends StatelessWidget {
  const _DetailEpisodeShimmer();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      children: [
        ShimmerPlaceholder(width: 104, height: 60, borderRadius: AppRadius.sm),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerPlaceholder(width: 92, height: 14),
              SizedBox(height: AppSpacing.xs),
              ShimmerPlaceholder(width: 180, height: 11),
            ],
          ),
        ),
      ],
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
