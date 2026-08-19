import 'package:equatable/equatable.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

/// App-owned state for one piece of content — the first and only state the
/// app itself owns (PLAN.md §14). Favourite/watched are independent flags on
/// the same record, not separate lists: an item can be both, or either.
///
/// Carries a snapshot [item] rather than just a bare [MediaRef]. PLAN.md's
/// original sketch was ref-only, resolved back to a [MediaItem] through
/// `meta()` on render — deferred here in favour of the snapshot: `meta()` was
/// unimplemented for every extension, its JSON shape is a real, separately-
/// verified integration (see `By433MatchDetail`), and Library's own read path
/// doesn't need it — the item is already in hand at the moment it's
/// favourited or watched. `meta()` now exists for `fvck` and stays available
/// for whoever needs *fresher-than-snapshot* data later (a refresh action, or
/// `liveUpdate` polling per §13) — Library just doesn't have to block on it.
class UserMediaState extends Equatable {
  /// Creates a record.
  const UserMediaState({
    required this.ref,
    required this.item,
    this.favorite = false,
    this.progress,
    this.lastWatched,
  });

  /// Builds a [UserMediaState] from decoded JSON.
  factory UserMediaState.fromJson(Map<String, Object?> json) =>
      UserMediaState(
        ref: MediaRef.fromJson(json['ref']! as Map<String, Object?>),
        item: MediaItem.fromJson(json['item']! as Map<String, Object?>),
        favorite: json['favorite'] as bool? ?? false,
        progress: (json['progressMs'] as num?) == null
            ? null
            : Duration(milliseconds: (json['progressMs'] as num).toInt()),
        lastWatched: (json['lastWatched'] as String?) == null
            ? null
            : DateTime.parse(json['lastWatched']! as String),
      );

  /// What this record is about.
  final MediaRef ref;

  /// Snapshot of the item as last seen — see the class doc for why.
  final MediaItem item;

  /// Whether the user favourited this item.
  final bool favorite;

  /// Playback position last time this was watched, or `null` if never
  /// started (or already finished and cleared).
  final Duration? progress;

  /// When this was last watched, or `null` if never.
  final DateTime? lastWatched;

  /// A stable map key for [ref] — extensions own opaque, extension-scoped
  /// ids, so the key has to include [MediaRef.extensionId] and
  /// [MediaRef.providerId] too or two extensions' ids could collide.
  static String keyFor(MediaRef ref) =>
      '${ref.extensionId}/${ref.providerId}/${ref.id}';

  /// This record's own key — see [keyFor].
  String get key => keyFor(ref);

  /// Returns a copy with the given fields replaced.
  UserMediaState copyWith({
    MediaItem? item,
    bool? favorite,
    Object? progress = _unset,
    Object? lastWatched = _unset,
  }) => UserMediaState(
    ref: ref,
    item: item ?? this.item,
    favorite: favorite ?? this.favorite,
    progress: identical(progress, _unset) ? this.progress : progress as Duration?,
    lastWatched: identical(lastWatched, _unset)
        ? this.lastWatched
        : lastWatched as DateTime?,
  );

  static const Object _unset = Object();

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'ref': ref.toJson(),
    'item': item.toJson(),
    'favorite': favorite,
    if (progress != null) 'progressMs': progress!.inMilliseconds,
    if (lastWatched != null) 'lastWatched': lastWatched!.toIso8601String(),
  };

  @override
  List<Object?> get props => [ref, item, favorite, progress, lastWatched];
}
