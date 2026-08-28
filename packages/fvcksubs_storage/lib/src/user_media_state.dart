import 'package:equatable/equatable.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

/// App-owned library and playback state for a protocol-v2 item.
class UserMediaState extends Equatable {
  /// Creates a persisted item snapshot.
  const UserMediaState({
    required this.item,
    this.contentRating = ContentRating.unknown,
    this.favorite = false,
    this.reminder = false,
    this.progress,
    this.duration,
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
    final duration = json['durationMs'];
    if (duration != null &&
        (duration is! num || duration.toInt() != duration || duration <= 0)) {
      throw const FormatException(
        'library durationMs must be a positive integer',
      );
    }
    if (lastWatched != null && lastWatched is! String) {
      throw const FormatException('library lastWatched must be a string');
    }
    final favorite = json['favorite'];
    if (favorite != null && favorite is! bool) {
      throw const FormatException('library favorite must be a boolean');
    }
    final reminder = json['reminder'];
    if (reminder != null && reminder is! bool) {
      throw const FormatException('library reminder must be a boolean');
    }
    return UserMediaState(
      item: MediaItemV2.fromJson(item.cast<String, Object?>()),
      contentRating: ContentRating.values.firstWhere(
        (value) => value.name == json['contentRating'],
        orElse: () => ContentRating.unknown,
      ),
      favorite: favorite as bool? ?? false,
      reminder: reminder as bool? ?? false,
      progress: progress == null
          ? null
          : Duration(milliseconds: (progress as num).toInt()),
      duration: duration == null
          ? null
          : Duration(milliseconds: (duration as num).toInt()),
      lastWatched: lastWatched == null
          ? null
          : DateTime.parse(lastWatched as String),
    );
  }

  /// Last known item data.
  final MediaItemV2 item;

  /// Audience classification captured when the item entered playback.
  ///
  /// Older records omit this field and remain visible for compatibility.
  final ContentRating contentRating;

  /// Stable content identity.
  MediaRef get ref => item.ref;

  /// Whether the item is in the user's favorites.
  final bool favorite;

  /// Whether the user asked to be reminded once this item releases.
  final bool reminder;

  /// Last playback position, when known.
  final Duration? progress;

  /// Total playback duration, when the native player reports one.
  final Duration? duration;

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
    ContentRating? contentRating,
    bool? favorite,
    bool? reminder,
    Object? progress = _unset,
    Object? duration = _unset,
    Object? lastWatched = _unset,
  }) => UserMediaState(
    item: item ?? this.item,
    contentRating: contentRating ?? this.contentRating,
    favorite: favorite ?? this.favorite,
    reminder: reminder ?? this.reminder,
    progress: identical(progress, _unset)
        ? this.progress
        : progress as Duration?,
    duration: identical(duration, _unset)
        ? this.duration
        : duration as Duration?,
    lastWatched: identical(lastWatched, _unset)
        ? this.lastWatched
        : lastWatched as DateTime?,
  );

  static const Object _unset = Object();

  /// Encodes this record.
  Map<String, Object?> toJson() => {
    'item': item.toJson(),
    if (contentRating != ContentRating.unknown)
      'contentRating': contentRating.name,
    'favorite': favorite,
    'reminder': reminder,
    if (progress != null) 'progressMs': progress!.inMilliseconds,
    if (duration != null) 'durationMs': duration!.inMilliseconds,
    if (lastWatched != null)
      'lastWatched': lastWatched!.toUtc().toIso8601String(),
  };

  @override
  List<Object?> get props => [
    item,
    contentRating,
    favorite,
    reminder,
    progress,
    duration,
    lastWatched,
  ];
}
