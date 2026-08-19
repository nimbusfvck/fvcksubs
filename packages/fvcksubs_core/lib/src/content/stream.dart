import 'package:equatable/equatable.dart';

import '../json_util.dart';

/// Container format of a stream.
enum StreamFormat {
  /// MPEG-DASH (`.mpd`).
  dash,

  /// HLS (`.m3u8`).
  hls,

  /// Anything else, or unknown (the fallback on decode).
  other,
}

/// DRM scheme the app understands.
///
/// Only [clearKey] and [widevine] can reach a player (both the Android
/// ExoPlayer path). [unsupported] marks a source asking for anything else
/// (e.g. PlayReady) — kept as-is so the UI can say so honestly instead of
/// silently trying to play and failing.
enum DrmScheme {
  /// EME ClearKey; keys arrive inline as JSON, no license server.
  clearKey,

  /// Widevine; needs a license server URL.
  widevine,

  /// Any scheme the app can't play (e.g. PlayReady); kept so the UI can say so.
  unsupported,
}

/// Ready-to-use DRM configuration for a stream.
class DrmConfig extends Equatable {
  /// Creates a DRM configuration.
  const DrmConfig({required this.scheme, this.licenseUrl, this.clearKeyJson});

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
    );
  }

  /// Scheme of this source.
  final DrmScheme scheme;

  /// License server URL, for [DrmScheme.widevine].
  final String? licenseUrl;

  /// Ready-to-use ClearKey license JSON, for [DrmScheme.clearKey].
  final String? clearKeyJson;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'scheme': scheme.name,
    if (licenseUrl != null) 'licenseUrl': licenseUrl,
    if (clearKeyJson != null) 'clearKeyJson': clearKeyJson,
  };

  @override
  List<Object?> get props => [scheme, licenseUrl, clearKeyJson];
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
  });

  /// Builds a [SubtitleTrack] from decoded JSON.
  factory SubtitleTrack.fromJson(Map<String, Object?> json) => SubtitleTrack(
    language: json['language'] as String,
    url: json['url'] as String,
    label: (json['label'] as String?) ?? '',
  );

  /// BCP-47-ish language code, whatever the upstream sends (`"en"`, `"pt-BR"`).
  final String language;

  /// Subtitle file URL (`.srt` or `.vtt`; the player sniffs which).
  final String url;

  /// Display name (e.g. the upstream's own release-name label), or empty to
  /// fall back to [language].
  final String label;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'language': language,
    'url': url,
    if (label.isNotEmpty) 'label': label,
  };

  @override
  List<Object?> get props => [language, url, label];
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
    this.format = StreamFormat.other,
    this.drm,
    this.audioUrl,
    this.label = '',
    this.subtitles = const [],
  });

  /// Builds a [PlayableStream] from decoded JSON.
  factory PlayableStream.fromJson(Map<String, Object?> json) => PlayableStream(
    url: json['url'] as String,
    headers: stringMap(json['headers']),
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
  );

  /// Final stream URL.
  final String url;

  /// HTTP headers that must accompany playback.
  final Map<String, String> headers;

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

  /// Whether this stream is DRM-protected.
  bool get isProtected => drm != null;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'url': url,
    if (headers.isNotEmpty) 'headers': headers,
    'format': format.name,
    if (drm != null) 'drm': drm!.toJson(),
    if (audioUrl != null) 'audioUrl': audioUrl,
    if (label.isNotEmpty) 'label': label,
    if (subtitles.isNotEmpty)
      'subtitles': subtitles.map((s) => s.toJson()).toList(),
  };

  @override
  List<Object?> get props => [
    url,
    headers,
    format,
    drm,
    audioUrl,
    label,
    subtitles,
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
  });

  /// Builds a [StreamSource] from decoded JSON.
  factory StreamSource.fromJson(Map<String, Object?> json) => StreamSource(
    id: json['id'] as String,
    label: json['label'] as String,
    provider: (json['provider'] as String?) ?? '',
  );

  /// Source id, valid for the current lookup session; passed back to resolve.
  final String id;

  /// Label shown to the user.
  final String label;

  /// Provider this source came from; the picker groups by it. Empty if unknown.
  final String provider;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (provider.isNotEmpty) 'provider': provider,
  };

  @override
  List<Object?> get props => [id, label, provider];
}
