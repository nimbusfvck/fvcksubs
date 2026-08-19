import 'package:equatable/equatable.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

/// App-owned library and playback state for a protocol-v2 item.
class UserMediaState extends Equatable {
  /// Creates a persisted item snapshot.
  const UserMediaState({
    required this.item,
    this.favorite = false,
    this.progress,
    this.lastWatched,
  });

  /// Decodes a strict protocol-v2 record.
  factory UserMediaState.fromJson(Map<String, Object?> json) {
    final item = json['item'];
    if (item is! Map) {
      throw const FormatException('library item must be an object');
    }
    final progress = json['progressMs'];
    if (progress != null &&
        (progress is! num || progress.toInt() != progress || progress < 0)) {
      throw const FormatException(
        'library progressMs must be a non-negative integer',
      );
    }
    final lastWatched = json['lastWatched'];
    if (lastWatched != null && lastWatched is! String) {
      throw const FormatException('library lastWatched must be a string');
    }
    final favorite = json['favorite'];
    if (favorite != null && favorite is! bool) {
      throw const FormatException('library favorite must be a boolean');
    }
    return UserMediaState(
      item: MediaItemV2.fromJson(item.cast<String, Object?>()),
      favorite: favorite as bool? ?? false,
      progress: progress == null
          ? null
          : Duration(milliseconds: (progress as num).toInt()),
      lastWatched: lastWatched == null
          ? null
          : DateTime.parse(lastWatched as String),
    );
  }

  /// Last known item data.
  final MediaItemV2 item;

  /// Stable content identity.
  MediaRef get ref => item.ref;

  /// Whether the item is in the user's favorites.
  final bool favorite;

  /// Last playback position, when known.
  final Duration? progress;

  /// Last playback activity time, when known.
  final DateTime? lastWatched;

  /// Builds the stable storage key for [ref].
  static String keyFor(MediaRef ref) =>
      '${ref.extensionId}/${ref.providerId}/${ref.id}';

  /// Stable storage key for this record.
  String get key => keyFor(ref);

  /// Returns a copy with selected values replaced.
  UserMediaState copyWith({
    MediaItemV2? item,
    bool? favorite,
    Object? progress = _unset,
    Object? lastWatched = _unset,
  }) => UserMediaState(
    item: item ?? this.item,
    favorite: favorite ?? this.favorite,
    progress: identical(progress, _unset)
        ? this.progress
        : progress as Duration?,
    lastWatched: identical(lastWatched, _unset)
        ? this.lastWatched
        : lastWatched as DateTime?,
  );

  static const Object _unset = Object();

  /// Encodes this record.
  Map<String, Object?> toJson() => {
    'item': item.toJson(),
    'favorite': favorite,
    if (progress != null) 'progressMs': progress!.inMilliseconds,
    if (lastWatched != null)
      'lastWatched': lastWatched!.toUtc().toIso8601String(),
  };

  @override
  List<Object?> get props => [item, favorite, progress, lastWatched];
}
