import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../app_scope.dart';
import '../../navigation/app_route_observer.dart';
import '../models/app_player_controller.dart';
import 'platform_player_builder.dart';

/// Autoplaying, muted trailer preview used by hero surfaces.
class TrailerPreview extends StatefulWidget {
  const TrailerPreview({
    super.key,
    required this.trailer,
    this.playing = true,
    this.onPlayingChanged,
    this.onProgressChanged,
    this.onCompleted,
  });

  final MediaTrailer trailer;
  final bool playing;
  final ValueChanged<bool>? onPlayingChanged;
  final ValueChanged<double?>? onProgressChanged;
  final VoidCallback? onCompleted;

  @override
  State<TrailerPreview> createState() => _TrailerPreviewState();
}

class _TrailerPreviewState extends State<TrailerPreview> with RouteAware {
  static const _autoplayDelay = Duration(seconds: 1);
  static const _maxAutoplayDuration = Duration(seconds: 25);

  bool _ready = false;
  ModalRoute<void>? _route;
  bool _routeVisible = true;
  bool _playing = false;
  bool _completed = false;
  Timer? _autoplayTimer;
  Timer? _maxAutoplayTimer;
  AppPlayerController? _controller;
  StreamSubscription<AppPlayerEvent>? _eventsSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (route == null || route == _route) return;
    final previousRoute = _route;
    if (previousRoute != null) appRouteObserver.unsubscribe(this);
    _route = route;
    appRouteObserver.subscribe(this, route);
  }

  @override
  void didUpdateWidget(covariant TrailerPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trailer.url != widget.trailer.url) {
      _detachController();
      _maxAutoplayTimer?.cancel();
      _maxAutoplayTimer = null;
      _ready = false;
      _completed = false;
      widget.onProgressChanged?.call(null);
    }
    _syncPlayback();
  }

  void _onPlaybackReady(Object? controllerObject) {
    final controller = controllerObject as AppPlayerController?;
    if (controller != null && !identical(controller, _controller)) {
      _detachController();
      _controller = controller;
      controller.value.addListener(_onControllerValueChanged);
      _eventsSubscription = controller.events.listen((event) {
        if (identical(_controller, controller)) _onControllerEvent(event);
      });
      _onControllerValueChanged();
    }
    if (mounted) setState(() => _ready = true);
  }

  void _onControllerValueChanged() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value.value;
    final duration = value.duration;
    final progress =
        _playing &&
            value.isPlaying &&
            duration > Duration.zero &&
            value.position >= Duration.zero
        ? (value.position.inMilliseconds / duration.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble()
        : null;
    widget.onProgressChanged?.call(progress);
  }

  void _onControllerEvent(AppPlayerEvent event) {
    if (event.type != AppPlayerEventType.completed || !mounted) return;
    _completePreview();
  }

  void _completePreview() {
    if (!mounted) return;
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
    _maxAutoplayTimer?.cancel();
    _maxAutoplayTimer = null;
    setState(() {
      _playing = false;
      _completed = true;
    });
    widget.onPlayingChanged?.call(false);
    widget.onProgressChanged?.call(null);
    widget.onCompleted?.call();
  }

  void _detachController() {
    _controller?.value.removeListener(_onControllerValueChanged);
    unawaited(_eventsSubscription?.cancel());
    _eventsSubscription = null;
    _controller = null;
  }

  @override
  void didPushNext() {
    if (!mounted) return;
    setState(() {
      _routeVisible = false;
      _ready = false;
    });
    _syncPlayback();
  }

  @override
  void didPopNext() {
    if (!mounted) return;
    setState(() => _routeVisible = true);
    _syncPlayback();
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _maxAutoplayTimer?.cancel();
    _detachController();
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  bool _mayAutoplay() {
    final scope = AppScope.of(context);
    return scope.previewAutoplayPreferenceController.enabled &&
        widget.playing &&
        _routeVisible &&
        scope.pictureInPictureSession.player == null;
  }

  void _syncPlayback() {
    if (!mounted) return;
    if (!_mayAutoplay() || _completed) {
      _autoplayTimer?.cancel();
      _autoplayTimer = null;
      _maxAutoplayTimer?.cancel();
      _maxAutoplayTimer = null;
      if (_playing) {
        setState(() => _playing = false);
        widget.onPlayingChanged?.call(false);
      }
      widget.onProgressChanged?.call(null);
      return;
    }
    if (_playing || _autoplayTimer != null) return;
    _autoplayTimer = Timer(_autoplayDelay, () {
      _autoplayTimer = null;
      if (!mounted || !_mayAutoplay()) return;
      setState(() => _playing = true);
      widget.onPlayingChanged?.call(true);
      _maxAutoplayTimer = Timer(_maxAutoplayDuration, _onAutoplayLimitReached);
    });
  }

  void _onAutoplayLimitReached() {
    _maxAutoplayTimer = null;
    if (!mounted || !_playing) return;
    _completePreview();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).pictureInPictureSession;
    final preference = AppScope.of(context).previewAutoplayPreferenceController;
    return ListenableBuilder(
      listenable: Listenable.merge([session, preference]),
      builder: (context, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncPlayback());
        if (!_routeVisible) return const SizedBox.shrink();
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: _ready && !_completed ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return platformPlayerBuilder(
                  context,
                  PlayableStream(
                    url: widget.trailer.url,
                    label: widget.trailer.url,
                  ),
                  key: ValueKey(widget.trailer.url),
                  isLive: false,
                  // A full player attached to the session owns the only
                  // active playback session, including while it is in PiP.
                  playing: _playing,
                  preview: true,
                  muted: true,
                  looping: false,
                  fit: BoxFit.cover,
                  wakelock: false,
                  onPlaybackReady: _onPlaybackReady,
                );
              },
            ),
          ),
        );
      },
    );
  }
}
