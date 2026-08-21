import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'stream_player.dart';

/// Autoplaying, muted trailer preview used by hero surfaces.
class TrailerPreview extends StatelessWidget {
  const TrailerPreview({super.key, required this.trailer});

  final MediaTrailer trailer;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio = constraints.maxHeight <= 0
            ? 16 / 9
            : constraints.maxWidth / constraints.maxHeight;
        return BetterPlayerView(
          stream: PlayableStream(url: trailer.url, label: trailer.url),
          aspectRatio: aspectRatio,
          looping: true,
          muted: true,
          fit: BoxFit.cover,
          isLive: false,
        );
      },
    ),
  );
}
