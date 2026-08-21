import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../catalog/media_hero.dart';
import '../player/play_item.dart';
import 'episode_target.dart';
import 'latest_available_episode.dart';
import '../utils/date_formatters.dart';
import '../catalog/media_card.dart';
import '../theme/tokens.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.item});

  final MediaItem item;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Future<List<StreamSource>>? _sources;
  Future<MediaDetail>? _detailFuture;
  bool _isDescriptionExpanded = false;

  int? _selectedSeasonIndex;

  bool _resolvingPlayTarget = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    _sources ??= scope.registry.sources(widget.item);
    if (_detailFuture == null) {
      try {
        _detailFuture = scope.registry.meta(widget.item.ref);
      } catch (_) {
        _detailFuture = null;
      }
    }
  }

  Future<void> _play({
    MediaItem? overrideItem,
    List<SeriesSeason> seasons = const [],
  }) => playItem(
    context,
    overrideItem ?? widget.item,
    seasons: seasons,
    returnToDetail: true,
  );

  Future<void> _playTarget(
    EpisodeTarget? target,
    MediaItem series,
    List<SeriesSeason> seasons, {
    bool probeLatestAvailable = false,
    int? lastAiredSeason,
    int? lastAiredEpisode,
  }) async {
    if (probeLatestAvailable && target != null && !target.resuming) {
      setState(() => _resolvingPlayTarget = true);
      final latest = await latestAvailableEpisodeTarget(
        AppScope.of(context).registry,
        series,
        seasons,
        lastAiredSeason: lastAiredSeason,
        lastAiredEpisode: lastAiredEpisode,
      );
      if (!mounted) return;
      setState(() => _resolvingPlayTarget = false);
      await _play(
        overrideItem: (latest ?? target).itemFor(series),
        seasons: seasons,
      );
      return;
    }
    await _play(overrideItem: target?.itemFor(series), seasons: seasons);
  }

  static String _playLabel(EpisodeTarget? target, Duration? movieProgress) {
    if (target != null) {
      return target.resuming
          ? 'Continue ${target.label}'
          : 'Play ${target.label}';
    }
    if ((movieProgress ?? Duration.zero) > Duration.zero) {
      return 'Continue Watching';
    }
    return 'Play';
  }

  String _formatRuntime(int? minutes) {
    if (minutes == null || minutes <= 0) return '';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0 && mins > 0) return '${hours}h ${mins}m';
    if (hours > 0) return '${hours}h';
    return '${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      backgroundColor: AppColors.surfaceDark,
      body: FutureBuilder<MediaDetail>(
        future: _detailFuture,
        builder: (context, snapshot) {
          final detail = snapshot.data;
          final description = detail?.description ?? item.subtitle ?? '';
          final cast = detail?.cast ?? const [];
          final seasons = detail?.seasons ?? const [];
          final genres = detail?.genres ?? const [];
          final runtime = _formatRuntime(detail?.runtimeMinutes);
          final certification = detail?.certification;
          final selectedSeasonIndex =
              _selectedSeasonIndex ??
              defaultSeasonIndex(seasons, detail?.lastAiredSeason);

          final watched = AppScope.of(
            context,
          ).legacyLibraryController.recordFor(item.ref);

          final target = episodeTargetFor(
            seasons,
            watched,
            lastAiredSeason: detail?.lastAiredSeason,
            lastAiredEpisode: detail?.lastAiredEpisode,
          );

          final metaParts = <String>[
            if (genres.isNotEmpty) genres.take(2).join(', '),
            if (runtime.isNotEmpty) runtime,
            if (certification != null && certification.isNotEmpty)
              certification,
          ];

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _BackdropHeader(
                  item: item,
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (metaParts.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          metaParts.join('  ·  '),
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onDarkSoft,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],

                      const SizedBox(height: AppSpacing.md),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _resolvingPlayTarget
                              ? null
                              : () => _playTarget(
                                  target,
                                  item,
                                  seasons,
                                  probeLatestAvailable: true,
                                  lastAiredSeason: detail?.lastAiredSeason,
                                  lastAiredEpisode: detail?.lastAiredEpisode,
                                ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          icon: _resolvingPlayTarget
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.black54,
                                  ),
                                )
                              : const Icon(
                                  Icons.play_arrow,
                                  size: 28,
                                  color: Colors.black,
                                ),
                          label: Text(
                            _playLabel(target, watched?.progress),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      _ActionRow(item: item),

                      if (description.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _DescriptionText(
                          description: description,
                          isExpanded: _isDescriptionExpanded,
                          onToggle: () {
                            setState(() {
                              _isDescriptionExpanded = !_isDescriptionExpanded;
                            });
                          },
                        ),
                      ],

                      if (cast.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          'Cast',
                          style: AppTypography.titleMd.copyWith(
                            color: AppColors.onDark,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _CastList(cast: cast),
                      ],

                      if (seasons.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        Row(
                          children: [
                            Text(
                              'Episodes',
                              style: AppTypography.titleMd.copyWith(
                                color: AppColors.onDark,
                              ),
                            ),
                            const Spacer(),
                            if (seasons.length > 1)
                              Flexible(
                                child: DropdownButton<int>(
                                  value: selectedSeasonIndex,
                                  isExpanded: true,
                                  dropdownColor: AppColors.surfaceDarkElevated,
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.onDark,
                                  ),
                                  underline: const SizedBox(),
                                  items: [
                                    for (int i = 0; i < seasons.length; i++)
                                      DropdownMenuItem(
                                        value: i,
                                        child: Text(
                                          seasons[i].name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(
                                        () => _selectedSeasonIndex = val,
                                      );
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Builder(
                          builder: (context) {
                            final season =
                                seasons[selectedSeasonIndex < seasons.length
                                    ? selectedSeasonIndex
                                    : 0];
                            return _EpisodesList(
                              season: season,
                              lastAiredSeason: detail?.lastAiredSeason,
                              lastAiredEpisode: detail?.lastAiredEpisode,
                              onPlayEpisode: (epNum, epTitle) => _playTarget(
                                EpisodeTarget(
                                  season: season.number,
                                  episode: epNum,
                                  title: epTitle,
                                  resuming: false,
                                ),
                                item,
                                seasons,
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BackdropHeader extends StatelessWidget {
  const _BackdropHeader({required this.item, required this.onBack});

  final MediaItem item;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final posterUrl = item.poster?.url ?? item.thumbnail?.url;

    return SizedBox(
      height: 380,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (posterUrl != null)
            Hero(
              tag: mediaArtworkHeroTag(item.ref),
              child: CachedNetworkImage(
                imageUrl: posterUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                placeholder: (context, url) =>
                    const ColoredBox(color: AppColors.surfaceDarkElevated),
                errorWidget: (context, url, error) => const ColoredBox(
                  color: AppColors.surfaceDarkElevated,
                  child: Icon(
                    Icons.movie_outlined,
                    color: AppColors.onDarkSoft,
                    size: 64,
                  ),
                ),
              ),
            )
          else
            const ColoredBox(color: AppColors.surfaceDarkElevated),

          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.center,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.surfaceDark.withValues(alpha: 0.4),
                    AppColors.surfaceDark,
                  ],
                  stops: const [0.3, 0.75, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: onBack,
                ),
              ),
            ),
          ),

          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.xs,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.status == LiveStatus.live)
                  const LiveBadge()
                else if (item.status == LiveStatus.scheduled)
                  const UpcomingBadge(),
                Text(
                  item.title,
                  style: AppTypography.displaySm.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: const [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                if (item.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle!,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onDarkSoft,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).legacyLibraryController;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final favorited = controller.isFavorite(item.ref);
            return _CircleActionButton(
              icon: favorited ? Icons.check : Icons.add,
              label: 'My List',
              isActive: favorited,
              onTap: () => controller.toggleFavorite(item),
            );
          },
        ),

        _CircleActionButton(
          icon: Icons.thumb_up_outlined,
          label: 'Rate',
          onTap: () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Rated')));
          },
        ),

        _CircleActionButton(
          icon: Icons.download_outlined,
          label: 'Download',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Download not available')),
            );
          },
        ),
      ],
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: AppRadius.md,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.brandAccent.withValues(alpha: 0.2)
                  : AppColors.surfaceDarkElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? AppColors.brandAccent : Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: isActive ? AppColors.brandAccent : AppColors.onDarkSoft,
            ),
          ),
        ],
      ),
    ),
  );
}

class _DescriptionText extends StatelessWidget {
  const _DescriptionText({
    required this.description,
    required this.isExpanded,
    required this.onToggle,
  });

  final String description;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        description,
        maxLines: isExpanded ? null : 3,
        overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
        style: AppTypography.bodyMd.copyWith(
          color: AppColors.onDark,
          height: 1.4,
        ),
      ),
      GestureDetector(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            isExpanded ? 'LESS' : 'MORE',
            style: AppTypography.caption.copyWith(
              color: AppColors.onDarkSoft,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ),
    ],
  );
}

class _CastList extends StatelessWidget {
  const _CastList({required this.cast});

  final List<CastMember> cast;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 100,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: cast.length,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
      itemBuilder: (context, index) {
        final member = cast[index];
        return SizedBox(
          width: 70,
          child: Column(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.surfaceDarkElevated,
                backgroundImage: member.photoUrl != null
                    ? CachedNetworkImageProvider(member.photoUrl!)
                    : null,
                child: member.photoUrl == null
                    ? Text(
                        member.name.isNotEmpty ? member.name[0] : '?',
                        style: AppTypography.titleSm.copyWith(
                          color: AppColors.onDark,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(color: AppColors.onDark),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _EpisodesList extends StatelessWidget {
  const _EpisodesList({
    required this.season,
    required this.onPlayEpisode,
    this.lastAiredSeason,
    this.lastAiredEpisode,
  });

  final SeriesSeason season;
  final void Function(int episodeNum, String title) onPlayEpisode;

  final int? lastAiredSeason;
  final int? lastAiredEpisode;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (int i = 0; i < season.episodes.length; i++) ...[
        _EpisodeTile(
          episodeNum: i + 1,
          episode: season.episodes[i],
          unreleased: isUnreleased(
            season.episodes[i],
            seasonNumber: season.number,
            episodeNum: i + 1,
            lastAiredSeason: lastAiredSeason,
            lastAiredEpisode: lastAiredEpisode,
          ),
          onTap: () => onPlayEpisode(i + 1, season.episodes[i].title),
        ),
        if (i < season.episodes.length - 1)
          const Divider(color: Colors.white10, height: 1),
      ],
    ],
  );
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episodeNum,
    required this.episode,
    required this.unreleased,
    required this.onTap,
  });

  final int episodeNum;
  final SeriesEpisode episode;

  final bool unreleased;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: unreleased ? 0.5 : 1,
    child: InkWell(
      onTap: unreleased ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            if (episode.thumbnailUrl != null)
              ClipRRect(
                borderRadius: AppRadius.sm,
                child: SizedBox(
                  width: 100,
                  height: 60,
                  child: CachedNetworkImage(
                    imageUrl: episode.thumbnailUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        const ColoredBox(color: AppColors.surfaceDarkElevated),
                    errorWidget: (context, url, error) =>
                        const ColoredBox(color: AppColors.surfaceDarkElevated),
                  ),
                ),
              )
            else
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceDarkElevated,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$episodeNum',
                  style: AppTypography.titleSm.copyWith(
                    color: AppColors.onDark,
                  ),
                ),
              ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$episodeNum. ${episode.title}',
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (unreleased)
                    Text(
                      episode.releaseDate != null
                          ? 'Releases ${formatReleaseDate(episode.releaseDate!)}'
                          : 'Not yet released',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onDarkSoft,
                      ),
                    )
                  else if (episode.duration != null)
                    Text(
                      episode.duration!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onDarkSoft,
                      ),
                    ),
                ],
              ),
            ),
            if (!unreleased)
              IconButton(
                icon: const Icon(
                  Icons.play_circle_outline,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: onTap,
              ),
          ],
        ),
      ),
    ),
  );
}
