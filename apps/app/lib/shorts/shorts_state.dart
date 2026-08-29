import 'package:fvcksubs_core/fvcksubs_core.dart';

/// Where an item's preview stands in the just-in-time resolution flow.
enum PreviewStatus { unresolved, resolving, usable, unusable }

/// One item's preview-resolution result. [source] is set only when
/// [status] is [PreviewStatus.usable] — the first [PreviewSource] in the
/// extension's response this app actually has a player for.
class PreviewResolution {
  const PreviewResolution({
    this.status = PreviewStatus.unresolved,
    this.source,
  });

  final PreviewStatus status;
  final PreviewSource? source;
}

/// Overall Shorts feed load state.
enum ShortsStatus { initial, loading, usable, empty, error }

class ShortsState {
  const ShortsState({
    this.status = ShortsStatus.initial,
    this.items = const [],
    this.error,
    this.previews = const {},
    this.details = const {},
  });

  /// Load status. [items] can be non-empty while this is [ShortsStatus.error]
  /// (a refresh failed but the previous feed is still shown) — check
  /// [items] to decide what to render, [status] for loading/error chrome.
  final ShortsStatus status;

  /// The feed, de-duplicated by [MediaRef] and in the extensions' declared
  /// order. The app never re-sorts this.
  final List<VersionedMediaItem> items;

  final Object? error;

  /// Per-item preview resolution, keyed by [_refKey]. Absent means
  /// [PreviewStatus.unresolved] — nothing has asked for it yet.
  final Map<String, PreviewResolution> previews;

  /// Per-item prefetched detail (only ever populated for a [SeriesItemV2] —
  /// see `ShortsController.ensureDetailFetched`), keyed by [_refKey].
  final Map<String, MediaDetailV2> details;

  bool get isLoading => status == ShortsStatus.loading;

  PreviewResolution previewFor(MediaRef ref) =>
      previews[_refKey(ref)] ?? const PreviewResolution();

  MediaDetailV2? detailFor(MediaRef ref) => details[_refKey(ref)];

  ShortsState copyWith({
    ShortsStatus? status,
    List<VersionedMediaItem>? items,
    Object? error,
    bool clearError = false,
    Map<String, PreviewResolution>? previews,
    Map<String, MediaDetailV2>? details,
  }) => ShortsState(
    status: status ?? this.status,
    items: items ?? this.items,
    error: clearError ? null : error ?? this.error,
    previews: previews ?? this.previews,
    details: details ?? this.details,
  );
}

String _refKey(MediaRef ref) => '${ref.extensionId}/${ref.providerId}/${ref.id}';
