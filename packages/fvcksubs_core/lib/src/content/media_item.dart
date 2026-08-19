import 'package:equatable/equatable.dart';

import '../json_util.dart';
import 'image_ref.dart';
import 'media_ref.dart';
import 'participant.dart';

/// What kind of thing a [MediaItem] is. Selects which layout renders it.
///
/// Strict on decode (unlike [LiveStatus]): an unknown kind is a real
/// incompatibility the manifest `apiVersion` is meant to catch, not something
/// to silently coerce.
enum MediaKind {
  /// A scheduled contest or broadcast (match, race, fight).
  liveEvent,

  /// An always-on channel with no start/end.
  channel,

  /// A single film.
  movie,

  /// A series container (its episodes are separate items).
  series,

  /// One episode of a series.
  episode,
}

/// Coarse live state. The human-readable detail lives in
/// [MediaItem.statusLabel]; this only drives sorting and the LIVE badge.
enum LiveStatus {
  /// Not started yet.
  scheduled,

  /// In progress now.
  live,

  /// Finished.
  ended,

  /// State not known (the default; also the fallback for an unrecognized value).
  unknown,
}

/// One content item — a match, a race, a film, a TV channel — in a single
/// sport-agnostic shape.
///
/// The app never branches on what the fields *mean*. `participants.length == 2`
/// is the only shape distinction it makes (it turns on the two-sided matcher);
/// everything else is rendered as given.
class MediaItem extends Equatable {
  /// Creates a media item.
  const MediaItem({
    required this.ref,
    required this.kind,
    required this.title,
    this.subtitle,
    this.poster,
    this.thumbnail,
    this.startsAt,
    this.endsAt,
    this.status = LiveStatus.unknown,
    this.statusLabel,
    this.participants = const [],
    this.badges = const [],
    this.group,
    this.extra = const {},
  });

  /// Builds a [MediaItem] from decoded JSON.
  factory MediaItem.fromJson(Map<String, Object?> json) => MediaItem(
    ref: MediaRef.fromJson(json['ref']! as Map<String, Object?>),
    kind: enumByNameStrict(MediaKind.values, json['kind']),
    title: json['title'] as String,
    subtitle: json['subtitle'] as String?,
    poster: ImageRef.fromJson(json['poster']),
    thumbnail: ImageRef.fromJson(json['thumbnail']),
    startsAt: dateFromJson(json['startsAt']),
    endsAt: dateFromJson(json['endsAt']),
    status: enumByName(
      LiveStatus.values,
      json['status'],
      orElse: LiveStatus.unknown,
    ),
    statusLabel: json['statusLabel'] as String?,
    participants: ((json['participants'] as List?) ?? const [])
        .map((e) => Participant.fromJson(e as Map<String, Object?>))
        .toList(),
    badges: stringList(json['badges']),
    group: json['group'] as String?,
    extra: (json['extra'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  /// Fully-qualified address of this item.
  final MediaRef ref;

  /// Which layout renders this item.
  final MediaKind kind;

  /// Primary title.
  final String title;

  /// Secondary line (competition, episode name, year), or `null`.
  final String? subtitle;

  /// Portrait artwork, for films/series.
  final ImageRef? poster;

  /// Landscape artwork, for events/channels.
  final ImageRef? thumbnail;

  /// Scheduled/actual start, UTC. `null` when not applicable (a channel).
  final DateTime? startsAt;

  /// Scheduled/actual end, UTC, or `null`.
  final DateTime? endsAt;

  /// Coarse live state.
  final LiveStatus status;

  /// Free-text status shown verbatim (`"HT"`, `"Lap 12/20"`, `"90+3'"`).
  final String? statusLabel;

  /// Competitors. Empty for a film/channel, two for a match, N for a race.
  final List<Participant> participants;

  /// Short display tags (`"4K"`, `"ID Comm"`).
  final List<String> badges;

  /// Section heading this item sits under, or `null` for an ungrouped list.
  ///
  /// Deliberately a plain label, not a typed "league"/"season"/"genre": the
  /// app renders a heading whenever this changes and never learns what the
  /// grouping *means* — a football catalog can group by competition, a movie
  /// one by decade, using the same field and the same rendering.
  ///
  /// The extension owns the arrangement: items are expected to arrive already
  /// ordered with each group contiguous, since only the extension knows what
  /// order its groups belong in (by433's own `displayOrder`, here). The app
  /// does not re-sort.
  final String? group;

  /// Extension-private passthrough. The app carries it but never reads it.
  final Map<String, Object?> extra;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'ref': ref.toJson(),
    'kind': kind.name,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (poster != null) 'poster': poster!.toJson(),
    if (thumbnail != null) 'thumbnail': thumbnail!.toJson(),
    if (startsAt != null) 'startsAt': dateToJson(startsAt),
    if (endsAt != null) 'endsAt': dateToJson(endsAt),
    'status': status.name,
    if (statusLabel != null) 'statusLabel': statusLabel,
    if (participants.isNotEmpty)
      'participants': participants.map((p) => p.toJson()).toList(),
    if (badges.isNotEmpty) 'badges': badges,
    if (group != null) 'group': group,
    if (extra.isNotEmpty) 'extra': extra,
  };

  @override
  List<Object?> get props => [
    ref,
    kind,
    title,
    subtitle,
    poster,
    thumbnail,
    startsAt,
    endsAt,
    status,
    statusLabel,
    participants,
    badges,
    group,
    extra,
  ];
}

/// One cast member, for a [MediaDetail]'s cast row.
class CastMember extends Equatable {
  /// Creates a cast member.
  const CastMember({required this.name, this.character = '', this.photoUrl});

  /// Builds a [CastMember] from decoded JSON.
  factory CastMember.fromJson(Map<String, Object?> json) => CastMember(
    name: json['name'] as String,
    character: (json['character'] as String?) ?? '',
    photoUrl: json['photoUrl'] as String?,
  );

  /// The actor's name.
  final String name;

  /// The role played, or empty when the upstream didn't say.
  final String character;

  /// Headshot URL, or `null`.
  final String? photoUrl;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'name': name,
    if (character.isNotEmpty) 'character': character,
    if (photoUrl != null) 'photoUrl': photoUrl,
  };

  @override
  List<Object?> get props => [name, character, photoUrl];
}

/// One episode, inside a [SeriesSeason].
class SeriesEpisode extends Equatable {
  /// Creates a series episode.
  const SeriesEpisode({
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.duration,
    this.releaseDate,
  });

  /// Builds a [SeriesEpisode] from decoded JSON.
  factory SeriesEpisode.fromJson(Map<String, Object?> json) => SeriesEpisode(
    title: json['title'] as String,
    description: json['description'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    duration: json['duration'] as String?,
    releaseDate: dateFromJson(json['releaseDate']),
  );

  /// Episode title.
  final String title;

  /// Episode synopsis, or `null`.
  final String? description;

  /// Episode still, or `null`.
  final String? thumbnailUrl;

  /// Display-ready duration (`"57m"`) exactly as the upstream sent it — not
  /// parsed to minutes, since nothing computes with it and the format isn't
  /// guaranteed uniform across upstreams.
  final String? duration;

  /// When this episode airs/aired, or `null` when the upstream has no notion
  /// of one. A real [DateTime] (unlike [duration]) because the app computes
  /// with it — whether it's in the future decides whether the episode is
  /// shown as released yet.
  final DateTime? releaseDate;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'title': title,
    if (description != null) 'description': description,
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    if (duration != null) 'duration': duration,
    if (releaseDate != null) 'releaseDate': dateToJson(releaseDate),
  };

  @override
  List<Object?> get props => [
    title,
    description,
    thumbnailUrl,
    duration,
    releaseDate,
  ];
}

/// One season, inside a [MediaDetail].
class SeriesSeason extends Equatable {
  /// Creates a series season.
  const SeriesSeason({
    required this.number,
    required this.name,
    this.episodes = const [],
  });

  /// Builds a [SeriesSeason] from decoded JSON.
  factory SeriesSeason.fromJson(Map<String, Object?> json) => SeriesSeason(
    number: (json['number']! as num).toInt(),
    name: json['name'] as String,
    episodes: ((json['episodes'] as List?) ?? const [])
        .map((e) => SeriesEpisode.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
  );

  /// Season number (1-based; a "specials" season may be 0).
  final int number;

  /// Season display name (`"Season 1"`).
  final String name;

  /// This season's episodes, in order.
  final List<SeriesEpisode> episodes;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'number': number,
    'name': name,
    if (episodes.isNotEmpty) 'episodes': episodes.map((e) => e.toJson()).toList(),
  };

  @override
  List<Object?> get props => [number, name, episodes];
}

/// A single item's detail view (the `meta` response).
///
/// Deliberately thin for V1 (see PLAN.md, "Detail UI: tipis dulu") in the
/// sense that matters — no premature protocol capability, everything here is
/// still a plain field on one response, not a role of its own — but not thin
/// on content: [cast] and [seasons] exist because a real movie/series detail
/// page needs more than a synopsis to not look bare. Still left out:
/// collection, recommendations, similar, trailers — real fields the upstream
/// (lumen-tv) sends that nothing renders yet. Playable sources are fetched
/// separately via the `sources` role, not carried here.
class MediaDetail extends Equatable {
  /// Creates a media detail.
  const MediaDetail({
    required this.item,
    this.description,
    this.tagline,
    this.genres = const [],
    this.runtimeMinutes,
    this.certification,
    this.networks = const [],
    this.cast = const [],
    this.seasons = const [],
    this.lastAiredSeason,
    this.lastAiredEpisode,
  });

  /// Builds a [MediaDetail] from decoded JSON.
  factory MediaDetail.fromJson(Map<String, Object?> json) => MediaDetail(
    item: MediaItem.fromJson(json['item']! as Map<String, Object?>),
    description: json['description'] as String?,
    tagline: json['tagline'] as String?,
    genres: stringList(json['genres']),
    runtimeMinutes: (json['runtimeMinutes'] as num?)?.toInt(),
    certification: json['certification'] as String?,
    networks: stringList(json['networks']),
    cast: ((json['cast'] as List?) ?? const [])
        .map((e) => CastMember.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
    seasons: ((json['seasons'] as List?) ?? const [])
        .map((e) => SeriesSeason.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
    lastAiredSeason: (json['lastAiredSeason'] as num?)?.toInt(),
    lastAiredEpisode: (json['lastAiredEpisode'] as num?)?.toInt(),
  );

  /// The item this detail describes.
  final MediaItem item;

  /// Long-form description/synopsis, or `null`.
  final String? description;

  /// Short marketing blurb (TMDB's "tagline"), distinct from [description] —
  /// e.g. "Every act of vengeance has a cost." — or `null`.
  final String? tagline;

  /// Genre names (`"Action"`, `"Sci-Fi"`), display-ready. Empty when the
  /// upstream has none or the item's kind has no concept of one.
  final List<String> genres;

  /// Total runtime in minutes, or `null` when unknown (a series, or an
  /// upcoming release TMDB hasn't timed yet).
  final int? runtimeMinutes;

  /// Content rating (`"PG-13"`, `"TV-MA"`), or `null`.
  final String? certification;

  /// Broadcaster/streamer names (`"HBO"`) — mainly a series concept. Empty
  /// for a film, or when the upstream has none.
  final List<String> networks;

  /// Cast, upstream order (typically billing order). Empty when the upstream
  /// sent none.
  final List<CastMember> cast;

  /// Seasons, in order. Always empty for a film — only a series has any.
  final List<SeriesSeason> seasons;

  /// The season/episode number of the most recently aired episode, or `null`
  /// when the upstream can't say (a film, or an extension with no notion of
  /// air dates). [seasons] lists every episode announced, aired or not, so
  /// this is the only reliable way to tell "last released" apart from "last
  /// listed" — it's what lets a fresh Play tap default straight to the real
  /// latest episode instead of walking the whole list live to find it (see
  /// `latestAvailableEpisodeTarget` in the app).
  final int? lastAiredSeason;

  /// Episode number within [lastAiredSeason], 1-based. `null` exactly when
  /// [lastAiredSeason] is.
  final int? lastAiredEpisode;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'item': item.toJson(),
    if (description != null) 'description': description,
    if (tagline != null) 'tagline': tagline,
    if (genres.isNotEmpty) 'genres': genres,
    if (runtimeMinutes != null) 'runtimeMinutes': runtimeMinutes,
    if (certification != null) 'certification': certification,
    if (networks.isNotEmpty) 'networks': networks,
    if (cast.isNotEmpty) 'cast': cast.map((c) => c.toJson()).toList(),
    if (seasons.isNotEmpty) 'seasons': seasons.map((s) => s.toJson()).toList(),
    if (lastAiredSeason != null) 'lastAiredSeason': lastAiredSeason,
    if (lastAiredEpisode != null) 'lastAiredEpisode': lastAiredEpisode,
  };

  @override
  List<Object?> get props => [
    item,
    description,
    tagline,
    genres,
    runtimeMinutes,
    certification,
    networks,
    cast,
    seasons,
    lastAiredSeason,
    lastAiredEpisode,
  ];
}
