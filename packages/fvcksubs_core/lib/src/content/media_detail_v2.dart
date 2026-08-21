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

/// One playable entry in an episode guide.
class EpisodeSummary extends Equatable {
  /// Creates an episode summary.
  const EpisodeSummary({
    required this.ref,
    required this.title,
    required this.position,
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
      'description',
      'artwork',
      'durationSeconds',
      'availableAt',
    }, 'episode summary');
    final duration = json['durationSeconds'];
    final position = json['position'];
    if (position is! num || position.toInt() != position || position < 1) {
      throw const FormatException(
        'episode.position must be a positive integer',
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
  });

  /// Decodes and validates an episode group.
  factory EpisodeGroup.fromJson(Map<String, Object?> json) {
    _rejectUnknown(json, const {'id', 'title', 'episodes'}, 'episode group');
    final episodes = json['episodes'];
    if (episodes is! List) {
      throw const FormatException('episodeGroup.episodes must be a list');
    }
    return EpisodeGroup(
      id: _requiredString(json['id'], 'episodeGroup.id'),
      title: _requiredString(json['title'], 'episodeGroup.title'),
      episodes: [
        for (final entry in episodes)
          EpisodeSummary.fromJson(_object(entry, 'episodeGroup.episodes[]')),
      ],
    );
  }

  /// Opaque stable group identifier.
  final String id;

  /// Display title for the group selector.
  final String title;

  /// Episodes in display order.
  final List<EpisodeSummary> episodes;

  /// Encodes this episode group.
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'episodes': episodes.map((episode) => episode.toJson()).toList(),
  };

  @override
  List<Object?> get props => [id, title, episodes];
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
    this.recommendations = const [],
    this.episodeGuide,
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
      'recommendations',
      'episodeGuide',
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

  /// Optional related items shown in a recommendation shelf at the bottom.
  final List<MediaItemV2> recommendations;

  /// Optional navigation data for episodic content.
  final EpisodeGuide? episodeGuide;

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
    if (recommendations.isNotEmpty)
      'recommendations': recommendations
          .map((recommendation) => recommendation.toJson())
          .toList(),
    if (episodeGuide != null) 'episodeGuide': episodeGuide!.toJson(),
  };

  @override
  List<Object?> get props => [
    item,
    description,
    tags,
    facts,
    credits,
    trailers,
    recommendations,
    episodeGuide,
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
