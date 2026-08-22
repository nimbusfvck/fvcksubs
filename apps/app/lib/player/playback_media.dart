import 'package:fvcksubs_core/fvcksubs_core.dart';

/// App-facing playback identity shared by protocol migrations.
class PlaybackMedia {
  const PlaybackMedia.legacy(MediaItem item) : legacyItem = item, v2Item = null;

  const PlaybackMedia.v2(MediaItemV2 item) : legacyItem = null, v2Item = item;

  final MediaItem? legacyItem;
  final MediaItemV2? v2Item;

  MediaRef get ref => legacyItem?.ref ?? v2Item!.ref;

  String get title => legacyItem?.title ?? v2Item!.title;

  /// Whether the current playback item is an episode of an episodic title.
  bool get isEpisode =>
      legacyItem?.kind == MediaKind.episode || v2Item is EpisodeItemV2;

  bool get isLive {
    final legacy = legacyItem;
    if (legacy != null) {
      return legacy.kind == MediaKind.liveEvent ||
          legacy.kind == MediaKind.channel;
    }
    return v2Item is EventItemV2 || v2Item is ChannelItemV2;
  }
}
