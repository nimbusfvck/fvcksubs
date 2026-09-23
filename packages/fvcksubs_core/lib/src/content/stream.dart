import 'package:equatable/equatable.dart';

import '../json_util.dart';

/// Container format of a stream.
enum StreamFormat {
  /// MPEG-DASH (`.mpd`).
  dash,

  /// HLS (`.m3u8`).
  hls,

  /// MPEG-4 progressive download (`.mp4`), including extensionless MP4 URLs.
  mp4,

  /// Anything else, or unknown (the fallback on decode).
  other,
}

/// DRM scheme the app understands.
///
/// [widevine] reaches Android's Media3/ExoPlayer path and [fairPlay] reaches
/// Apple's AVFoundation path. [clearKey] is supported by the Android
/// implementation when [DrmConfig.clearKeyJson] contains an inline key set.
/// [unsupported] remains represented so the UI can report it.
enum DrmScheme {
  /// EME ClearKey; keys arrive inline as JSON, with no license server.
  clearKey,

  /// Widevine; needs a license server URL.
  widevine,

  /// Apple FairPlay Streaming; needs a certificate and license URL.
  fairPlay,

  /// Any scheme the app can't play (e.g. PlayReady); kept so the UI can say so.
  unsupported,
}

/// Ready-to-use DRM configuration for a stream.
class DrmConfig extends Equatable {
  /// Creates a DRM configuration.
  const DrmConfig({
    required this.scheme,
    this.licenseUrl,
    this.clearKeyJson,
    this.certificateUrl,
    this.contentId,
  });

  /// Builds a [DrmConfig] from decoded JSON, or `null`.
  static DrmConfig? fromJson(Object? json) {
    if (json == null) return null;
    final map = json as Map<String, Object?>;
    return DrmConfig(
      scheme: enumByName(
        DrmScheme.values,
        map['scheme'],
        orElse: DrmScheme.unsupported,
      ),
      licenseUrl: map['licenseUrl'] as String?,
      clearKeyJson: map['clearKeyJson'] as String?,
      certificateUrl: map['certificateUrl'] as String?,
      contentId: map['contentId'] as String?,
    );
  }

  /// Scheme of this source.
  final DrmScheme scheme;

  /// License server URL, for [DrmScheme.widevine].
  final String? licenseUrl;

  /// Ready-to-use ClearKey license JSON, for [DrmScheme.clearKey].
  final String? clearKeyJson;

  /// FairPlay application certificate URL, for [DrmScheme.fairPlay].
  final String? certificateUrl;

  /// Optional FairPlay content identifier used when generating the SPC.
  final String? contentId;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'scheme': scheme.name,
    if (licenseUrl != null) 'licenseUrl': licenseUrl,
    if (clearKeyJson != null) 'clearKeyJson': clearKeyJson,
    if (certificateUrl != null) 'certificateUrl': certificateUrl,
    if (contentId != null) 'contentId': contentId,
  };

  @override
  List<Object?> get props => [
    scheme,
    licenseUrl,
    clearKeyJson,
    certificateUrl,
    contentId,
  ];
}

/// One subtitle/caption track alongside a [PlayableStream].
///
/// Subtitle tracks are returned by `resolve()` rather than through a separate
/// extension role. The player detects SRT or VTT from the response content,
/// so the protocol does not carry a format field.
class SubtitleTrack extends Equatable {
  /// Creates a subtitle track.
  const SubtitleTrack({
    required this.language,
    required this.url,
    this.label = '',
    this.headers = const {},
  });

  /// Builds a [SubtitleTrack] from decoded JSON.
  factory SubtitleTrack.fromJson(Map<String, Object?> json) => SubtitleTrack(
    language: json['language'] as String,
    url: json['url'] as String,
    label: (json['label'] as String?) ?? '',
    headers: stringMap(json['headers']),
  );

  /// BCP-47-ish language code, whatever the upstream sends (`"en"`, `"pt-BR"`).
  final String language;

  /// Subtitle file URL (`.srt` or `.vtt`; the player sniffs which).
  final String url;

  /// Display name (e.g. the upstream's own release-name label), or empty to
  /// fall back to [language].
  final String label;

  /// HTTP headers required to download this subtitle file.
  final Map<String, String> headers;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'language': language,
    'url': url,
    if (label.isNotEmpty) 'label': label,
    if (headers.isNotEmpty) 'headers': headers,
  };

  @override
  List<Object?> get props => [language, url, label, headers];
}

/// One alternate rendition of a [PlayableStream].
///
/// Variants are session-scoped: providers may return signed URLs here, so a
/// caller should use them for the current playback session and resolve the
/// source again after they expire.
class StreamVariant extends Equatable {
  /// Creates an alternate rendition.
  const StreamVariant({
    required this.id,
    required this.url,
    this.headers = const {},
    this.format = StreamFormat.other,
    this.label = '',
    this.width,
    this.height,
    this.bitrate,
  });

  /// Builds a variant from decoded JSON.
  factory StreamVariant.fromJson(Map<String, Object?> json) => StreamVariant(
    id: json['id'] as String,
    url: json['url'] as String,
    headers: stringMap(json['headers']),
    format: enumByName(
      StreamFormat.values,
      json['format'],
      orElse: StreamFormat.other,
    ),
    label: (json['label'] as String?) ?? '',
    width: (json['width'] as num?)?.toInt(),
    height: (json['height'] as num?)?.toInt(),
    bitrate: (json['bitrate'] as num?)?.toInt(),
  );

  /// Stable only within the current resolve response.
  final String id;

  /// Final URL for this rendition.
  final String url;

  /// HTTP headers required by this rendition.
  final Map<String, String> headers;

  /// Container format.
  final StreamFormat format;

  /// Display label, normally `360p`, `720p`, or `1080p`.
  final String label;

  /// Frame width, when known.
  final int? width;

  /// Frame height, when known.
  final int? height;

  /// Bitrate in bits per second, when known.
  final int? bitrate;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'id': id,
    'url': url,
    if (headers.isNotEmpty) 'headers': headers,
    'format': format.name,
    if (label.isNotEmpty) 'label': label,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (bitrate != null) 'bitrate': bitrate,
  };

  @override
  List<Object?> get props => [
    id,
    url,
    headers,
    format,
    label,
    width,
    height,
    bitrate,
  ];
}

/// One playable stream produced by resolving a [StreamSource].
///
/// [headers] must be sent with playback (`User-Agent`, `Referer`): many edges
/// 302 away requests that lack them. This is the `resolve` response — the
/// protocol's `PlayableStream`.
class PlayableStream extends Equatable {
  /// Creates a playable stream.
  const PlayableStream({
    required this.url,
    this.headers = const {},
    this.playlistHeaders = const {},
    this.segmentHeaders = const {},
    this.format = StreamFormat.other,
    this.drm,
    this.audioUrl,
    this.label = '',
    this.subtitles = const [],
    this.variants = const [],
  });

  /// Builds a [PlayableStream] from decoded JSON.
  factory PlayableStream.fromJson(Map<String, Object?> json) => PlayableStream(
    url: json['url'] as String,
    headers: stringMap(json['headers']),
    playlistHeaders: stringMap(json['playlistHeaders']),
    segmentHeaders: stringMap(json['segmentHeaders']),
    format: enumByName(
      StreamFormat.values,
      json['format'],
      orElse: StreamFormat.other,
    ),
    drm: DrmConfig.fromJson(json['drm']),
    audioUrl: json['audioUrl'] as String?,
    label: (json['label'] as String?) ?? '',
    subtitles: ((json['subtitles'] as List?) ?? const [])
        .map((e) => SubtitleTrack.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
    variants: ((json['variants'] as List?) ?? const [])
        .map((e) => StreamVariant.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
  );

  /// Final stream URL.
  final String url;

  /// HTTP headers that must accompany playback.
  final Map<String, String> headers;

  /// Optional headers for the root and nested HLS playlists.
  ///
  /// When empty, [headers] is used. This supports origins that reject a
  /// `Referer` on the manifest but require it for media segments.
  final Map<String, String> playlistHeaders;

  /// Optional headers for HLS media segments.
  ///
  /// When empty, [headers] is used. The app's live HLS proxy applies this to
  /// segment requests after rewriting the playlist.
  final Map<String, String> segmentHeaders;

  /// Container format.
  final StreamFormat format;

  /// DRM configuration, `null` when the stream is clear.
  final DrmConfig? drm;

  /// Separate audio track URL, or `null`.
  final String? audioUrl;

  /// Source label (e.g. the picked link's name).
  final String label;

  /// Subtitle tracks offered alongside this stream. Empty is the normal case
  /// — most sources carry none.
  final List<SubtitleTrack> subtitles;

  /// Alternate renditions offered alongside this stream.
  final List<StreamVariant> variants;

  /// Whether this stream is DRM-protected.
  bool get isProtected => drm != null;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'url': url,
    if (headers.isNotEmpty) 'headers': headers,
    if (playlistHeaders.isNotEmpty) 'playlistHeaders': playlistHeaders,
    if (segmentHeaders.isNotEmpty) 'segmentHeaders': segmentHeaders,
    'format': format.name,
    if (drm != null) 'drm': drm!.toJson(),
    if (audioUrl != null) 'audioUrl': audioUrl,
    if (label.isNotEmpty) 'label': label,
    if (subtitles.isNotEmpty)
      'subtitles': subtitles.map((s) => s.toJson()).toList(),
    if (variants.isNotEmpty)
      'variants': variants.map((variant) => variant.toJson()).toList(),
  };

  @override
  List<Object?> get props => [
    url,
    headers,
    playlistHeaders,
    segmentHeaders,
    format,
    drm,
    audioUrl,
    label,
    subtitles,
    variants,
  ];
}

/// One broadcast link before it's resolved into a [PlayableStream].
///
/// Deliberately light: only what the source picker needs. The real resolution
/// — extra network calls, time-based URL signing — happens when the user picks
/// one. This is the `sources` response element — the protocol's `StreamSource`.
class StreamSource extends Equatable {
  /// Creates a stream source.
  const StreamSource({
    required this.id,
    required this.label,
    this.provider = '',
    this.providerId = '',
  });

  /// Builds a [StreamSource] from decoded JSON.
  factory StreamSource.fromJson(Map<String, Object?> json) => StreamSource(
    id: json['id'] as String,
    label: json['label'] as String,
    provider: (json['provider'] as String?) ?? '',
    providerId: (json['providerId'] as String?) ?? '',
  );

  /// Source id, valid for the current lookup session; passed back to resolve.
  final String id;

  /// Label shown to the user.
  final String label;

  /// Provider this source came from; the picker groups by it. Empty if unknown.
  final String provider;

  /// Stable manifest provider id used for preferences and routing metadata.
  final String providerId;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (provider.isNotEmpty) 'provider': provider,
    if (providerId.isNotEmpty) 'providerId': providerId,
  };

  @override
  List<Object?> get props => [id, label, provider, providerId];
}
