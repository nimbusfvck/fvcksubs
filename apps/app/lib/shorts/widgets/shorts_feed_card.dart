import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../app_scope.dart';
import '../../catalog/artwork_placeholder.dart';
import '../../library/library_controller.dart';
import '../../player/models/app_player_controller.dart';
import '../../player/widgets/app_preview_player.dart';
import '../../player/widgets/player_fit_button.dart';
import '../../theme/tokens.dart';
import '../../utils/date_formatters.dart';
import '../shorts_primary_action.dart';
import '../shorts_state.dart';

/// One Shorts feed item: preview player (or artwork while it initializes),
/// tap-to-pause/play with a brief center icon flash, hold-to-peek-pause
/// (releases back into play), title/kind/date/rating/synopsis, and a
/// right-side action rail (Watch/Remind Me, Favorite, Audio) — the same
/// layout shorts-style feeds elsewhere use. No transport controls — per
/// source plan §5, this is a preview surface, not the full player.
class ShortsFeedCard extends StatefulWidget {
  const ShortsFeedCard({
    super.key,
    required this.item,
    required this.detail,
    required this.previewResolution,
    required this.muted,
    required this.playing,
    required this.fit,
    required this.onToggleMute,
    required this.onToggleFit,
    required this.onReady,
    required this.onError,
    required this.onWatch,
  });

  final MediaItemV2 item;
  final MediaDetailV2? detail;
  final PreviewResolution previewResolution;
  final bool muted;

  /// Whether this card is the active page — the precondition for playing at
  /// all. Combined internally with the viewer's own pause/hold gestures.
  final bool playing;

  /// Session-wide fill mode, set by [ShortsPage] — persists across cards
  /// the same way [muted] does.
  final PlayerFitMode fit;

  final VoidCallback onToggleMute;
  final VoidCallback onToggleFit;
  final VoidCallback onReady;
  final void Function(Object error) onError;
  final VoidCallback onWatch;

  @override
  State<ShortsFeedCard> createState() => _ShortsFeedCardState();
}

class _ShortsFeedCardState extends State<ShortsFeedCard>
    with SingleTickerProviderStateMixin {
  bool _paused = false;
  late final AnimationController _flashController;
  late final Animation<double> _flashOpacity;
  IconData _flashIcon = Icons.pause_rounded;
  int _flashGeneration = 0;

  static const _flashHold = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _flashOpacity = CurvedAnimation(parent: _flashController, curve: Curves.easeOut);
  }

  @override
  void didUpdateWidget(covariant ShortsFeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A card becoming active again (e.g. swiped back to) starts fresh
    // rather than remembering a pause from a previous visit.
    if (widget.playing && !oldWidget.playing) {
      _paused = false;
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  /// Appears quickly, holds, then fades — a flash, not a persistent panel.
  /// Guarded by [_flashGeneration] so a rapid second tap's flash cannot be
  /// cut short by the first flash's delayed reverse firing late.
  void _flash(IconData icon) {
    final generation = ++_flashGeneration;
    setState(() => _flashIcon = icon);
    _flashController.stop();
    unawaited(
      _flashController.forward(from: 0).whenComplete(() async {
        await Future<void>.delayed(_flashHold);
        if (mounted && generation == _flashGeneration) {
          unawaited(_flashController.reverse());
        }
      }),
    );
  }

  void _handleTap() {
    setState(() => _paused = !_paused);
    _flash(_paused ? Icons.pause_rounded : Icons.play_arrow_rounded);
  }

  void _handleLongPressStart(LongPressStartDetails _) {
    if (_paused) return;
    setState(() => _paused = true);
  }

  void _handleLongPressEnd(LongPressEndDetails _) {
    setState(() => _paused = false);
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.previewResolution.source;
    final artwork = widget.item.artwork?.portrait ?? widget.item.artwork?.landscape;
    final effectivePlaying = widget.playing && !_paused;
    final boxFit = widget.fit == PlayerFitMode.cover ? BoxFit.cover : BoxFit.contain;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (artwork != null)
            CachedNetworkImage(
              imageUrl: artwork.url,
              fit: boxFit,
              fadeInDuration: Duration.zero,
              placeholder: (_, _) => const ArtworkPlaceholder(),
              errorWidget: (_, _, _) => const ArtworkPlaceholder(),
            )
          else
            const ArtworkPlaceholder(),
          if (widget.previewResolution.status == PreviewStatus.usable && source != null)
            AppPreviewPlayer(
              key: ValueKey(source.id),
              source: source,
              muted: widget.muted,
              playing: effectivePlaying,
              fit: boxFit,
              onReady: widget.onReady,
              onError: widget.onError,
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
          // Tap to pause/play; hold to peek-pause and resume on release.
          // Placed ahead of the rail/text below in paint order, so those
          // get first claim on their own taps — Stack hit-tests the last
          // child first, and an opaque IconButton there absorbs its own tap
          // before it ever reaches this full-bleed layer underneath.
          //
          // Deliberately no onLongPressCancel: Flutter's long-press
          // recognizer starts tracking on every pointer-down and fires
          // *cancel* whenever it loses the arena to the tap recognizer —
          // i.e. on every ordinary quick tap, not just an interrupted
          // hold. Wiring it to un-pause raced _handleTap's own toggle and
          // made every tap pause without ever being able to resume.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleTap,
              onLongPressStart: _handleLongPressStart,
              onLongPressEnd: _handleLongPressEnd,
            ),
          ),
          IgnorePointer(
            child: Center(
              child: FadeTransition(
                opacity: _flashOpacity,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Icon(_flashIcon, color: AppColors.onDark, size: 40),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: PlayerFitButton(mode: widget.fit, onToggle: widget.onToggleFit),
                ),
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: _InfoOverlay(item: widget.item, detail: widget.detail)),
                const SizedBox(width: AppSpacing.sm),
                _ActionRail(
                  item: widget.item,
                  detail: widget.detail,
                  muted: widget.muted,
                  onWatch: widget.onWatch,
                  onToggleMute: widget.onToggleMute,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoOverlay extends StatelessWidget {
  const _InfoOverlay({required this.item, required this.detail});

  final MediaItemV2 item;
  final MediaDetailV2? detail;

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

/// Vertical Watch/Remind Me, Favorite, Audio rail anchored to the right
/// edge, matching how other shorts-style feeds place their actions.
class _ActionRail extends StatelessWidget {
  const _ActionRail({
    required this.item,
    required this.detail,
    required this.muted,
    required this.onWatch,
    required this.onToggleMute,
  });

  final MediaItemV2 item;
  final MediaDetailV2? detail;
  final bool muted;
  final VoidCallback onWatch;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final libraryController = AppScope.of(context).libraryController;
    return BlocBuilder<LibraryController, LibraryState>(
      bloc: libraryController,
      builder: (context, library) {
        final action = primaryActionFor(item, detail: detail, library: library);
        final isRemindMe = action.kind == ShortsActionKind.remindMe;
        final reminded = library.isReminded(item.ref);
        final favoriteActive = library.isFavorite(item.ref);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RailAction(
              icon: _iconFor(action.kind, reminded),
              label: isRemindMe && reminded ? 'Reminder Set' : action.label,
              tooltip: isRemindMe && reminded ? 'Reminder set' : action.label,
              onTap: isRemindMe ? () => libraryController.toggleReminder(item) : onWatch,
            ),
            const SizedBox(height: AppSpacing.md),
            _RailAction(
              icon: favoriteActive ? Icons.check : Icons.add,
              label: 'Favorite',
              tooltip: favoriteActive ? 'In favorites' : 'Add to favorites',
              onTap: () => libraryController.toggleFavorite(item),
            ),
            const SizedBox(height: AppSpacing.md),
            _RailAction(
              icon: muted ? Icons.volume_off : Icons.volume_up,
              label: 'Audio',
              tooltip: muted ? 'Unmute' : 'Mute',
              onTap: onToggleMute,
            ),
          ],
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

class _RailAction extends StatelessWidget {
  const _RailAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 26),
        style: IconButton.styleFrom(
          foregroundColor: AppColors.onDark,
          backgroundColor: Colors.black45,
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(10),
        ),
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.onDark,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
        ),
      ),
    ],
  );
}
