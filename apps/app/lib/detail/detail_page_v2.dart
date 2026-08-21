import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_scope.dart';
import '../library/library_controller.dart';
import '../player/play_item.dart';
import '../player/stream_player.dart';
import '../theme/tokens.dart';
import '../utils/date_formatters.dart';

class DetailPageV2 extends StatefulWidget {
  const DetailPageV2({super.key, required this.item});

  final MediaItemV2 item;

  @override
  State<DetailPageV2> createState() => _DetailPageV2State();
}

class _DetailPageV2State extends State<DetailPageV2> {
  Future<MediaDetailV2>? _detail;
  String? _selectedGroupId;
  bool _descriptionExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detail ??= AppScope.of(context).registry.metaV2(widget.item.ref);
  }

  EpisodeItemV2 _episodeItem(
    MediaItemV2 parent,
    EpisodeGroup group,
    int index,
  ) {
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
    );
  }

  ({EpisodeGroup group, int index, bool resuming})? _primaryEpisode(
    MediaDetailV2 detail,
    LibraryState library,
  ) {
    final guide = detail.episodeGuide;
    final target = guide?.defaultEpisodeRef;
    if (guide == null || guide.groups.isEmpty) return null;
    final resumed = _resumedEpisode(guide, detail.item.ref, library);
    if (resumed != null) return resumed;
    if (target != null) {
      for (final group in guide.groups) {
        final index = group.episodes.indexWhere(
          (episode) => episode.ref == target,
        );
        if (index >= 0 && _isAvailable(group.episodes[index])) {
          return (group: group, index: index, resuming: false);
        }
      }
    }
    for (final group in guide.groups.reversed) {
      for (final entry in group.episodes.indexed.toList().reversed) {
        if (_isAvailable(entry.$2)) {
          return (group: group, index: entry.$1, resuming: false);
        }
      }
    }
    return null;
  }

  ({EpisodeGroup group, int index, bool resuming})? _resumedEpisode(
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
        if (index >= 0 && _isAvailable(group.episodes[index])) {
          return (group: group, index: index, resuming: true);
        }
      }
    }
    return null;
  }

  bool _hasEpisodes(MediaDetailV2 detail) =>
      detail.episodeGuide?.groups.any((group) => group.episodes.isNotEmpty) ??
      false;

  bool _isAvailable(EpisodeSummary episode) {
    final availableAt = episode.availableAt;
    return availableAt == null || !availableAt.isAfter(DateTime.now().toUtc());
  }

  MediaItemV2? _primaryTarget(
    MediaDetailV2 detail,
    ({EpisodeGroup group, int index, bool resuming})? target,
  ) {
    if (target == null) return _hasEpisodes(detail) ? null : detail.item;
    return _episodeItem(detail.item, target.group, target.index);
  }

  String _playLabel(
    MediaDetailV2 detail,
    ({EpisodeGroup group, int index, bool resuming})? target,
    Duration? movieProgress,
  ) {
    if (target == null) {
      if (_hasEpisodes(detail)) return 'Coming soon';
      return (movieProgress ?? Duration.zero) > Duration.zero
          ? 'Continue Watching'
          : 'Play';
    }
    final season = RegExp(
      r'\b(?:season|s)\s*([0-9]+)\b',
      caseSensitive: false,
    ).firstMatch(target.group.title)?.group(1);
    if (season == null) return target.resuming ? 'Continue' : 'Play';
    final label = 'S${season}E${target.group.episodes[target.index].position}';
    return target.resuming ? 'Continue $label' : 'Play $label';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.surfaceDark,
    body: FutureBuilder<MediaDetailV2>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
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
    final guide = detail.episodeGuide;
    final groups = guide?.groups ?? const <EpisodeGroup>[];
    final libraryController = AppScope.of(context).libraryController;
    final selectedGroup = groups.isEmpty
        ? null
        : groups.firstWhere(
            (group) => group.id == _selectedGroupId,
            orElse: () => groups.last,
          );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Header(detail: detail)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.md,
          ),
          sliver: SliverList.list(
            children: [
              if (detail.tags.isNotEmpty) _Tags(values: detail.tags),
              if (detail.tags.isNotEmpty) const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: BlocBuilder<LibraryController, LibraryState>(
                        bloc: libraryController,
                        builder: (context, state) {
                          final target = _primaryEpisode(detail, state);
                          final primaryTarget = _primaryTarget(detail, target);
                          return _PrimaryPlayButton(
                            onPressed: primaryTarget == null
                                ? null
                                : () => playItemV2(
                                    context,
                                    primaryTarget,
                                    returnToDetail: true,
                                  ),
                            label: _playLabel(
                              detail,
                              target,
                              state.recordFor(item.ref)?.progress,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _FavoriteAction(item: item),
                ],
              ),
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
                  child: Text(_descriptionExpanded ? 'Show less' : 'Show more'),
                ),
              ],
              if (detail.trailers.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                const _SectionTitle('Trailers'),
                const SizedBox(height: AppSpacing.sm),
                for (final trailer in detail.trailers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _openTrailer(context, trailer),
                        icon: const Icon(Icons.play_circle_outline, size: 18),
                        label: Text(
                          trailer.site == null
                              ? trailer.title
                              : '${trailer.title} · ${trailer.site}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
              if (selectedGroup != null) ...[
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
                          onChanged: (value) =>
                              setState(() => _selectedGroupId = value),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final entry in selectedGroup.episodes.indexed)
                  BlocBuilder<LibraryController, LibraryState>(
                    bloc: libraryController,
                    builder: (context, state) => _EpisodeTile(
                      episode: entry.$2,
                      progress: _progressFraction(
                        state.recordFor(entry.$2.ref),
                      ),
                      onTap: () => playItemV2(
                        context,
                        _episodeItem(item, selectedGroup, entry.$1),
                        returnToDetail: true,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
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
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.play_arrow_rounded, size: 28),
    label: Text(label),
    style: ElevatedButton.styleFrom(shape: const StadiumBorder()),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final MediaDetailV2 detail;

  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    final image = item.artwork?.landscape ?? item.artwork?.portrait;
    final preview = _autoplayTrailer(detail);
    return SizedBox(
      height: 340,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            CachedNetworkImage(
              imageUrl: image.url,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) =>
                  const ColoredBox(color: AppColors.surfaceDarkElevated),
            )
          else
            const ColoredBox(color: AppColors.surfaceDarkElevated),
          if (preview != null)
            Positioned.fill(
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) => BetterPlayerView(
                    stream: PlayableStream(
                      url: preview.url,
                      // Keep the cache key unique per signed preview URL.
                      label: preview.url,
                    ),
                    // Match the hero container so the embedded player uses
                    // the same full area as the poster background.
                    aspectRatio: constraints.maxWidth / constraints.maxHeight,
                    looping: true,
                    muted: true,
                    fit: BoxFit.cover,
                    isLive: false,
                  ),
                ),
              ),
            ),
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

MediaTrailer? _autoplayTrailer(MediaDetailV2 detail) {
  for (final trailer in detail.trailers) {
    if (trailer.mimeType?.toLowerCase().startsWith('video/') ?? false) {
      return trailer;
    }
  }
  return null;
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
        return SizedBox.square(
          dimension: 44,
          child: IconButton(
            tooltip: active ? 'In favorites' : 'Add to favorites',
            onPressed: () => controller.toggleFavorite(item),
            icon: Icon(active ? Icons.check : Icons.add),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.onDark,
              side: const BorderSide(color: AppColors.outlineDark),
              shape: const StadiumBorder(),
            ),
          ),
        );
      },
    );
  }
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
          'Episode ${episode.position}',
          style: AppTypography.caption.copyWith(color: AppColors.onDarkSoft),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              episode.title,
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
