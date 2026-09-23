import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../models/app_player_controller.dart';
import '../state/quality_preference_controller.dart';

StreamVariant? preferredStartupVariant(PlayableStream stream, int? maxHeight) =>
    preferredQualityTrack(
      maxHeight: maxHeight,
      tracks: [
        for (final variant in stream.variants)
          AppQualityTrack(
            id: variant.id,
            height: variant.height ?? 0,
            width: variant.width,
            bitrate: variant.bitrate,
            variant: variant,
          ),
      ],
    )?.variant;

PlayableStream streamForVariant(
  PlayableStream stream,
  StreamVariant? variant,
) => variant == null
    ? stream
    : PlayableStream(
      url: variant.url,
      headers: variant.headers.isEmpty ? stream.headers : variant.headers,
      playlistHeaders: stream.playlistHeaders,
      segmentHeaders: stream.segmentHeaders,
      format: variant.format,
        drm: stream.drm,
        audioUrl: stream.audioUrl,
        label: variant.label,
        subtitles: stream.subtitles,
        variants: stream.variants,
      );
