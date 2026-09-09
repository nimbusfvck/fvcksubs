import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../app_scope.dart';
import '../../navigation/app_route_observer.dart';
import 'platform_player_builder.dart';

/// Autoplaying, muted trailer preview used by hero surfaces.
class TrailerPreview extends StatefulWidget {
  const TrailerPreview({super.key, required this.trailer, this.playing = true});

  final MediaTrailer trailer;
  final bool playing;

  @override
  State<TrailerPreview> createState() => _TrailerPreviewState();
}

class _TrailerPreviewState extends State<TrailerPreview> with RouteAware {
  static const _autoplayDelay = Duration(seconds: 1);
  static const _maximumPlayback = Duration(seconds: 20);

  bool _ready = false;
  ModalRoute<void>? _route;
  bool _routeVisible = true;
  bool _playing = false;
  bool _budgetExhausted = false;
  Timer? _autoplayTimer;
  Timer? _playbackTimer;

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
      _ready = false;
      _budgetExhausted = false;
    }
    _syncPlayback();
  }

  void _onPlaybackReady(Object? _) {
    if (mounted) setState(() => _ready = true);
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
    _playbackTimer?.cancel();
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  bool _mayAutoplay() {
    final scope = AppScope.of(context);
    return scope.previewAutoplayPreferenceController.enabled &&
        widget.playing &&
        _routeVisible &&
        scope.pictureInPictureSession.player == null &&
        !_budgetExhausted;
  }

  void _syncPlayback() {
    if (!mounted) return;
    if (!_mayAutoplay()) {
      _autoplayTimer?.cancel();
      _autoplayTimer = null;
      _playbackTimer?.cancel();
      _playbackTimer = null;
      if (_playing) setState(() => _playing = false);
      return;
    }
    if (_playing || _autoplayTimer != null) return;
    _autoplayTimer = Timer(_autoplayDelay, () {
      _autoplayTimer = null;
      if (!mounted || !_mayAutoplay()) return;
      setState(() => _playing = true);
      _playbackTimer = Timer(_maximumPlayback, () {
        _playbackTimer = null;
        if (!mounted) return;
        setState(() {
          _playing = false;
          _ready = false;
          _budgetExhausted = true;
        });
      });
    });
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
            opacity: _ready ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return platformPlayerBuilder(
                  context,
                  PlayableStream(
                    url: widget.trailer.url,
                    label: widget.trailer.url,
                  ),
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
