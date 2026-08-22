import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../../navigation/app_route_observer.dart';
import 'stream_player.dart';

/// Autoplaying, muted trailer preview used by hero surfaces.
class TrailerPreview extends StatefulWidget {
  const TrailerPreview({super.key, required this.trailer, this.playing = true});

  final MediaTrailer trailer;
  final bool playing;

  @override
  State<TrailerPreview> createState() => _TrailerPreviewState();
}

class _TrailerPreviewState extends State<TrailerPreview> with RouteAware {
  bool _ready = false;
  ModalRoute<void>? _route;
  bool _routeVisible = true;

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
    }
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
  }

  @override
  void didPopNext() {
    if (!mounted) return;
    setState(() => _routeVisible = true);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_routeVisible) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _ready ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final aspectRatio = constraints.maxHeight <= 0
                ? 16 / 9
                : constraints.maxWidth / constraints.maxHeight;
            return BetterPlayerView(
              stream: PlayableStream(
                url: widget.trailer.url,
                label: widget.trailer.url,
              ),
              aspectRatio: aspectRatio,
              looping: true,
              muted: true,
              fit: BoxFit.cover,
              playing: widget.playing,
              preview: true,
              isLive: false,
              onPlaybackReady: _onPlaybackReady,
            );
          },
        ),
      ),
    );
  }
}
