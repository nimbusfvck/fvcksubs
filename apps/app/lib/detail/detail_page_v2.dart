import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
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
import '../theme/breakpoints.dart';
import '../theme/tokens.dart';
import '../utils/date_formatters.dart';
import '../widgets/centered_content.dart';
import '../widgets/clickable.dart';
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

  /// Cap on the Play/Remind Me + favorite action row's width once the page
  /// is wide enough for a rail — full-bleed is a thumb-friendly mobile
  /// pattern, but the same row stretched across a centered desktop-width
  /// column looks like an error state. Locked to [AppBreakpoints.railWidth],
  /// not resized as the window keeps growing past it.
  static const double _primaryActionsMaxWidth = AppBreakpoints.railWidth;

  Future<MediaDetailV2>? _detail;
  String? _selectedGroupId;
  int? _selectedRangeIndex;
  bool _descriptionExpanded = false;

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
          : 'Play';
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
    return target.resuming ? 'Continue $label' : 'Play $label';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.surfaceDark,
    body: FutureBuilder<MediaDetailV2>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasData) {
          return _LoadingDetail(item: widget.item, heroTag: widget.heroTag);
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _ErrorView(onBack: () => Navigator.of(context).pop());
        }
        return _buildDetail(snapshot.data!);
      },
    ),
  );

  Widget _buildDetail(MediaDetailV2 detail) {
    final item = detail.item;
    final trailers = detail.trailers
        .where((trailer) => !_isAutoplayTrailer(trailer))
        .toList(growable: false);
    final guide = detail.episodeGuide;
    final groups = guide?.groups ?? const <EpisodeGroup>[];
    final libraryController = AppScope.of(context).libraryController;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: CenteredContent(
            child: _Header(detail: detail, heroTag: widget.heroTag),
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
                  if (detail.tags.isNotEmpty) _Tags(values: detail.tags),
                  if (detail.tags.isNotEmpty)
                    const SizedBox(height: AppSpacing.md),
                  _primaryActionRow(
                    detail: detail,
                    item: item,
                    guide: guide,
                    libraryController: libraryController,
                  ),
                  if (item.isUpcoming && item.releaseDate != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Releases ${formatReleaseDate(item.releaseDate!.toLocal())}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onDarkSoft,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  if (detail.description case final description?) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      description,
                      maxLines: _descriptionExpanded ? null : 4,
                      overflow: _descriptionExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onDark,
                        height: 1.5,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(
                        () => _descriptionExpanded = !_descriptionExpanded,
                      ),
                      child: Text(
                        _descriptionExpanded ? 'Show less' : 'Show more',
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
                  if (detail.recommendations.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    const _SectionTitle('You Might Also Like'),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 248 + Clickable.ringBleed * 2,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: detail.recommendations.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final recommendation = detail.recommendations[index];
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
                                  VersionedMediaItem(item: recommendation),
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
    );
  }

  Widget _primaryActionRow({
    required MediaDetailV2 detail,
    required MediaItemV2 item,
    required EpisodeGuide? guide,
    required LibraryController libraryController,
  }) {
    final row = Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: _primaryAction(
              detail: detail,
              item: item,
              guide: guide,
              libraryController: libraryController,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _FavoriteAction(item: item),
      ],
    );
    return AppBreakpoints.isPhone(context)
        ? row
        : SizedBox(width: _primaryActionsMaxWidth, child: row);
  }

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
      final target = primaryEpisodeTarget(detail.episodeGuide, detail.item.ref, state);
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
    final target = primaryEpisodeTarget(detail.episodeGuide, detail.item.ref, library);
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
  const _Header({required this.detail, this.heroTag});

  final MediaDetailV2 detail;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    final image = item.artwork?.landscape ?? item.artwork?.portrait;
    final preview = _autoplayTrailer(detail);
    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            _HeaderArtwork(item: item, image: image, heroTag: heroTag)
          else
            const ArtworkPlaceholder(icon: Icons.movie_outlined),
          if (preview != null)
            Positioned.fill(child: TrailerPreview(trailer: preview)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black26, AppColors.surfaceDark],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.sm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.displaySm.copyWith(
                    color: AppColors.onDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (item.releaseYear != null || item.rating != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.xs,
                      children: [
                        if (item.releaseYear case final releaseYear?)
                          Text(
                            releaseYear.toString(),
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onDarkSoft,
                            ),
                          ),
                        if (item.releaseYear != null && item.rating != null)
                          Text(
                            '-',
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onDarkSoft,
                            ),
                          ),
                        if (item.rating case final rating?)
                          Semantics(
                            label: 'Rating ${rating.toStringAsFixed(1)}',
                            child: ExcludeSemantics(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 18,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: AppSpacing.xxs),
                                  Text(
                                    rating.toStringAsFixed(1),
                                    style: AppTypography.bodyMd.copyWith(
                                      color: AppColors.onDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (item.subtitle case final subtitle?)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onDarkSoft,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderArtwork extends StatelessWidget {
  const _HeaderArtwork({required this.item, required this.image, this.heroTag});

  final MediaItemV2 item;
  final ImageRef image;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final artwork = CachedNetworkImage(
      imageUrl: image.url,
      fit: BoxFit.cover,
      errorWidget: (_, _, _) =>
          const ColoredBox(color: AppColors.surfaceDarkElevated),
    );
    final portrait = item.artwork?.portrait;
    final tag = heroTag ?? mediaArtworkHeroTag(item.ref);
    return portrait == null ? artwork : Hero(tag: tag, child: artwork);
  }
}

class _LoadingDetail extends StatelessWidget {
  const _LoadingDetail({required this.item, this.heroTag});

  final MediaItemV2 item;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: CenteredContent(
          child: _Header(
            detail: MediaDetailV2(item: item),
            heroTag: heroTag,
          ),
        ),
      ),
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.md,
        ),
        sliver: SliverToBoxAdapter(
          child: CenteredContent(child: _DetailLoadingBody()),
        ),
      ),
    ],
  );
}

class _DetailLoadingBody extends StatelessWidget {
  const _DetailLoadingBody();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: ShimmerPlaceholder(height: 48, borderRadius: AppRadius.pill),
          ),
          const SizedBox(width: AppSpacing.sm),
          ShimmerPlaceholder(
            width: 44,
            height: 44,
            borderRadius: AppRadius.pill,
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(
            child: ShimmerPlaceholder(height: 14, borderRadius: AppRadius.sm),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: ShimmerPlaceholder(height: 14, borderRadius: AppRadius.sm),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: ShimmerPlaceholder(height: 14, borderRadius: AppRadius.sm),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      ShimmerPlaceholder(height: 18, borderRadius: AppRadius.sm),
      const SizedBox(height: AppSpacing.sm),
      ShimmerPlaceholder(height: 18, borderRadius: AppRadius.sm),
      const SizedBox(height: AppSpacing.sm),
      FractionallySizedBox(
        widthFactor: 0.72,
        alignment: Alignment.centerLeft,
        child: ShimmerPlaceholder(height: 18, borderRadius: AppRadius.sm),
      ),
      const SizedBox(height: AppSpacing.lg),
      ShimmerPlaceholder(height: 160, borderRadius: AppRadius.md),
    ],
  );
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

class _Tags extends StatelessWidget {
  const _Tags({required this.values});

  final List<String> values;

  @override
  Widget build(BuildContext context) => Wrap(
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
