import 'package:equatable/equatable.dart';

import 'image_ref.dart';
import 'media_item_v2.dart';
import 'media_ref.dart';

/// Display-only labelled metadata.
class MediaFact extends Equatable {
  /// Creates a display fact.
  const MediaFact({required this.label, required this.value});

  /// Decodes and validates a display fact.
  factory MediaFact.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {'label', 'value'}, 'fact');
    return MediaFact(
      label: _requiredString(json['label'], 'fact.label'),
      value: _requiredString(json['value'], 'fact.value'),
    );
  }

  /// Short label shown beside [value].
  final String label;

  /// Display-ready value supplied by the extension.
  final String value;

  /// Encodes this fact.
  Map<String, Object?> toJson() => {'label': label, 'value': value};

  @override
  List<Object?> get props => [label, value];
}

/// A person or entity credited by the extension.
class MediaCredit extends Equatable {
  /// Creates a credit.
  const MediaCredit({required this.name, this.role, this.image});

  /// Decodes and validates a credit.
  factory MediaCredit.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {'name', 'role', 'image'}, 'credit');
    return MediaCredit(
      name: _requiredString(json['name'], 'credit.name'),
      role: _optionalString(json['role'], 'credit.role'),
      image: _optionalImage(json['image'], 'credit.image'),
    );
  }

  /// Display name of the credited person or entity.
  final String name;

  /// Optional display-ready contribution or role.
  final String? role;

  /// Optional profile image.
  final ImageRef? image;

  /// Encodes this credit.
  Map<String, Object?> toJson() => {
    'name': name,
    if (role != null) 'role': role,
    if (image != null) 'image': image!.toJson(),
  };

  @override
  List<Object?> get props => [name, role, image];
}

/// A displayable preview video attached to a media detail response.
class MediaTrailer extends Equatable {
  /// Creates a trailer reference.
  const MediaTrailer({
    required this.title,
    required this.url,
    this.site,
    this.thumbnail,
    this.mimeType,
  });

  /// Decodes and validates a trailer reference.
  factory MediaTrailer.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'title',
      'url',
      'site',
      'thumbnail',
      'mimeType',
    }, 'trailer');
    final url = _requiredHttpUrl(json['url'], 'trailer.url');
    return MediaTrailer(
      title: _requiredString(json['title'], 'trailer.title'),
      url: url,
      site: _optionalString(json['site'], 'trailer.site'),
      thumbnail: _optionalImage(json['thumbnail'], 'trailer.thumbnail'),
      mimeType: _optionalString(json['mimeType'], 'trailer.mimeType'),
    );
  }

  /// User-facing trailer title, such as `Official Trailer`.
  final String title;

  /// Absolute URL opened when the viewer selects the trailer.
  final String url;

  /// Optional platform label, such as `YouTube`.
  final String? site;

  /// Optional preview image for a trailer card or button.
  final ImageRef? thumbnail;

  /// Optional MIME type for a directly playable preview stream.
  ///
  /// When this starts with `video/`, the app may autoplay [url] as a detail
  /// header preview. Omit it for a normal external trailer URL.
  final String? mimeType;

  /// Encodes this trailer reference.
  Map<String, Object?> toJson() => {
    'title': title,
    'url': url,
    if (site != null) 'site': site,
    if (thumbnail != null) 'thumbnail': thumbnail!.toJson(),
    if (mimeType != null) 'mimeType': mimeType,
  };

  @override
  List<Object?> get props => [title, url, site, thumbnail, mimeType];
}

/// One scheduled programme in a continuously available channel's guide.
class ChannelProgramV2 extends Equatable {
  /// Creates a channel programme.
  const ChannelProgramV2({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.subtitle,
    this.description,
  });

  /// Decodes and validates a channel programme.
  factory ChannelProgramV2.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'id',
      'title',
      'subtitle',
      'description',
      'startsAt',
      'endsAt',
    }, 'channel program');
    final startsAt = _requiredUtc(json['startsAt'], 'channelProgram.startsAt');
    final endsAt = _requiredUtc(json['endsAt'], 'channelProgram.endsAt');
    if (!endsAt.isAfter(startsAt)) {
      throw const FormatException(
        'channelProgram.endsAt must be after startsAt',
      );
    }
    return ChannelProgramV2(
      id: _requiredString(json['id'], 'channelProgram.id'),
      title: _requiredString(json['title'], 'channelProgram.title'),
      subtitle: _optionalString(json['subtitle'], 'channelProgram.subtitle'),
      description: _optionalString(
        json['description'],
        'channelProgram.description',
      ),
      startsAt: startsAt,
      endsAt: endsAt,
    );
  }

  /// Stable upstream programme identifier.
  final String id;

  /// Display title.
  final String title;

  /// Optional secondary title or episode label.
  final String? subtitle;

  /// Optional synopsis.
  final String? description;

  /// Programme start in UTC.
  final DateTime startsAt;

  /// Programme end in UTC.
  final DateTime endsAt;

  /// Encodes this programme.
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (description != null) 'description': description,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt.toUtc().toIso8601String(),
  };

  @override
  List<Object?> get props => [
    id,
    title,
    subtitle,
    description,
    startsAt,
    endsAt,
  ];
}

/// Short programme guide for a continuously available channel.
class ChannelGuideV2 extends Equatable {
  /// Creates a channel guide.
  const ChannelGuideV2({
    required this.programs,
    this.generatedAt,
    this.available = true,
  });

  /// Decodes and validates a channel guide.
  factory ChannelGuideV2.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'generatedAt',
      'available',
      'programs',
    }, 'channel guide');
    final programs = json['programs'];
    if (programs is! List) {
      throw const FormatException('channelGuide.programs must be a list');
    }
    final available = json['available'];
    if (available != null && available is! bool) {
      throw const FormatException('channelGuide.available must be a boolean');
    }
    return ChannelGuideV2(
      generatedAt: json['generatedAt'] == null
          ? null
          : _requiredUtc(json['generatedAt'], 'channelGuide.generatedAt'),
      available: available as bool? ?? true,
      programs: [
        for (final entry in programs)
          ChannelProgramV2.fromJson(_object(entry, 'channelGuide.programs[]')),
      ],
    );
  }

  /// When the upstream guide was generated, in UTC.
  final DateTime? generatedAt;

  /// Whether the channel currently has guide data.
  final bool available;

  /// Programmes in chronological display order.
  final List<ChannelProgramV2> programs;

  /// Encodes this guide.
  Map<String, Object?> toJson() => {
    if (generatedAt != null)
      'generatedAt': generatedAt!.toUtc().toIso8601String(),
    'available': available,
    'programs': programs.map((program) => program.toJson()).toList(),
  };

  @override
  List<Object?> get props => [generatedAt, available, programs];
}

/// One playable entry in an episode guide.
class EpisodeSummary extends Equatable {
  /// Creates an episode summary.
  const EpisodeSummary({
    required this.ref,
    required this.title,
    required this.position,
    this.absoluteEpisode,
    this.description,
    this.artwork,
    this.durationSeconds,
    this.availableAt,
  });

  /// Decodes and validates an episode summary.
  factory EpisodeSummary.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'ref',
      'title',
      'position',
      'absoluteEpisode',
      'description',
      'artwork',
      'durationSeconds',
      'availableAt',
    }, 'episode summary');
    final duration = json['durationSeconds'];
    final position = json['position'];
    final absoluteEpisode = json['absoluteEpisode'];
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
    if (duration != null &&
        (duration is! num || duration.toInt() != duration || duration <= 0)) {
      throw const FormatException(
        'episode.durationSeconds must be a positive integer',
      );
    }
    return EpisodeSummary(
      ref: _requiredRef(json['ref'], 'episode.ref'),
      title: _requiredString(json['title'], 'episode.title'),
      position: position.toInt(),
      absoluteEpisode: (absoluteEpisode as num?)?.toInt(),
      description: _optionalString(json['description'], 'episode.description'),
      artwork: _optionalArtwork(json['artwork'], 'episode.artwork'),
      durationSeconds: (duration as num?)?.toInt(),
      availableAt: _optionalUtc(json['availableAt'], 'episode.availableAt'),
    );
  }

  /// Stable reference used for metadata and playback calls.
  final MediaRef ref;

  /// Primary episode title.
  final String title;

  /// One-based display position inside the containing group.
  final int position;

  /// Optional one-based position in the source's continuous episode run.
  ///
  /// TMDB groups long-running anime into seasons while some stream providers
  /// index the same title continuously. The display position stays relative
  /// to its group; this value carries the provider-facing absolute number.
  final int? absoluteEpisode;

  /// Optional synopsis.
  final String? description;

  /// Optional episode-specific artwork.
  final Artwork? artwork;

  /// Optional positive runtime in seconds.
  final int? durationSeconds;

  /// Optional UTC release or availability time.
  final DateTime? availableAt;

  /// Encodes this episode summary.
  Map<String, Object?> toJson() => {
    'ref': ref.toJson(),
    'title': title,
    'position': position,
    if (absoluteEpisode != null) 'absoluteEpisode': absoluteEpisode,
    if (description != null) 'description': description,
    if (artwork != null) 'artwork': artwork!.toJson(),
    if (durationSeconds != null) 'durationSeconds': durationSeconds,
    if (availableAt != null)
      'availableAt': availableAt!.toUtc().toIso8601String(),
  };

  @override
  List<Object?> get props => [
    ref,
    title,
    position,
    absoluteEpisode,
    description,
    artwork,
    durationSeconds,
    availableAt,
  ];
}

/// An extension-defined episode grouping such as a season or volume.
class EpisodeGroup extends Equatable {
  /// Creates an extension-defined episode group.
  const EpisodeGroup({
    required this.id,
    required this.title,
    required this.episodes,
    this.loaded = true,
  });

  /// Decodes and validates an episode group.
  factory EpisodeGroup.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'id',
      'title',
      'episodes',
      'loaded',
    }, 'episode group');
    final episodes = json['episodes'];
    final loaded = json['loaded'];
    if (episodes is! List) {
      throw const FormatException('episodeGroup.episodes must be a list');
    }
    if (loaded != null && loaded is! bool) {
      throw const FormatException('episodeGroup.loaded must be a boolean');
    }
    return EpisodeGroup(
      id: _requiredString(json['id'], 'episodeGroup.id'),
      title: _requiredString(json['title'], 'episodeGroup.title'),
      episodes: [
        for (final entry in episodes)
          EpisodeSummary.fromJson(_object(entry, 'episodeGroup.episodes[]')),
      ],
      loaded: loaded as bool? ?? true,
    );
  }

  /// Opaque stable group identifier.
  final String id;

  /// Display title for the group selector.
  final String title;

  /// Episodes in display order.
  final List<EpisodeSummary> episodes;

  /// Whether [episodes] is complete. False means the group is a lazy
  /// placeholder and the host should request that group before playback.
  final bool loaded;

  /// Encodes this episode group.
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'episodes': episodes.map((episode) => episode.toJson()).toList(),
    if (!loaded) 'loaded': false,
  };

  @override
  List<Object?> get props => [id, title, episodes, loaded];
}

/// Typed navigation data for episodic content.
class EpisodeGuide extends Equatable {
  /// Creates an episode guide.
  const EpisodeGuide({required this.groups, this.defaultEpisodeRef});

  /// Decodes and validates an episode guide.
  factory EpisodeGuide.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'groups',
      'defaultEpisodeRef',
    }, 'episode guide');
    final groups = json['groups'];
    if (groups is! List) {
      throw const FormatException('episodeGuide.groups must be a list');
    }
    final decodedGroups = [
      for (final entry in groups)
        EpisodeGroup.fromJson(_object(entry, 'episodeGuide.groups[]')),
    ];
    final defaultRef = json['defaultEpisodeRef'] == null
        ? null
        : _requiredRef(
            json['defaultEpisodeRef'],
            'episodeGuide.defaultEpisodeRef',
          );
    if (defaultRef != null &&
        !decodedGroups.any(
          (group) => group.episodes.any((episode) => episode.ref == defaultRef),
        )) {
      throw const FormatException(
        'episodeGuide.defaultEpisodeRef must reference a listed episode',
      );
    }
    return EpisodeGuide(groups: decodedGroups, defaultEpisodeRef: defaultRef);
  }

  /// Groups in display order.
  final List<EpisodeGroup> groups;

  /// Episode selected by the primary play action when present.
  final MediaRef? defaultEpisodeRef;

  /// Encodes this episode guide.
  Map<String, Object?> toJson() => {
    'groups': groups.map((group) => group.toJson()).toList(),
    if (defaultEpisodeRef != null)
      'defaultEpisodeRef': defaultEpisodeRef!.toJson(),
  };

  @override
  List<Object?> get props => [groups, defaultEpisodeRef];
}

/// A group of related movie items supplied by an extension.
class MediaCollectionV2 extends Equatable {
  /// Creates a collection shelf.
  const MediaCollectionV2({
    required this.id,
    required this.name,
    required this.items,
  });

  /// Decodes and validates a collection shelf.
  factory MediaCollectionV2.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {'id', 'name', 'items'}, 'detail.collection');
    final id = json['id'];
    final name = json['name'];
    final items = json['items'];
    if (id is! String || id.isEmpty) {
      throw const FormatException(
        'detail.collection.id must be a non-empty string',
      );
    }
    if (name is! String || name.isEmpty) {
      throw const FormatException(
        'detail.collection.name must be a non-empty string',
      );
    }
    if (items is! List) {
      throw const FormatException('detail.collection.items must be a list');
    }
    return MediaCollectionV2(
      id: id,
      name: name,
      items: [
        for (final item in items)
          MediaItemV2.fromJson(_object(item, 'detail.collection.items[]')),
      ],
    );
  }

  /// Stable TMDB or extension-defined collection identifier.
  final String id;

  /// Display name for the collection section.
  final String name;

  /// Items in the collection, in extension-defined display order.
  final List<MediaItemV2> items;

  /// Encodes this collection shelf.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'items': items.map((item) => item.toJson()).toList(),
  };

  @override
  List<Object?> get props => [id, name, items];
}

/// Strict protocol-v2 detail response.
class MediaDetailV2 extends Equatable {
  /// Creates a protocol-v2 detail response.
  const MediaDetailV2({
    required this.item,
    this.description,
    this.tags = const [],
    this.facts = const [],
    this.credits = const [],
    this.trailers = const [],
    this.collection,
    this.recommendations = const [],
    this.episodeGuide,
    this.channelGuide,
  });

  /// Decodes and validates a protocol-v2 detail response.
  factory MediaDetailV2.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {
      'item',
      'description',
      'tags',
      'facts',
      'credits',
      'trailers',
      'collection',
      'recommendations',
      'episodeGuide',
      'channelGuide',
    }, 'media detail');
    final tags = json['tags'];
    if (tags != null && tags is! List) {
      throw const FormatException('detail.tags must be a list');
    }
    final facts = json['facts'];
    if (facts != null && facts is! List) {
      throw const FormatException('detail.facts must be a list');
    }
    final credits = json['credits'];
    if (credits != null && credits is! List) {
      throw const FormatException('detail.credits must be a list');
    }
    final trailers = json['trailers'];
    if (trailers != null && trailers is! List) {
      throw const FormatException('detail.trailers must be a list');
    }
    final recommendations = json['recommendations'];
    if (recommendations != null && recommendations is! List) {
      throw const FormatException('detail.recommendations must be a list');
    }
    final collection = json['collection'];
    if (collection != null && collection is! Map) {
      throw const FormatException('detail.collection must be an object');
    }
    return MediaDetailV2(
      item: MediaItemV2.fromJson(_object(json['item'], 'detail.item')),
      description: _optionalString(json['description'], 'detail.description'),
      tags: [
        for (final tag in (tags as List?) ?? const [])
          _requiredString(tag, 'detail.tags[]'),
      ],
      facts: [
        for (final fact in (facts as List?) ?? const [])
          MediaFact.fromJson(_object(fact, 'detail.facts[]')),
      ],
      credits: [
        for (final credit in (credits as List?) ?? const [])
          MediaCredit.fromJson(_object(credit, 'detail.credits[]')),
      ],
      trailers: [
        for (final trailer in (trailers as List?) ?? const [])
          MediaTrailer.fromJson(_object(trailer, 'detail.trailers[]')),
      ],
      collection: collection == null
          ? null
          : MediaCollectionV2.fromJson(
              _object(collection, 'detail.collection'),
            ),
      recommendations: [
        for (final recommendation in (recommendations as List?) ?? const [])
          MediaItemV2.fromJson(
            _object(recommendation, 'detail.recommendations[]'),
          ),
      ],
      episodeGuide: json['episodeGuide'] == null
          ? null
          : EpisodeGuide.fromJson(
              _object(json['episodeGuide'], 'detail.episodeGuide'),
            ),
      channelGuide: json['channelGuide'] == null
          ? null
          : ChannelGuideV2.fromJson(
              _object(json['channelGuide'], 'detail.channelGuide'),
            ),
    );
  }

  /// Canonical item rendered by the detail header.
  final MediaItemV2 item;

  /// Optional long-form description.
  final String? description;

  /// Short classification labels rendered as chips or inline text.
  final List<String> tags;

  /// Display-only labelled metadata.
  final List<MediaFact> facts;

  /// Credited people or entities in extension-defined order.
  final List<MediaCredit> credits;

  /// Optional preview videos in extension-defined display order.
  final List<MediaTrailer> trailers;

  /// Optional related movie collection shown above recommendations.
  final MediaCollectionV2? collection;

  /// Optional related items shown in a recommendation shelf at the bottom.
  final List<MediaItemV2> recommendations;

  /// Optional navigation data for episodic content.
  final EpisodeGuide? episodeGuide;

  /// Optional programme data for continuously available channels.
  final ChannelGuideV2? channelGuide;

  /// Encodes this detail response.
  Map<String, Object?> toJson() => {
    'item': item.toJson(),
    if (description != null) 'description': description,
    if (tags.isNotEmpty) 'tags': tags,
    if (facts.isNotEmpty) 'facts': facts.map((fact) => fact.toJson()).toList(),
    if (credits.isNotEmpty)
      'credits': credits.map((credit) => credit.toJson()).toList(),
    if (trailers.isNotEmpty)
      'trailers': trailers.map((trailer) => trailer.toJson()).toList(),
    if (collection != null) 'collection': collection!.toJson(),
    if (recommendations.isNotEmpty)
      'recommendations': recommendations
          .map((recommendation) => recommendation.toJson())
          .toList(),
    if (episodeGuide != null) 'episodeGuide': episodeGuide!.toJson(),
    if (channelGuide != null) 'channelGuide': channelGuide!.toJson(),
  };

  @override
  List<Object?> get props => [
    item,
    description,
    tags,
    facts,
    credits,
    trailers,
    collection,
    recommendations,
    episodeGuide,
    channelGuide,
  ];
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map) throw FormatException('$path must be an object');
  return value.cast<String, Object?>();
}

String _requiredString(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$path must be a non-empty string');
  }
  return value;
}

String? _optionalString(Object? value, String path) {
  if (value == null) return null;
  return _requiredString(value, path);
}

String _requiredHttpUrl(Object? value, String path) {
  final url = _requiredString(value, path);
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.host.isEmpty ||
      !{'http', 'https'}.contains(uri.scheme)) {
    throw FormatException('$path must be an absolute http(s) URL');
  }
  return url;
}

MediaRef _requiredRef(Object? value, String path) =>
    MediaRef.fromJson(_object(value, path));

Artwork? _optionalArtwork(Object? value, String path) =>
    value == null ? null : Artwork.fromJson(_object(value, path));

ImageRef? _optionalImage(Object? value, String path) {
  if (value == null) return null;
  final image = ImageRef.fromJson(_object(value, path));
  final uri = Uri.tryParse(image!.url);
  if (uri == null || !uri.isAbsolute || !uri.hasAuthority) {
    throw FormatException('$path.url must be an absolute URL');
  }
  return image;
}

DateTime? _optionalUtc(Object? value, String path) {
  if (value == null) return null;
  if (value is! String || !value.toUpperCase().endsWith('Z')) {
    throw FormatException('$path must be an ISO-8601 UTC timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$path must be an ISO-8601 UTC timestamp');
  }
  return parsed;
}

DateTime _requiredUtc(Object? value, String path) =>
    _optionalUtc(value, path) ??
    (throw FormatException('$path must be an ISO-8601 UTC timestamp'));

void _rejectUnknown(
  Map<String, Object?> json,
  Set<String> allowed,
  String context,
) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$context contains unsupported field "$key"');
    }
  }
}
