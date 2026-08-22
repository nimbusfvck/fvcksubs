import 'package:equatable/equatable.dart';

import 'media_item_v2.dart';
import 'media_ref.dart';

/// Protocol-v2 item envelope used by the current catalog and search APIs.
class VersionedMediaItem extends Equatable {
  /// Creates a protocol-v2 catalog item envelope.
  const VersionedMediaItem({required this.item});

  /// Decodes an item according to the extension's declared API version.
  factory VersionedMediaItem.fromProtocolJson(
    Map<String, Object?> json, {
    required int apiVersion,
  }) {
    if (apiVersion != 2) {
      throw FormatException('Unsupported media item apiVersion: $apiVersion');
    }
    return VersionedMediaItem(item: MediaItemV2.fromJson(json));
  }

  /// Restores an envelope saved by [toJson].
  factory VersionedMediaItem.fromJson(Map<String, Object?> json) {
    final item = json['item'];
    if (item is! Map) {
      throw const FormatException(
        'versioned media item.item must be an object',
      );
    }
    return VersionedMediaItem(
      item: MediaItemV2.fromJson(item.cast<String, Object?>()),
    );
  }

  /// Strict item used by version-2 app consumers.
  /// Decoded protocol-v2 item.
  final MediaItemV2 item;

  /// Stable reference of the wrapped item.
  MediaRef get ref => item.ref;

  /// Display title of the wrapped item.
  String get title => item.title;

  /// Optional subtitle of the wrapped item.
  String? get subtitle => item.subtitle;

  /// Kind discriminator of the wrapped item.
  MediaKindV2 get kind => item.kind;

  /// Encodes the envelope for persistence.
  Map<String, Object?> toJson() => {'item': item.toJson()};

  @override
  List<Object?> get props => [item];
}
