import 'package:equatable/equatable.dart';

/// A reference to a remote image (poster, logo, thumbnail).
///
/// A type rather than a bare `String` so the protocol can grow image concerns
/// (headers for referer-gated CDNs, intrinsic size) without reshaping every
/// field that holds one.
class ImageRef extends Equatable {
  /// Creates an image reference.
  const ImageRef(this.url);

  /// Builds an [ImageRef] from decoded JSON, or `null`.
  static ImageRef? fromJson(Object? json) {
    if (json == null) return null;
    return ImageRef((json as Map)['url'] as String);
  }

  /// Absolute image URL.
  final String url;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {'url': url};

  @override
  List<Object?> get props => [url];
}
