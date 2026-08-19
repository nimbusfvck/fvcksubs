import 'package:equatable/equatable.dart';

import 'media_item.dart';
import 'media_item_v2.dart';
import 'media_ref.dart';

/// A protocol item decoded into the strict version-2 in-memory model.
///
/// [legacyItem] is retained only for calls back into a version-1 extension.
/// This keeps provider-owned payload data intact without exposing it through
/// the version-2 item contract.
class VersionedMediaItem extends Equatable {
  /// Creates an item envelope.
  const VersionedMediaItem({required this.item, this.legacyItem});

  /// Decodes an item according to the extension's declared API version.
  factory VersionedMediaItem.fromProtocolJson(
    Map<String, Object?> json, {
    required int apiVersion,
  }) {
    return switch (apiVersion) {
      1 => VersionedMediaItem.fromV1(MediaItem.fromJson(json)),
      2 => VersionedMediaItem(item: MediaItemV2.fromJson(json)),
      _ => throw FormatException(
        'Unsupported media item apiVersion: $apiVersion',
      ),
    };
  }

  /// Restores an envelope saved by [toJson].
  factory VersionedMediaItem.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {'item', 'legacyItem'}, 'versioned media item');
    final item = json['item'];
    final legacy = json['legacyItem'];
    if (item is! Map) {
      throw const FormatException(
        'versioned media item.item must be an object',
      );
    }
    if (legacy != null && legacy is! Map) {
      throw const FormatException(
        'versioned media item.legacyItem must be an object',
      );
    }
    return VersionedMediaItem(
      item: MediaItemV2.fromJson(item.cast<String, Object?>()),
      legacyItem: legacy == null
          ? null
          : MediaItem.fromJson((legacy as Map).cast<String, Object?>()),
    );
  }

  /// Converts a version-1 item while preserving its original payload.
  factory VersionedMediaItem.fromV1(MediaItem legacy) => VersionedMediaItem(
    item: _V1MediaItemAdapter.convert(legacy),
    legacyItem: legacy,
  );

  /// Strict item used by version-2 app consumers.
  final MediaItemV2 item;

  /// Original version-1 item, when this envelope came from a v1 extension.
  final MediaItem? legacyItem;

  /// Whether calls to the owning extension require the legacy payload.
  bool get requiresLegacyRequest => legacyItem != null;

  /// Returns the original v1 item for a call into a v1 extension.
  MediaItem requestItemForV1() {
    final value = legacyItem;
    if (value == null) {
      throw StateError('A protocol-v2 item has no version-1 request payload');
    }
    return value;
  }

  /// Encodes the envelope for persistence during the compatibility period.
  Map<String, Object?> toJson() => {
    'item': item.toJson(),
    if (legacyItem != null) 'legacyItem': legacyItem!.toJson(),
  };

  @override
  List<Object?> get props => [item, legacyItem];
}

final class _V1MediaItemAdapter {
  const _V1MediaItemAdapter._();

  static MediaItemV2 convert(MediaItem legacy) {
    _validateVariantFields(legacy);
    final artwork = _artworkOf(legacy);
    return switch (legacy.kind) {
      MediaKind.movie => VideoItemV2(
        ref: legacy.ref,
        title: legacy.title,
        subtitle: legacy.subtitle,
        artwork: artwork,
      ),
      MediaKind.series => SeriesItemV2(
        ref: legacy.ref,
        title: legacy.title,
        subtitle: legacy.subtitle,
        artwork: artwork,
      ),
      MediaKind.channel => ChannelItemV2(
        ref: legacy.ref,
        title: legacy.title,
        subtitle: legacy.subtitle,
        artwork: artwork,
      ),
      MediaKind.episode => _episodeOf(legacy, artwork),
      MediaKind.liveEvent => _eventOf(legacy, artwork),
    };
  }

  static Artwork? _artworkOf(MediaItem legacy) {
    if (legacy.poster == null && legacy.thumbnail == null) return null;
    return Artwork(portrait: legacy.poster, landscape: legacy.thumbnail);
  }

  static EpisodeItemV2 _episodeOf(MediaItem legacy, Artwork? artwork) {
    final season = legacy.extra['season'];
    final episode = legacy.extra['episode'];
    if (season is! int || season < 0) {
      throw const FormatException(
        'A version-1 episode requires a non-negative integer extra.season',
      );
    }
    if (episode is! int || episode < 1) {
      throw const FormatException(
        'A version-1 episode requires a positive integer extra.episode',
      );
    }
    final groupId = 'season:$season';
    return EpisodeItemV2(
      ref: MediaRef(
        extensionId: legacy.ref.extensionId,
        providerId: legacy.ref.providerId,
        id: _episodeId(legacy.ref.id, groupId, episode),
      ),
      title: legacy.title,
      subtitle: legacy.subtitle,
      artwork: artwork,
      episode: EpisodeIdentity(
        parentRef: legacy.ref,
        groupId: groupId,
        position: episode,
      ),
    );
  }

  static EventItemV2 _eventOf(MediaItem legacy, Artwork? artwork) {
    final startsAt = legacy.startsAt;
    if (startsAt == null) {
      throw const FormatException(
        'A version-1 liveEvent requires startsAt before migration to v2',
      );
    }
    return EventItemV2(
      ref: legacy.ref,
      title: legacy.title,
      subtitle: legacy.subtitle,
      artwork: artwork,
      schedule: Schedule(
        startsAt: startsAt.toUtc(),
        state: switch (legacy.status) {
          LiveStatus.scheduled => ScheduleState.scheduled,
          LiveStatus.live => ScheduleState.live,
          LiveStatus.ended => ScheduleState.ended,
          LiveStatus.unknown => ScheduleState.unknown,
        },
        label: legacy.statusLabel,
      ),
      participants: legacy.participants,
    );
  }

  static void _validateVariantFields(MediaItem legacy) {
    if (legacy.kind == MediaKind.liveEvent) return;
    if (legacy.startsAt != null) {
      throw FormatException(
        'Version-1 ${legacy.kind.name} cannot migrate with startsAt',
      );
    }
    if (legacy.status != LiveStatus.unknown || legacy.statusLabel != null) {
      throw FormatException(
        'Version-1 ${legacy.kind.name} cannot migrate with live status data',
      );
    }
    if (legacy.participants.isNotEmpty) {
      throw FormatException(
        'Version-1 ${legacy.kind.name} cannot migrate with participants',
      );
    }
  }

  static String _episodeId(String parentId, String groupId, int position) =>
      'v1-episode:${Uri.encodeComponent(parentId)}:'
      '${Uri.encodeComponent(groupId)}:$position';
}

void _expectKeys(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$path contains unsupported field "$key"');
    }
  }
}
