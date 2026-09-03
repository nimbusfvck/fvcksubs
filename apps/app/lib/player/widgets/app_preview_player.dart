import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../app_scope.dart';
import '../models/app_player_controller.dart';
import '../youtube/youtube_preview_resolver.dart';
import 'platform_player_builder.dart';

/// Whether this app has an adapter for [provider]. Shared by
/// [AppPreviewPlayer]'s own resolution and by `ShortsController`, which
/// pre-filters a [PreviewResponse] to the first source this returns true
/// for before ever constructing a player — a single source of truth for
/// "which embed providers this app can actually play."
bool isSupportedPreviewProvider(String provider) => provider == 'youtube';

PlayerFitMode _playerFitModeOf(BoxFit fit) =>
    fit == BoxFit.cover ? PlayerFitMode.cover : PlayerFitMode.contain;

/// Renders one already-resolved [PlayableStream] as a preview: muted/looping
/// as requested, no transport controls, no subtitle/quality wiring — the
/// concerns full playback needs and previews don't.
typedef PreviewNativePlayerBuilder =
    Widget Function(
      BuildContext context,
      PlayableStream stream, {
      required bool muted,
      required bool looping,
      required bool playing,
      required BoxFit fit,
      Key? key,
      void Function(Object? controller)? onControllerCreated,
      void Function(Object? controller)? onPlaybackReady,
    });

/// Default [PreviewNativePlayerBuilder]: the same platform player builder
/// full playback uses (BetterPlayer on Android, video_player for Apple VOD,
/// MediaKit for Apple live),
/// fixed to preview mode rather than a second player stack.
Widget defaultPreviewNativePlayerBuilder(
  BuildContext context,
  PlayableStream stream, {
  required bool muted,
  required bool looping,
  required bool playing,
  required BoxFit fit,
  Key? key,
  void Function(Object? controller)? onControllerCreated,
  void Function(Object? controller)? onPlaybackReady,
}) => platformPlayerBuilder(
  context,
  stream,
  isLive: false,
  muted: muted,
  looping: looping,
  playing: playing,
  preview: true,
  // Unlike a decorative auto-loop preview, this player *is* the thing the
  // viewer is actively watching — keep the screen on while it plays.
  wakelock: true,
  // Lets the caller's own blurred backdrop show through a contain-fit
  // letterbox instead of opaque black bars.
  transparentBackground: true,
  fit: fit,
  onControllerCreated: onControllerCreated,
  onPlaybackReady: onPlaybackReady,
  key: key,
);

/// Resolves a [PreviewSource] just in time and renders it, delegating to the
/// existing platform player builder rather than a parallel player stack.
///
/// Preview and full playback are separate workflows (see
/// docs/14-shorts-preview-feed-plan.md §2.3): this never substitutes for the
/// app's source-discovery/resolve flow, and nothing it resolves is persisted.
class AppPreviewPlayer extends StatefulWidget {
  const AppPreviewPlayer({
    super.key,
    required this.source,
    required this.muted,
    required this.playing,
    this.fit = BoxFit.contain,
    this.onReady,
    this.onCompleted,
    this.onError,
    this.youtubeResolver = resolveYoutubePreviewStream,
  });

  /// The source to preview. Re-resolved whenever this changes.
  final PreviewSource source;

  /// Starts (and stays) muted until the caller flips this.
  final bool muted;

  /// Controls playback without discarding the resolved stream.
  final bool playing;

  /// How the video fills its layout bounds. Letterboxed by default per the
  /// source plan's "not aggressively cropped" guidance; a viewer can switch
  /// to fill via a fit toggle (Shorts wires this to [PlayerFitMode]).
  final BoxFit fit;

  /// Called once the native player reports it's ready to show frames.
  final void Function()? onReady;

  /// Called when the stream reaches its end. This player never loops —
  /// unlike a decorative background preview, a Shorts item's preview is a
  /// trailer that can run well past a native short clip's length, so the
  /// caller advancing to the next item reads better than looping it.
  final void Function()? onCompleted;

  /// Called when resolution fails, an unsupported embed provider is given,
  /// or the native player reports a fatal error. The Shorts workflow skips
  /// an item on this signal rather than surfacing an error card.
  final void Function(Object error)? onError;

  /// Injectable so tests can avoid a real network call.
  final Future<PlayableStream> Function(String videoId) youtubeResolver;

  @override
  State<AppPreviewPlayer> createState() => _AppPreviewPlayerState();
}

class _AppPreviewPlayerState extends State<AppPreviewPlayer> {
  PlayableStream? _resolvedStream;
  StreamSubscription<AppPlayerEvent>? _eventsSubscription;
  AppPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant AppPreviewPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _resolvedStream = null;
      _resolve();
      return;
    }
    // The native player widgets only read `fit` once, at construction —
    // same `source` means the same underlying player instance survives
    // this update (see the `ValueKey(source.id)` callers key it by), so a
    // fit change has to go through the live controller's own setFit,
    // exactly like the main player's own fit button does. Without this, a
    // toggle silently no-ops until a *different* source (a fresh player)
    // happens to pick up the new value at its own construction.
    if (oldWidget.fit != widget.fit) {
      unawaited(_controller?.setFit(_playerFitModeOf(widget.fit)));
    }
  }

  void _resolve() {
    final source = widget.source;
    switch (source) {
      case DirectPreviewSource(:final stream):
        // A plain field write, not setState: this runs synchronously from
        // initState or didUpdateWidget, both already inside a build the
        // framework scheduled for this element — calling setState here
        // would trip its "called during build" assertion.
        _resolvedStream = stream;
      case EmbeddedPreviewSource(:final provider, :final mediaId):
        if (!isSupportedPreviewProvider(provider)) {
          widget.onError?.call(
            UnsupportedError('Unsupported preview provider "$provider"'),
          );
          return;
        }
        widget
            .youtubeResolver(mediaId)
            .then((stream) {
              if (!mounted || widget.source != source) return;
              setState(() => _resolvedStream = stream);
            })
            .catchError((Object error) {
              if (!mounted || widget.source != source) return;
              widget.onError?.call(error);
            });
    }
  }

  void _onControllerCreated(Object? controller) {
    unawaited(_eventsSubscription?.cancel());
    _controller = controller as AppPlayerController?;
    _eventsSubscription = _controller?.events.listen((event) {
      if (!mounted) return;
      switch (event.type) {
        case AppPlayerEventType.error:
          widget.onError?.call(event.error ?? StateError('Playback failed'));
        case AppPlayerEventType.completed:
          widget.onCompleted?.call();
      }
    });
  }

  void _onPlaybackReady(Object? _) => widget.onReady?.call();

  @override
  void dispose() {
    unawaited(_eventsSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = _resolvedStream;
    if (stream == null) return const SizedBox.shrink();
    return AppScope.of(context).previewPlayerBuilder(
      context,
      stream,
      muted: widget.muted,
      looping: false,
      playing: widget.playing,
      fit: widget.fit,
      onControllerCreated: _onControllerCreated,
      onPlaybackReady: _onPlaybackReady,
    );
  }
}
