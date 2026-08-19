import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../library/library_controller_v2.dart';
import '../player/play_item.dart';
import '../theme/tokens.dart';

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
        position: index + 1,
      ),
    );
  }

  MediaItemV2 _primaryTarget(MediaDetailV2 detail) {
    final guide = detail.episodeGuide;
    final target = guide?.defaultEpisodeRef;
    if (guide == null || target == null) return detail.item;
    for (final group in guide.groups) {
      final index = group.episodes.indexWhere(
        (episode) => episode.ref == target,
      );
      if (index >= 0) return _episodeItem(detail.item, group, index);
    }
    return detail.item;
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
    final selectedGroup = groups.isEmpty
        ? null
        : groups.firstWhere(
            (group) => group.id == _selectedGroupId,
            orElse: () => groups.first,
          );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _Header(item: item)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          sliver: SliverList.list(
            children: [
              if (detail.tags.isNotEmpty) _Tags(values: detail.tags),
              if (detail.tags.isNotEmpty) const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => playItemV2(context, _primaryTarget(detail)),
                  icon: const Icon(Icons.play_arrow_rounded, size: 28),
                  label: const Text('Play'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _FavoriteAction(item: item),
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
              if (detail.facts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const _SectionTitle('Details'),
                const SizedBox(height: AppSpacing.sm),
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
                      DropdownButton<String>(
                        value: selectedGroup.id,
                        dropdownColor: AppColors.surfaceDarkElevated,
                        items: [
                          for (final group in groups)
                            DropdownMenuItem(
                              value: group.id,
                              child: Text(group.title),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _selectedGroupId = value),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final entry in selectedGroup.episodes.indexed)
                  _EpisodeTile(
                    episode: entry.$2,
                    onTap: () => playItemV2(
                      context,
                      _episodeItem(item, selectedGroup, entry.$1),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});

  final MediaItemV2 item;

  @override
  Widget build(BuildContext context) {
    final image = item.artwork?.landscape ?? item.artwork?.portrait;
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
                  style: AppTypography.displaySm.copyWith(
                    color: AppColors.onDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (item.subtitle case final subtitle?)
                  Text(
                    subtitle,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onDarkSoft,
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

class _FavoriteAction extends StatelessWidget {
  const _FavoriteAction({required this.item});

  final MediaItemV2 item;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).libraryControllerV2;
    return BlocBuilder<LibraryControllerV2, LibraryStateV2>(
      bloc: controller,
      builder: (context, state) {
        final active = state.isFavorite(item.ref);
        return OutlinedButton.icon(
          onPressed: () => controller.toggleFavorite(item),
          icon: Icon(active ? Icons.check : Icons.add),
          label: Text(active ? 'In favorites' : 'Add to favorites'),
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
    children: [for (final value in values) Chip(label: Text(value))],
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
    height: 80,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                credit.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySm.copyWith(color: AppColors.onDark),
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
        );
      },
    ),
  );
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, required this.onTap});

  final EpisodeSummary episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(episode.title),
    subtitle: episode.description == null
        ? null
        : Text(
            episode.description!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
    trailing: const Icon(Icons.play_circle_outline),
    onTap: onTap,
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
