import 'package:equatable/equatable.dart';

/// Fully-qualified address of a content item across every installed extension.
///
/// [id] is opaque to the app: it belongs to the extension, which is handed the
/// same [MediaRef] back to resolve metadata or sources. [extensionId] +
/// [providerId] route it to the right code.
class MediaRef extends Equatable {
  /// Creates a media reference.
  const MediaRef({
    required this.extensionId,
    required this.providerId,
    required this.id,
  });

  /// Builds a [MediaRef] from decoded JSON.
  factory MediaRef.fromJson(Map<String, Object?> json) => MediaRef(
    extensionId: json['extensionId'] as String,
    providerId: json['providerId'] as String,
    id: json['id'] as String,
  );

  /// Installed extension this item came from (e.g. `cricfy`).
  final String extensionId;

  /// Provider within the extension (e.g. `cricfy.events`).
  final String providerId;

  /// Extension-private id. Opaque to the app.
  final String id;

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'extensionId': extensionId,
    'providerId': providerId,
    'id': id,
  };

  @override
  List<Object?> get props => [extensionId, providerId, id];
}
