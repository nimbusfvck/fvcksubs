import 'package:equatable/equatable.dart';

import '../json_util.dart';
import 'event_branding.dart';
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
  const Artwork({
    this.portrait,
    this.landscape,
    this.backdrops = const [],
    this.logo,
  });

  /// Decodes and validates artwork.
  factory Artwork.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'portrait',
      'landscape',
      'backdrops',
      'logo',
    }, 'artwork');
    final artwork = Artwork(
      portrait: _imageFromJson(json['portrait'], 'artwork.portrait'),
      landscape: _imageFromJson(json['landscape'], 'artwork.landscape'),
      backdrops: _imagesFromJson(json['backdrops'], 'artwork.backdrops'),
      logo: _imageFromJson(json['logo'], 'artwork.logo'),
    );
    if (artwork.portrait == null &&
        artwork.landscape == null &&
        artwork.backdrops.isEmpty &&
        artwork.logo == null) {
      throw const FormatException('artwork must contain at least one image');
    }
    return artwork;
  }

  /// Portrait image for narrow cards.
  final ImageRef? portrait;

  /// Landscape image for wide cards and detail headers.
  final ImageRef? landscape;

  /// Alternate landscape images for detail headers and backdrop carousels.
  final List<ImageRef> backdrops;

  /// Optional title or brand mark.
  final ImageRef? logo;

  /// Encodes this artwork.
  Map<String, Object?> toJson() => {
    if (portrait != null) 'portrait': portrait!.toJson(),
    if (landscape != null) 'landscape': landscape!.toJson(),
    if (backdrops.isNotEmpty)
      'backdrops': backdrops.map((image) => image.toJson()).toList(),
    if (logo != null) 'logo': logo!.toJson(),
  };

  @override
  List<Object?> get props => [portrait, landscape, backdrops, logo];
}

/// A rating supplied by a named review or audience service.
class MediaRating extends Equatable {
  /// Creates a rating.
  const MediaRating({
    required this.source,
    required this.score,
    required this.scale,
    this.votes,
    this.kind,
    this.icon,
  });

  /// Decodes and validates a rating.
  factory MediaRating.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'source',
      'score',
      'scale',
      'votes',
      'kind',
      'icon',
    }, 'rating');
    final source = json['source'];
    final score = json['score'];
    final scale = json['scale'];
    final votes = json['votes'];
    final kind = json['kind'];
    final icon = json['icon'];
    if (source is! String || source.trim().isEmpty) {
      throw const FormatException('rating.source must be a non-empty string');
    }
    if (score is! num || !score.isFinite || score < 0) {
      throw const FormatException('rating.score must be a non-negative number');
    }
    if (scale is! num || !scale.isFinite || scale <= 0) {
      throw const FormatException('rating.scale must be a positive number');
    }
    if (score > scale) {
      throw const FormatException('rating.score must not exceed rating.scale');
    }
    if (votes != null &&
        (votes is! num ||
            !votes.isFinite ||
            votes < 0 ||
            votes.toInt() != votes)) {
      throw const FormatException(
        'rating.votes must be a non-negative integer',
      );
    }
    if (kind != null && (kind is! String || kind.trim().isEmpty)) {
      throw const FormatException('rating.kind must be a non-empty string');
    }
    if (icon != null && icon is! Map) {
      throw const FormatException('rating.icon must be an object');
    }
    return MediaRating(
      source: source.trim(),
      score: score.toDouble(),
      scale: scale.toDouble(),
      votes: (votes as num?)?.toInt(),
      kind: (kind as String?)?.trim(),
      icon: icon == null ? null : _imageFromJson(icon, 'rating.icon'),
    );
  }

  /// Stable source identifier, for example `imdb` or `rottenTomatoes`.
  final String source;

  /// Score awarded by [source].
  final double score;

  /// Maximum score, or percentage scale, used by [source].
  final double scale;

  /// Optional vote count reported by the source.
  final int? votes;

  /// Optional source-specific category, such as `critic` or `audience`.
  final String? kind;

  /// Optional source icon.
  final ImageRef? icon;

  /// Encodes this rating.
  Map<String, Object?> toJson() => {
    'source': source,
    'score': score,
    'scale': scale,
    if (votes != null) 'votes': votes,
    if (kind != null) 'kind': kind,
    if (icon != null) 'icon': icon!.toJson(),
  };

  @override
  List<Object?> get props => [source, score, scale, votes, kind, icon];
}

/// Schedule data available only on an [EventItemV2].
class Schedule extends Equatable {
  /// Creates a schedule.
  const Schedule({
    required this.startsAt,
    this.state = ScheduleState.unknown,
    this.label,
    this.endsAt,
  });

  /// Decodes and validates a schedule.
  factory Schedule.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'startsAt',
      'state',
      'label',
      'endsAt',
    }, 'schedule');
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
    final rawEndsAt = json['endsAt'];
    DateTime? parsedEndsAt;
    if (rawEndsAt != null) {
      if (rawEndsAt is! String) {
        throw const FormatException('schedule.endsAt must be a string');
      }
      parsedEndsAt = DateTime.tryParse(rawEndsAt);
      if (parsedEndsAt == null || !rawEndsAt.toUpperCase().endsWith('Z')) {
        throw const FormatException(
          'schedule.endsAt must be an ISO-8601 UTC timestamp',
        );
      }
      if (!parsedEndsAt.isAfter(parsed)) {
        throw const FormatException('schedule.endsAt must be after startsAt');
      }
    }
    return Schedule(
      startsAt: parsed,
      state: enumByName(
        ScheduleState.values,
        json['state'],
        orElse: ScheduleState.unknown,
      ),
      label: label as String?,
      endsAt: parsedEndsAt,
    );
  }

  /// Event start in UTC.
  final DateTime startsAt;

  /// Machine-readable lifecycle state.
  final ScheduleState state;

  /// Optional short status rendered verbatim.
  final String? label;

  /// Estimated or provider-supplied event end in UTC.
  final DateTime? endsAt;

  /// Encodes this schedule.
  Map<String, Object?> toJson() => {
    'startsAt': startsAt.toUtc().toIso8601String(),
    'state': state.name,
    if (label != null) 'label': label,
    if (endsAt != null) 'endsAt': endsAt!.toUtc().toIso8601String(),
  };

  @override
  List<Object?> get props => [startsAt, state, label, endsAt];
}

/// Typed navigation context for an episode.
class EpisodeIdentity extends Equatable {
  /// Creates episode identity.
  const EpisodeIdentity({
    required this.parentRef,
    required this.groupId,
    required this.position,
    this.absoluteEpisode,
  });

  /// Decodes and validates episode identity.
  factory EpisodeIdentity.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'parentRef',
      'groupId',
      'position',
      'absoluteEpisode',
    }, 'episode');
    final groupId = json['groupId'];
    final position = json['position'];
    final absoluteEpisode = json['absoluteEpisode'];
    if (groupId is! String || groupId.isEmpty) {
      throw const FormatException('episode.groupId must be a non-empty string');
    }
    if (position is! num || position.toInt() != position || position < 1) {
      throw const FormatException(
        'episode.position must be a positive integer',
      );
    }
    if (absoluteEpisode != null &&
        (absoluteEpisode is! num ||
            absoluteEpisode.toInt() != absoluteEpisode ||
            absoluteEpisode < 1)) {
      throw const FormatException(
        'episode.absoluteEpisode must be a positive integer',
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
      absoluteEpisode: (absoluteEpisode as num?)?.toInt(),
    );
  }

  /// Series or collection containing the episode.
  final MediaRef parentRef;

  /// Opaque group ID supplied by the extension.
  final String groupId;

  /// One-based display position within the group.
  final int position;

  /// Optional one-based position in the provider's continuous episode run.
  final int? absoluteEpisode;

  /// Encodes this identity.
  Map<String, Object?> toJson() => {
    'parentRef': parentRef.toJson(),
    'groupId': groupId,
    'position': position,
    if (absoluteEpisode != null) 'absoluteEpisode': absoluteEpisode,
  };

  @override
  List<Object?> get props => [parentRef, groupId, position, absoluteEpisode];
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
    this.overview,
    this.originalTitle,
    this.originalLanguage,
    this.genres = const [],
    this.countries = const [],
    this.tags = const [],
    this.releaseYear,
    this.releaseDate,
    this.rating,
    this.ratingVotes,
    this.ratings = const [],
    this.imdbId,
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
          'branding',
        }, 'event item');
        final schedule = json['schedule'];
        if (schedule is! Map) {
          throw const FormatException('event item requires a schedule');
        }
        final participants = json['participants'];
        if (participants != null && participants is! List) {
          throw const FormatException('event participants must be a list');
        }
        final branding = json['branding'];
        if (branding != null && branding is! Map) {
          throw const FormatException('event branding must be an object');
        }
        return EventItemV2._fromCommon(
          common,
          schedule: Schedule.fromJson(schedule.cast<String, Object?>()),
          participants: [
            for (final entry in (participants as List?) ?? const [])
              Participant.fromJson((entry as Map).cast<String, Object?>()),
          ],
          branding: branding == null
              ? null
              : EventBranding.fromJson(
                  (branding as Map).cast<String, Object?>(),
                ),
        );
    }
  }

  /// Stable item identity.
  final MediaRef ref;

  /// Primary display title.
  final String title;

  /// Optional secondary display text.
  final String? subtitle;

  /// Optional short synopsis suitable for list previews.
  final String? overview;

  /// Optional title in the source's original language.
  final String? originalTitle;

  /// Optional ISO 639-1 original language code.
  final String? originalLanguage;

  /// Optional normalized genre names.
  final List<String> genres;

  /// Optional ISO 3166-1 country codes associated with the item.
  final List<String> countries;

  /// Normalized extension-supplied labels used for lightweight filtering.
  final List<String> tags;

  /// Calendar year in which this item was first released.
  final int? releaseYear;

  /// When this item first becomes (or became) available, from the
  /// extension. A future value marks it as not yet released.
  final DateTime? releaseDate;

  /// Extension-supplied audience or editorial rating.
  final double? rating;

  /// Optional number of votes behind [rating].
  final int? ratingVotes;

  /// Optional ratings from external services.
  final List<MediaRating> ratings;

  /// Optional IMDb identifier used to join external metadata.
  final String? imdbId;

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
    if (overview != null) 'overview': overview,
    if (originalTitle != null) 'originalTitle': originalTitle,
    if (originalLanguage != null) 'originalLanguage': originalLanguage,
    if (genres.isNotEmpty) 'genres': genres,
    if (countries.isNotEmpty) 'countries': countries,
    if (releaseYear != null) 'releaseYear': releaseYear,
    if (releaseDate != null)
      'releaseDate': releaseDate!.toUtc().toIso8601String(),
    if (rating != null) 'rating': rating,
    if (ratingVotes != null) 'ratingVotes': ratingVotes,
    if (ratings.isNotEmpty)
      'ratings': ratings.map((value) => value.toJson()).toList(),
    if (imdbId != null) 'imdbId': imdbId,
    if (tags.isNotEmpty) 'tags': tags,
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
    overview,
    originalTitle,
    originalLanguage,
    genres,
    countries,
    tags,
    releaseYear,
    releaseDate,
    rating,
    ratingVotes,
    ratings,
    imdbId,
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
    super.overview,
    super.originalTitle,
    super.originalLanguage,
    super.genres,
    super.countries,
    super.tags,
    super.releaseYear,
    super.releaseDate,
    super.rating,
    super.ratingVotes,
    super.ratings,
    super.imdbId,
    super.artwork,
  });

  VideoItemV2._fromCommon(_CommonItemFields value)
    : this(
        ref: value.ref,
        title: value.title,
        subtitle: value.subtitle,
        overview: value.overview,
        originalTitle: value.originalTitle,
        originalLanguage: value.originalLanguage,
        genres: value.genres,
        countries: value.countries,
        tags: value.tags,
        releaseYear: value.releaseYear,
        releaseDate: value.releaseDate,
        rating: value.rating,
        ratingVotes: value.ratingVotes,
        ratings: value.ratings,
        imdbId: value.imdbId,
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
    super.overview,
    super.originalTitle,
    super.originalLanguage,
    super.genres,
    super.countries,
    super.tags,
    super.releaseYear,
    super.releaseDate,
    super.rating,
    super.ratingVotes,
    super.ratings,
    super.imdbId,
    super.artwork,
  });

  SeriesItemV2._fromCommon(_CommonItemFields value)
    : this(
        ref: value.ref,
        title: value.title,
        subtitle: value.subtitle,
        overview: value.overview,
        originalTitle: value.originalTitle,
        originalLanguage: value.originalLanguage,
        genres: value.genres,
        countries: value.countries,
        tags: value.tags,
        releaseYear: value.releaseYear,
        releaseDate: value.releaseDate,
        rating: value.rating,
        ratingVotes: value.ratingVotes,
        ratings: value.ratings,
        imdbId: value.imdbId,
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
    super.overview,
    super.originalTitle,
    super.originalLanguage,
    super.genres,
    super.countries,
    super.tags,
    super.releaseYear,
    super.releaseDate,
    super.rating,
    super.ratingVotes,
    super.ratings,
    super.imdbId,
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
        overview: value.overview,
        originalTitle: value.originalTitle,
        originalLanguage: value.originalLanguage,
        genres: value.genres,
        countries: value.countries,
        tags: value.tags,
        releaseYear: value.releaseYear,
        releaseDate: value.releaseDate,
        rating: value.rating,
        ratingVotes: value.ratingVotes,
        ratings: value.ratings,
        imdbId: value.imdbId,
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
    super.overview,
    super.originalTitle,
    super.originalLanguage,
    super.genres,
    super.countries,
    super.tags,
    super.releaseYear,
    super.releaseDate,
    super.rating,
    super.ratingVotes,
    super.ratings,
    super.imdbId,
    super.artwork,
  });

  ChannelItemV2._fromCommon(_CommonItemFields value)
    : this(
        ref: value.ref,
        title: value.title,
        subtitle: value.subtitle,
        overview: value.overview,
        originalTitle: value.originalTitle,
        originalLanguage: value.originalLanguage,
        genres: value.genres,
        countries: value.countries,
        tags: value.tags,
        releaseYear: value.releaseYear,
        releaseDate: value.releaseDate,
        rating: value.rating,
        ratingVotes: value.ratingVotes,
        ratings: value.ratings,
        imdbId: value.imdbId,
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
    super.overview,
    super.originalTitle,
    super.originalLanguage,
    super.genres,
    super.countries,
    super.tags,
    super.releaseYear,
    super.releaseDate,
    super.rating,
    super.ratingVotes,
    super.ratings,
    super.imdbId,
    super.artwork,
    this.participants = const [],
    this.branding,
  });

  EventItemV2._fromCommon(
    _CommonItemFields value, {
    required this.schedule,
    required this.participants,
    required this.branding,
  }) : super(
         ref: value.ref,
         title: value.title,
         subtitle: value.subtitle,
         overview: value.overview,
         originalTitle: value.originalTitle,
         originalLanguage: value.originalLanguage,
         genres: value.genres,
         countries: value.countries,
         tags: value.tags,
         releaseYear: value.releaseYear,
         releaseDate: value.releaseDate,
         rating: value.rating,
         ratingVotes: value.ratingVotes,
         ratings: value.ratings,
         imdbId: value.imdbId,
         artwork: value.artwork,
       );

  /// Required schedule for this event.
  final Schedule schedule;

  /// Optional event participants.
  final List<Participant> participants;

  /// Optional competition, tournament, or organizer branding.
  final EventBranding? branding;

  @override
  /// The `event` discriminator.
  MediaKindV2 get kind => MediaKindV2.event;

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'schedule': schedule.toJson(),
    if (participants.isNotEmpty)
      'participants': participants.map((value) => value.toJson()).toList(),
    if (branding != null) 'branding': branding!.toJson(),
  };

  @override
  List<Object?> get props => [...super.props, schedule, participants, branding];
}

const _baseKeys = {
  'ref',
  'kind',
  'title',
  'subtitle',
  'overview',
  'originalTitle',
  'originalLanguage',
  'genres',
  'countries',
  'tags',
  'releaseYear',
  'releaseDate',
  'rating',
  'ratingVotes',
  'ratings',
  'imdbId',
  'artwork',
};

final class _CommonItemFields {
  const _CommonItemFields({
    required this.ref,
    required this.title,
    this.subtitle,
    this.overview,
    this.originalTitle,
    this.originalLanguage,
    this.genres = const [],
    this.countries = const [],
    this.tags = const [],
    this.releaseYear,
    this.releaseDate,
    this.rating,
    this.ratingVotes,
    this.ratings = const [],
    this.imdbId,
    this.artwork,
  });

  factory _CommonItemFields.fromJson(Map<String, Object?> json) {
    final ref = json['ref'];
    final title = json['title'];
    final subtitle = json['subtitle'];
    final overview = json['overview'];
    final originalTitle = json['originalTitle'];
    final originalLanguage = json['originalLanguage'];
    final genres = json['genres'];
    final countries = json['countries'];
    final tags = json['tags'];
    final releaseYear = json['releaseYear'];
    final releaseDate = json['releaseDate'];
    final rating = json['rating'];
    final ratingVotes = json['ratingVotes'];
    final ratings = json['ratings'];
    final imdbId = json['imdbId'];
    final artwork = json['artwork'];
    if (ref is! Map) throw const FormatException('item.ref must be an object');
    if (title is! String || title.isEmpty) {
      throw const FormatException('item.title must be a non-empty string');
    }
    if (subtitle != null && subtitle is! String) {
      throw const FormatException('item.subtitle must be a string');
    }
    if (overview != null && overview is! String) {
      throw const FormatException('item.overview must be a string');
    }
    if (originalTitle != null && originalTitle is! String) {
      throw const FormatException('item.originalTitle must be a string');
    }
    if (originalLanguage != null && originalLanguage is! String) {
      throw const FormatException('item.originalLanguage must be a string');
    }
    final parsedGenres = _stringListFromJson(genres, 'item.genres');
    final parsedCountries = _stringListFromJson(countries, 'item.countries');
    if (tags != null && tags is! List) {
      throw const FormatException('item.tags must be a list');
    }
    final parsedTags = <String>[];
    for (final tag in (tags as List?) ?? const []) {
      if (tag is! String || tag.trim().isEmpty) {
        throw const FormatException('item.tags[] must be a non-empty string');
      }
      parsedTags.add(tag.trim());
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
    if (ratingVotes != null &&
        (ratingVotes is! int || ratingVotes < 0)) {
      throw const FormatException(
        'item.ratingVotes must be a non-negative integer',
      );
    }
    if (ratings != null && ratings is! List) {
      throw const FormatException('item.ratings must be a list');
    }
    if (imdbId != null &&
        (imdbId is! String || !RegExp(r'^tt\d+$').hasMatch(imdbId))) {
      throw const FormatException(
        'item.imdbId must be a valid IMDb identifier',
      );
    }
    if (artwork != null && artwork is! Map) {
      throw const FormatException('item.artwork must be an object');
    }
    return _CommonItemFields(
      ref: MediaRef.fromJson(ref.cast<String, Object?>()),
      title: title,
      subtitle: subtitle as String?,
      overview: overview as String?,
      originalTitle: originalTitle as String?,
      originalLanguage: originalLanguage as String?,
      genres: parsedGenres,
      countries: parsedCountries,
      tags: parsedTags,
      releaseYear: releaseYear as int?,
      releaseDate: parsedReleaseDate,
      rating: (rating as num?)?.toDouble(),
      ratingVotes: ratingVotes as int?,
      ratings: [
        for (final entry in (ratings as List?) ?? const [])
          MediaRating.fromJson((entry as Map).cast<String, Object?>()),
      ],
      imdbId: imdbId as String?,
      artwork: artwork == null
          ? null
          : Artwork.fromJson((artwork as Map).cast<String, Object?>()),
    );
  }

  final MediaRef ref;
  final String title;
  final String? subtitle;
  final String? overview;
  final String? originalTitle;
  final String? originalLanguage;
  final List<String> genres;
  final List<String> countries;
  final List<String> tags;
  final int? releaseYear;
  final DateTime? releaseDate;
  final double? rating;
  final int? ratingVotes;
  final List<MediaRating> ratings;
  final String? imdbId;
  final Artwork? artwork;
}

List<String> _stringListFromJson(Object? value, String path) {
  if (value == null) return const [];
  if (value is! List) throw FormatException('$path must be a list');
  final result = <String>[];
  for (final entry in value) {
    if (entry is! String || entry.trim().isEmpty) {
      throw FormatException('$path[] must be a non-empty string');
    }
    result.add(entry.trim());
  }
  return result;
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

List<ImageRef> _imagesFromJson(Object? value, String path) {
  if (value == null) return const [];
  if (value is! List) throw FormatException('$path must be a list');
  return [
    for (var index = 0; index < value.length; index++)
      _imageFromJson(value[index], '$path[$index]')!,
  ];
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
