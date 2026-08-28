import 'package:equatable/equatable.dart';

import '../json_util.dart';
import 'image_ref.dart';
import 'media_ref.dart';
import 'participant.dart';

/// The content shapes supported by protocol version 2.
enum MediaKindV2 {
  /// Standalone playable video.
  video,

  /// Collection containing episodes.
  series,

  /// Individually addressable episode.
  episode,

  /// Continuously available channel.
  channel,

  /// Scheduled or live event.
  event,
}

/// A scheduled item's lifecycle state.
enum ScheduleState {
  /// The event has not started.
  scheduled,

  /// The event is in progress.
  live,

  /// The event has finished.
  ended,

  /// No reliable lifecycle state is available.
  unknown,
}

/// Artwork grouped by its intended shape.
class Artwork extends Equatable {
  /// Creates artwork. At least one image must be present at the JSON boundary.
  const Artwork({this.portrait, this.landscape, this.logo});

  /// Decodes and validates artwork.
  factory Artwork.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {'portrait', 'landscape', 'logo'}, 'artwork');
    final artwork = Artwork(
      portrait: _imageFromJson(json['portrait'], 'artwork.portrait'),
      landscape: _imageFromJson(json['landscape'], 'artwork.landscape'),
      logo: _imageFromJson(json['logo'], 'artwork.logo'),
    );
    if (artwork.portrait == null &&
        artwork.landscape == null &&
        artwork.logo == null) {
      throw const FormatException('artwork must contain at least one image');
    }
    return artwork;
  }

  /// Portrait image for narrow cards.
  final ImageRef? portrait;

  /// Landscape image for wide cards and detail headers.
  final ImageRef? landscape;

  /// Optional title or brand mark.
  final ImageRef? logo;

  /// Encodes this artwork.
  Map<String, Object?> toJson() => {
    if (portrait != null) 'portrait': portrait!.toJson(),
    if (landscape != null) 'landscape': landscape!.toJson(),
    if (logo != null) 'logo': logo!.toJson(),
  };

  @override
  List<Object?> get props => [portrait, landscape, logo];
}

/// Schedule data available only on an [EventItemV2].
class Schedule extends Equatable {
  /// Creates a schedule.
  const Schedule({
    required this.startsAt,
    this.state = ScheduleState.unknown,
    this.label,
  });

  /// Decodes and validates a schedule.
  factory Schedule.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {'startsAt', 'state', 'label'}, 'schedule');
    final rawStartsAt = json['startsAt'];
    if (rawStartsAt is! String) {
      throw const FormatException('schedule.startsAt must be a string');
    }
    final parsed = DateTime.tryParse(rawStartsAt);
    if (parsed == null || !rawStartsAt.toUpperCase().endsWith('Z')) {
      throw const FormatException(
        'schedule.startsAt must be an ISO-8601 UTC timestamp',
      );
    }
    final label = json['label'];
    if (label != null && label is! String) {
      throw const FormatException('schedule.label must be a string');
    }
    return Schedule(
      startsAt: parsed,
      state: enumByName(
        ScheduleState.values,
        json['state'],
        orElse: ScheduleState.unknown,
      ),
      label: label as String?,
    );
  }

  /// Event start in UTC.
  final DateTime startsAt;

  /// Machine-readable lifecycle state.
  final ScheduleState state;

  /// Optional short status rendered verbatim.
  final String? label;

  /// Encodes this schedule.
  Map<String, Object?> toJson() => {
    'startsAt': startsAt.toUtc().toIso8601String(),
    'state': state.name,
    if (label != null) 'label': label,
  };

  @override
  List<Object?> get props => [startsAt, state, label];
}

/// Typed navigation context for an episode.
class EpisodeIdentity extends Equatable {
  /// Creates episode identity.
  const EpisodeIdentity({
    required this.parentRef,
    required this.groupId,
    required this.position,
  });

  /// Decodes and validates episode identity.
  factory EpisodeIdentity.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {'parentRef', 'groupId', 'position'}, 'episode');
    final groupId = json['groupId'];
    final position = json['position'];
    if (groupId is! String || groupId.isEmpty) {
      throw const FormatException('episode.groupId must be a non-empty string');
    }
    if (position is! num || position.toInt() != position || position < 1) {
      throw const FormatException(
        'episode.position must be a positive integer',
      );
    }
    final parent = json['parentRef'];
    if (parent is! Map) {
      throw const FormatException('episode.parentRef must be an object');
    }
    return EpisodeIdentity(
      parentRef: MediaRef.fromJson(parent.cast<String, Object?>()),
      groupId: groupId,
      position: position.toInt(),
    );
  }

  /// Series or collection containing the episode.
  final MediaRef parentRef;

  /// Opaque group ID supplied by the extension.
  final String groupId;

  /// One-based display position within the group.
  final int position;

  /// Encodes this identity.
  Map<String, Object?> toJson() => {
    'parentRef': parentRef.toJson(),
    'groupId': groupId,
    'position': position,
  };

  @override
  List<Object?> get props => [parentRef, groupId, position];
}

/// Strict protocol-v2 catalog item.
///
/// Use [MediaItemV2.fromJson] at the extension boundary. It rejects fields
/// that do not belong to the selected [kind].
sealed class MediaItemV2 extends Equatable {
  const MediaItemV2({
    required this.ref,
    required this.title,
    this.subtitle,
    this.releaseYear,
    this.releaseDate,
    this.rating,
    this.artwork,
  });

  /// Decodes the item variant selected by `kind`.
  factory MediaItemV2.fromJson(Map<String, Object?> json) {
    final kind = enumByNameStrict(MediaKindV2.values, json['kind']);
    final common = _CommonItemFields.fromJson(json);
    switch (kind) {
      case MediaKindV2.video:
        _rejectUnknown(json, _baseKeys, 'video item');
        return VideoItemV2._fromCommon(common);
      case MediaKindV2.series:
        _rejectUnknown(json, _baseKeys, 'series item');
        return SeriesItemV2._fromCommon(common);
      case MediaKindV2.channel:
        _rejectUnknown(json, _baseKeys, 'channel item');
        return ChannelItemV2._fromCommon(common);
      case MediaKindV2.episode:
        _rejectUnknown(json, {
          ..._baseKeys,
          'episode',
          'availableAt',
        }, 'episode item');
        final episode = json['episode'];
        if (episode is! Map) {
          throw const FormatException('episode item requires episode data');
        }
        final availableAt = json['availableAt'];
        DateTime? parsedAvailableAt;
        if (availableAt != null) {
          parsedAvailableAt = availableAt is String
              ? DateTime.tryParse(availableAt)
              : null;
          if (parsedAvailableAt == null ||
              !(availableAt as String).toUpperCase().endsWith('Z')) {
            throw const FormatException(
              'item.availableAt must be an ISO-8601 UTC timestamp',
            );
          }
        }
        return EpisodeItemV2._fromCommon(
          common,
          EpisodeIdentity.fromJson(episode.cast<String, Object?>()),
          parsedAvailableAt,
        );
      case MediaKindV2.event:
        _rejectUnknown(json, {
          ..._baseKeys,
          'schedule',
          'participants',
        }, 'event item');
        final schedule = json['schedule'];
        if (schedule is! Map) {
          throw const FormatException('event item requires a schedule');
        }
        final participants = json['participants'];
        if (participants != null && participants is! List) {
          throw const FormatException('event participants must be a list');
        }
        return EventItemV2._fromCommon(
          common,
          schedule: Schedule.fromJson(schedule.cast<String, Object?>()),
          participants: [
            for (final entry in (participants as List?) ?? const [])
              Participant.fromJson((entry as Map).cast<String, Object?>()),
          ],
        );
    }
  }

  /// Stable item identity.
  final MediaRef ref;

  /// Primary display title.
  final String title;

  /// Optional secondary display text.
  final String? subtitle;

  /// Calendar year in which this item was first released.
  final int? releaseYear;

  /// When this item first becomes (or became) available, from the
  /// extension. A future value marks it as not yet released.
  final DateTime? releaseDate;

  /// Extension-supplied audience or editorial rating.
  final double? rating;

  /// Optional artwork grouped by orientation.
  final Artwork? artwork;

  /// This item's strict variant.
  MediaKindV2 get kind;

  /// Whether [releaseDate] is known and still in the future.
  bool get isUpcoming =>
      releaseDate != null && releaseDate!.isAfter(DateTime.now().toUtc());

  Map<String, Object?> _baseJson() => {
    'ref': ref.toJson(),
    'kind': kind.name,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (releaseYear != null) 'releaseYear': releaseYear,
    if (releaseDate != null)
      'releaseDate': releaseDate!.toUtc().toIso8601String(),
    if (rating != null) 'rating': rating,
    if (artwork != null) 'artwork': artwork!.toJson(),
  };

  /// Encodes the selected variant.
  Map<String, Object?> toJson();

  @override
  List<Object?> get props => [
    ref,
    kind,
    title,
    subtitle,
    releaseYear,
    releaseDate,
    rating,
    artwork,
  ];
}

/// Standalone playable video.
final class VideoItemV2 extends MediaItemV2 {
  /// Creates a video item.
  const VideoItemV2({
    required super.ref,
    required super.title,
    super.subtitle,
    super.releaseYear,
    super.releaseDate,
    super.rating,
    super.artwork,
  });

  VideoItemV2._fromCommon(_CommonItemFields value)
    : this(
        ref: value.ref,
        title: value.title,
        subtitle: value.subtitle,
        releaseYear: value.releaseYear,
        releaseDate: value.releaseDate,
        rating: value.rating,
        artwork: value.artwork,
      );

  @override
  /// The `video` discriminator.
  MediaKindV2 get kind => MediaKindV2.video;

  @override
  Map<String, Object?> toJson() => _baseJson();
}

/// Series or another episodic collection.
final class SeriesItemV2 extends MediaItemV2 {
  /// Creates a series item.
  const SeriesItemV2({
    required super.ref,
    required super.title,
    super.subtitle,
    super.releaseYear,
    super.releaseDate,
    super.rating,
    super.artwork,
  });

  SeriesItemV2._fromCommon(_CommonItemFields value)
    : this(
        ref: value.ref,
        title: value.title,
        subtitle: value.subtitle,
        releaseYear: value.releaseYear,
        releaseDate: value.releaseDate,
        rating: value.rating,
        artwork: value.artwork,
      );

  @override
  /// The `series` discriminator.
  MediaKindV2 get kind => MediaKindV2.series;

  @override
  Map<String, Object?> toJson() => _baseJson();
}

/// Individually addressable episode.
final class EpisodeItemV2 extends MediaItemV2 {
  /// Creates an episode item.
  const EpisodeItemV2({
    required super.ref,
    required super.title,
    required this.episode,
    super.subtitle,
    super.releaseYear,
    super.releaseDate,
    super.rating,
    super.artwork,
    this.availableAt,
  });

  EpisodeItemV2._fromCommon(
    _CommonItemFields value,
    this.episode,
    this.availableAt,
  ) : super(
        ref: value.ref,
        title: value.title,
        subtitle: value.subtitle,
        releaseYear: value.releaseYear,
        releaseDate: value.releaseDate,
        rating: value.rating,
        artwork: value.artwork,
      );

  /// Parent and position used for navigation and resume.
  final EpisodeIdentity episode;

  /// When this episode first became available, from the episode guide.
  ///
  /// Carried on the item rather than left in the guide because the stream
  /// role matches on it: a provider indexing a long-running series by
  /// broadcast date has no other way to tell one cour's episode 1 from
  /// another's, and it cannot re-read the guide from inside `sources`.
  final DateTime? availableAt;

  @override
  /// The `episode` discriminator.
  MediaKindV2 get kind => MediaKindV2.episode;

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'episode': episode.toJson(),
    if (availableAt != null)
      'availableAt': availableAt!.toUtc().toIso8601String(),
  };

  @override
  List<Object?> get props => [...super.props, episode, availableAt];
}

/// Continuously available channel.
final class ChannelItemV2 extends MediaItemV2 {
  /// Creates a channel item.
  const ChannelItemV2({
    required super.ref,
    required super.title,
    super.subtitle,
    super.releaseYear,
    super.releaseDate,
    super.rating,
    super.artwork,
  });

  ChannelItemV2._fromCommon(_CommonItemFields value)
    : this(
        ref: value.ref,
        title: value.title,
        subtitle: value.subtitle,
        releaseYear: value.releaseYear,
        releaseDate: value.releaseDate,
        rating: value.rating,
        artwork: value.artwork,
      );

  @override
  /// The `channel` discriminator.
  MediaKindV2 get kind => MediaKindV2.channel;

  @override
  Map<String, Object?> toJson() => _baseJson();
}

/// Scheduled or live event.
final class EventItemV2 extends MediaItemV2 {
  /// Creates an event item.
  const EventItemV2({
    required super.ref,
    required super.title,
    required this.schedule,
    super.subtitle,
    super.releaseYear,
    super.releaseDate,
    super.rating,
    super.artwork,
    this.participants = const [],
  });

  EventItemV2._fromCommon(
    _CommonItemFields value, {
    required this.schedule,
    required this.participants,
  }) : super(
         ref: value.ref,
         title: value.title,
         subtitle: value.subtitle,
         releaseYear: value.releaseYear,
         releaseDate: value.releaseDate,
         rating: value.rating,
         artwork: value.artwork,
       );

  /// Required schedule for this event.
  final Schedule schedule;

  /// Optional event participants.
  final List<Participant> participants;

  @override
  /// The `event` discriminator.
  MediaKindV2 get kind => MediaKindV2.event;

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'schedule': schedule.toJson(),
    if (participants.isNotEmpty)
      'participants': participants.map((value) => value.toJson()).toList(),
  };

  @override
  List<Object?> get props => [...super.props, schedule, participants];
}

const _baseKeys = {
  'ref',
  'kind',
  'title',
  'subtitle',
  'releaseYear',
  'releaseDate',
  'rating',
  'artwork',
};

final class _CommonItemFields {
  const _CommonItemFields({
    required this.ref,
    required this.title,
    this.subtitle,
    this.releaseYear,
    this.releaseDate,
    this.rating,
    this.artwork,
  });

  factory _CommonItemFields.fromJson(Map<String, Object?> json) {
    final ref = json['ref'];
    final title = json['title'];
    final subtitle = json['subtitle'];
    final releaseYear = json['releaseYear'];
    final releaseDate = json['releaseDate'];
    final rating = json['rating'];
    final artwork = json['artwork'];
    if (ref is! Map) throw const FormatException('item.ref must be an object');
    if (title is! String || title.isEmpty) {
      throw const FormatException('item.title must be a non-empty string');
    }
    if (subtitle != null && subtitle is! String) {
      throw const FormatException('item.subtitle must be a string');
    }
    if (releaseYear != null && (releaseYear is! int || releaseYear <= 0)) {
      throw const FormatException(
        'item.releaseYear must be a positive integer',
      );
    }
    DateTime? parsedReleaseDate;
    if (releaseDate != null) {
      parsedReleaseDate = releaseDate is String
          ? DateTime.tryParse(releaseDate)
          : null;
      if (parsedReleaseDate == null ||
          !(releaseDate as String).toUpperCase().endsWith('Z')) {
        throw const FormatException(
          'item.releaseDate must be an ISO-8601 UTC timestamp',
        );
      }
    }
    if (rating != null && (rating is! num || !rating.isFinite || rating < 0)) {
      throw const FormatException('item.rating must be a non-negative number');
    }
    if (artwork != null && artwork is! Map) {
      throw const FormatException('item.artwork must be an object');
    }
    return _CommonItemFields(
      ref: MediaRef.fromJson(ref.cast<String, Object?>()),
      title: title,
      subtitle: subtitle as String?,
      releaseYear: releaseYear as int?,
      releaseDate: parsedReleaseDate,
      rating: (rating as num?)?.toDouble(),
      artwork: artwork == null
          ? null
          : Artwork.fromJson((artwork as Map).cast<String, Object?>()),
    );
  }

  final MediaRef ref;
  final String title;
  final String? subtitle;
  final int? releaseYear;
  final DateTime? releaseDate;
  final double? rating;
  final Artwork? artwork;
}

ImageRef? _imageFromJson(Object? value, String path) {
  if (value == null) return null;
  if (value is! Map) throw FormatException('$path must be an object');
  final map = value.cast<String, Object?>();
  _rejectUnknown(map, const {'url'}, path);
  final rawUrl = map['url'];
  if (rawUrl is! String) throw FormatException('$path.url must be a string');
  final uri = Uri.tryParse(rawUrl);
  if (uri == null ||
      !uri.isAbsolute ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw FormatException('$path.url must be an absolute HTTP(S) URL');
  }
  return ImageRef(rawUrl);
}

void _rejectUnknown(
  Map<String, Object?> json,
  Set<String> allowed,
  String path,
) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$path contains unsupported field "$key"');
    }
  }
}
