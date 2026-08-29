import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../app_scope.dart';
import '../models/app_player_controller.dart';
import '../youtube/youtube_preview_resolver.dart';
import 'platform_player_builder.dart';

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
      Key? key,
      void Function(Object? controller)? onControllerCreated,
      void Function(Object? controller)? onPlaybackReady,
    });

/// Default [PreviewNativePlayerBuilder]: the same platform player builder
/// full playback uses (BetterPlayer on Android, MediaKit on iOS/macOS),
/// fixed to preview mode rather than a second player stack.
Widget defaultPreviewNativePlayerBuilder(
  BuildContext context,
  PlayableStream stream, {
  required bool muted,
  required bool looping,
  required bool playing,
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
  fit: BoxFit.contain,
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
    this.onReady,
    this.onError,
    this.youtubeResolver = resolveYoutubePreviewStream,
  });

  /// The source to preview. Re-resolved whenever this changes.
  final PreviewSource source;

  /// Starts (and stays) muted until the caller flips this.
  final bool muted;

  /// Controls playback without discarding the resolved stream.
  final bool playing;

  /// Called once the native player reports it's ready to show frames.
  final void Function()? onReady;

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
        if (provider != 'youtube') {
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
    _eventsSubscription = (controller as AppPlayerController?)?.events.listen((
      event,
    ) {
      if (!mounted) return;
      if (event.type == AppPlayerEventType.error) {
        widget.onError?.call(event.error ?? StateError('Playback failed'));
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
      looping: true,
      playing: widget.playing,
      onControllerCreated: _onControllerCreated,
      onPlaybackReady: _onPlaybackReady,
    );
  }
}
