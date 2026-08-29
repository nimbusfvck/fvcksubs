import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../app_scope.dart';
import '../../catalog/artwork_placeholder.dart';
import '../../library/library_controller.dart';
import '../../player/widgets/app_preview_player.dart';
import '../../theme/tokens.dart';
import '../../utils/date_formatters.dart';
import '../shorts_primary_action.dart';
import '../shorts_state.dart';

/// One Shorts feed item: preview player (or artwork while it initializes),
/// title/kind/date/rating/synopsis overlay, and the primary/Favorite/Sound
/// actions. No transport controls — per source plan §5, this is a preview
/// surface, not the full player.
class ShortsFeedCard extends StatelessWidget {
  const ShortsFeedCard({
    super.key,
    required this.item,
    required this.detail,
    required this.previewResolution,
    required this.muted,
    required this.playing,
    required this.onToggleMute,
    required this.onReady,
    required this.onError,
    required this.onWatch,
  });

  final MediaItemV2 item;
  final MediaDetailV2? detail;
  final PreviewResolution previewResolution;
  final bool muted;
  final bool playing;
  final VoidCallback onToggleMute;
  final VoidCallback onReady;
  final void Function(Object error) onError;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final source = previewResolution.source;
    final artwork = item.artwork?.portrait ?? item.artwork?.landscape;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (artwork != null)
            CachedNetworkImage(
              imageUrl: artwork.url,
              fit: BoxFit.contain,
              fadeInDuration: Duration.zero,
              placeholder: (_, _) => const ArtworkPlaceholder(),
              errorWidget: (_, _, _) => const ArtworkPlaceholder(),
            )
          else
            const ArtworkPlaceholder(),
          if (previewResolution.status == PreviewStatus.usable && source != null)
            AppPreviewPlayer(
              key: ValueKey(source.id),
              source: source,
              muted: muted,
              playing: playing,
              onReady: onReady,
              onError: onError,
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
                stops: [0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            right: AppSpacing.sm,
            bottom: AppSpacing.xxl,
            child: _SoundButton(muted: muted, onPressed: onToggleMute),
          ),
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: _InfoOverlay(item: item, detail: detail, onWatch: onWatch),
          ),
        ],
      ),
    );
  }
}

class _InfoOverlay extends StatelessWidget {
  const _InfoOverlay({required this.item, required this.detail, required this.onWatch});

  final MediaItemV2 item;
  final MediaDetailV2? detail;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
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
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          children: [
            Text(_kindLabel(item.kind), style: _metaStyle),
            if (item.releaseDate case final date?)
              Text('· ${formatReleaseDate(date)}', style: _metaStyle)
            else if (item.releaseYear case final year?)
              Text('· $year', style: _metaStyle),
            if (item.rating case final rating?)
              Text('· ★ ${rating.toStringAsFixed(1)}', style: _metaStyle),
          ],
        ),
      ),
      if (item.subtitle case final subtitle? when subtitle.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            subtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
          ),
        ),
      const SizedBox(height: AppSpacing.sm),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PrimaryActionButton(item: item, detail: detail, onWatch: onWatch),
          const SizedBox(width: AppSpacing.sm),
          _FavoriteButton(item: item),
        ],
      ),
    ],
  );

  static const _metaStyle = TextStyle(color: AppColors.onDarkSoft, fontSize: 14);

  static String _kindLabel(MediaKindV2 kind) => switch (kind) {
    MediaKindV2.video => 'Movie',
    MediaKindV2.series => 'Series',
    MediaKindV2.episode => 'Episode',
    MediaKindV2.channel => 'Live',
    MediaKindV2.event => 'Live event',
  };
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({required this.item, required this.detail, required this.onWatch});

  final MediaItemV2 item;
  final MediaDetailV2? detail;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final libraryController = AppScope.of(context).libraryController;
    return BlocBuilder<LibraryController, LibraryState>(
      bloc: libraryController,
      builder: (context, library) {
        final action = primaryActionFor(item, detail: detail, library: library);
        final isRemindMe = action.kind == ShortsActionKind.remindMe;
        return FilledButton.icon(
          onPressed: isRemindMe
              ? () => libraryController.toggleReminder(item)
              : onWatch,
          icon: Icon(_iconFor(action.kind, library.isReminded(item.ref)), size: 22),
          label: Text(
            isRemindMe && library.isReminded(item.ref) ? 'Reminder Set' : action.label,
          ),
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
          ),
        );
      },
    );
  }

  IconData _iconFor(ShortsActionKind kind, bool reminded) => switch (kind) {
    ShortsActionKind.remindMe =>
      reminded ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
    ShortsActionKind.watch || ShortsActionKind.watchLive => Icons.play_arrow_rounded,
    ShortsActionKind.details => Icons.info_outline_rounded,
  };
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.item});

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

class _SoundButton extends StatelessWidget {
  const _SoundButton({required this.muted, required this.onPressed});

  final bool muted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: muted ? 'Unmute' : 'Mute',
    onPressed: onPressed,
    icon: Icon(muted ? Icons.volume_off : Icons.volume_up, color: AppColors.onDark),
    style: IconButton.styleFrom(
      backgroundColor: Colors.black45,
      shape: const CircleBorder(),
    ),
  );
}
