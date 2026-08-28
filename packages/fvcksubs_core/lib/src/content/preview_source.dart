import 'package:equatable/equatable.dart';

import '../json_util.dart';
import 'stream.dart';

/// The two shapes a preview can arrive in.
enum PreviewSourceType {
  /// Played through a provider-specific embed (e.g. a YouTube video id).
  embedded,

  /// A directly playable [PlayableStream].
  direct,
}

/// One candidate preview source, in the extension's preferred order.
///
/// Use [PreviewSource.fromJson] at the extension boundary. Unlike
/// [MediaItemV2.fromJson]'s strict field rejection, an [EmbeddedPreviewSource]
/// with a [EmbeddedPreviewSource.provider] this app build doesn't recognize
/// still decodes successfully — it's the app's job to skip an unsupported
/// provider at render time, not the decoder's job to fail the whole
/// [PreviewResponse] over it.
sealed class PreviewSource extends Equatable {
  const PreviewSource({required this.id});

  /// Decodes the source variant selected by `type`.
  factory PreviewSource.fromJson(Map<String, Object?> json) {
    final type = enumByNameStrict(PreviewSourceType.values, json['type']);
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('preview source.id must be a non-empty string');
    }
    switch (type) {
      case PreviewSourceType.embedded:
        final provider = json['provider'];
        final mediaId = json['mediaId'];
        if (provider is! String || provider.isEmpty) {
          throw const FormatException(
            'embedded preview source.provider must be a non-empty string',
          );
        }
        if (mediaId is! String || mediaId.isEmpty) {
          throw const FormatException(
            'embedded preview source.mediaId must be a non-empty string',
          );
        }
        return EmbeddedPreviewSource(id: id, provider: provider, mediaId: mediaId);
      case PreviewSourceType.direct:
        final stream = json['stream'];
        if (stream is! Map) {
          throw const FormatException(
            'direct preview source.stream must be an object',
          );
        }
        return DirectPreviewSource(
          id: id,
          stream: PlayableStream.fromJson(stream.cast<String, Object?>()),
        );
    }
  }

  /// Source id, opaque to the app.
  final String id;

  /// This source's variant.
  PreviewSourceType get type;

  /// Encodes the selected variant.
  Map<String, Object?> toJson();

  @override
  List<Object?> get props => [id, type];
}

/// Played through a provider-specific embed rather than a direct URL.
///
/// [provider] is a plain string, not an enum: an unknown provider must still
/// decode so a [PreviewResponse] carrying a mix of known and unknown
/// providers doesn't fail outright. The app checks [provider] against the
/// embeds it has an adapter for and skips this source if it doesn't
/// recognize it.
final class EmbeddedPreviewSource extends PreviewSource {
  /// Creates an embedded preview source.
  const EmbeddedPreviewSource({
    required super.id,
    required this.provider,
    required this.mediaId,
  });

  /// Embed provider (`"youtube"`).
  final String provider;

  /// Provider-scoped media id (a YouTube video id, for `"youtube"`).
  final String mediaId;

  @override
  PreviewSourceType get type => PreviewSourceType.embedded;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'provider': provider,
    'mediaId': mediaId,
  };

  @override
  List<Object?> get props => [...super.props, provider, mediaId];
}

/// A directly playable [PlayableStream].
final class DirectPreviewSource extends PreviewSource {
  /// Creates a direct preview source.
  const DirectPreviewSource({required super.id, required this.stream});

  /// The stream to hand the player.
  final PlayableStream stream;

  @override
  PreviewSourceType get type => PreviewSourceType.direct;

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'stream': stream.toJson(),
  };

  @override
  List<Object?> get props => [...super.props, stream];
}

/// The result of resolving an item's preview.
///
/// Session-only: a direct source's URL may be signed or short-lived, so this
/// must never be persisted — every retry asks the extension again.
class PreviewResponse extends Equatable {
  /// Creates a preview response.
  const PreviewResponse({this.sources = const []});

  /// Builds a [PreviewResponse] from decoded JSON.
  factory PreviewResponse.fromJson(Map<String, Object?> json) {
    final sources = json['sources'];
    if (sources != null && sources is! List) {
      throw const FormatException('preview response.sources must be a list');
    }
    return PreviewResponse(
      sources: [
        for (final entry in (sources as List?) ?? const [])
          PreviewSource.fromJson((entry as Map).cast<String, Object?>()),
      ],
    );
  }

  /// Candidate sources, in the extension's preferred order. Empty means no
  /// usable preview was found for this item.
  final List<PreviewSource> sources;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'sources': sources.map((s) => s.toJson()).toList(),
  };

  @override
  List<Object?> get props => [sources];
}
