import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'stream_player.dart';

/// Autoplaying, muted trailer preview used by hero surfaces.
class TrailerPreview extends StatefulWidget {
  const TrailerPreview({super.key, required this.trailer});

  final MediaTrailer trailer;

  @override
  State<TrailerPreview> createState() => _TrailerPreviewState();
}

class _TrailerPreviewState extends State<TrailerPreview> {
  bool _ready = false;

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
  Widget build(BuildContext context) => IgnorePointer(
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
            isLive: false,
            onPlaybackReady: _onPlaybackReady,
          );
        },
      ),
    ),
  );
}
