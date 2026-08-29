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
/// (BetterPlayer on Android, MediaKit on iOS/macOS) already play HLS
/// natively; a plain muxed MP4 is the second choice. Separate video+audio is
/// the last resort — it plays correctly on MediaKit (which applies
/// [PlayableStream.audioUrl] as a second track) but silently, video-only, on
/// BetterPlayer, which has no equivalent for a second audio URL.
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
      url: hlsMuxed.bestQuality.url.toString(),
      format: StreamFormat.hls,
    );
  }

  if (manifest.muxed.isNotEmpty) {
    return PlayableStream(
      url: manifest.muxed.bestQuality.url.toString(),
      format: StreamFormat.other,
    );
  }

  if (manifest.videoOnly.isNotEmpty && manifest.audioOnly.isNotEmpty) {
    return PlayableStream(
      url: manifest.videoOnly.bestQuality.url.toString(),
      audioUrl: manifest.audioOnly.withHighestBitrate().url.toString(),
      format: StreamFormat.other,
    );
  }

  throw StateError('No playable preview stream found for video $videoId');
}
