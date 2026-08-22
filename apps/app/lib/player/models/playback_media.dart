import 'package:fvcksubs_core/fvcksubs_core.dart';

/// App-facing playback identity used by the protocol-v2 player flow.
class PlaybackMedia {
  const PlaybackMedia(this.item);

  final MediaItemV2 item;

  MediaRef get ref => item.ref;

  String get title => item.title;

  /// Whether the current playback item is an episode of an episodic title.
  bool get isEpisode => item is EpisodeItemV2;

  bool get isLive => item is EventItemV2 || item is ChannelItemV2;
}
