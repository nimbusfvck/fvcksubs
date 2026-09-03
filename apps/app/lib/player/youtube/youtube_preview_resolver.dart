import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Resolves a YouTube video id into a short-lived [PlayableStream].
///
/// Never persisted by callers — every retry must call this again, since the
/// resolved URL may be signed or expire (see
/// docs/14-shorts-preview-feed-plan.md §2.4/§3). Uses the `visionos`
/// InnerTube client: the upstream `youtube_explode_dart` release fails
/// bot-detection reliably on every other client, a spoofed visionOS client is
/// what this app's fork commit adds specifically to dodge that.
///
/// YouTube never returns a muxed MP4 for this client — only separate
/// video-only + audio-only streams, or HLS. A muxed HLS stream is preferred
/// because it carries audio and video together and both native players
/// (BetterPlayer on Android, video_player on Apple VOD) already play HLS
/// natively; a plain muxed MP4 is the second choice. Separate video+audio is
/// the last resort — it plays correctly on MediaKit (which applies
/// [PlayableStream.audioUrl] as a second track) while the Apple video_player
/// route deliberately falls back to MediaKit rather than dropping the audio.
Future<PlayableStream> resolveYoutubePreviewStream(String videoId) async {
  final youtube = YoutubeExplode();
  try {
    final manifest = await youtube.videos.streams.getManifest(
      videoId,
      ytClients: [YoutubeApiClient.visionos],
    );
    return selectPreviewStream(manifest, videoId: videoId);
  } finally {
    youtube.close();
  }
}

/// A Shorts card is a small vertical tile, not a full-screen player — no
/// need to pull a 1080p/4K stream for it. Caps at 480p, the highest quality
/// still at or under that; a video with nothing that low falls back to
/// whatever its smallest available quality is, rather than the highest.
const _maxPreviewHeight = 480;

T _lightestFittingQuality<T extends VideoStreamInfo>(List<T> streams) {
  final byQuality = streams.toList()
    ..sort((a, b) => a.videoResolution.compareTo(b.videoResolution));
  final withinCap = byQuality.where(
    (s) => s.videoResolution.height <= _maxPreviewHeight,
  );
  return withinCap.isNotEmpty ? withinCap.last : byQuality.first;
}

/// Picks the preview stream from an already-resolved [manifest]. Pulled out
/// of [resolveYoutubePreviewStream] so the tier order (HLS muxed > muxed MP4
/// > separate video+audio) is testable without a network call.
@visibleForTesting
PlayableStream selectPreviewStream(
  StreamManifest manifest, {
  required String videoId,
}) {
  final hlsMuxed = manifest.hls.whereType<HlsMuxedStreamInfo>().toList();
  if (hlsMuxed.isNotEmpty) {
    return PlayableStream(
      url: _lightestFittingQuality(hlsMuxed).url.toString(),
      format: StreamFormat.hls,
    );
  }

  if (manifest.muxed.isNotEmpty) {
    return PlayableStream(
      url: _lightestFittingQuality(manifest.muxed).url.toString(),
      format: StreamFormat.other,
    );
  }

  if (manifest.videoOnly.isNotEmpty && manifest.audioOnly.isNotEmpty) {
    return PlayableStream(
      url: _lightestFittingQuality(manifest.videoOnly).url.toString(),
      audioUrl: manifest.audioOnly.withHighestBitrate().url.toString(),
      format: StreamFormat.other,
    );
  }

  throw StateError('No playable preview stream found for video $videoId');
}
