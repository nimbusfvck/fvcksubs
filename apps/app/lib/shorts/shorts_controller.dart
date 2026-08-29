import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import '../player/widgets/app_preview_player.dart';
import 'shorts_state.dart';

/// Owns the Shorts feed: preview-catalog discovery, lazy per-item preview
/// resolution, and current-item detail prefetch. Modeled directly on
/// `FeaturedController` (`apps/app/lib/home/featured_controller.dart`) —
/// same `_request` generation-counter pattern for stale-request protection,
/// same partial-failure tolerance.
class ShortsController extends Cubit<ShortsState> {
  ShortsController({required this.registry}) : super(const ShortsState());

  final ExtensionRegistry registry;

  int _request = 0;

  /// Loads (or reloads) the feed from every preview-surface catalog across
  /// installed extensions, de-duplicated by [MediaRef] with the first
  /// occurrence kept. Declared order is preserved — never re-sorted.
  Future<void> load({bool refresh = false}) async {
    final request = ++_request;
    emit(state.copyWith(status: ShortsStatus.loading, clearError: true));

    final bindings = registry.previewCatalogs();
    final results = await Future.wait([
      for (final binding in bindings) _loadBinding(binding),
    ]);

    if (isClosed || request != _request) return;

    final failures = [for (final result in results) if (result.error != null) result.error!];
    if (bindings.isNotEmpty && failures.length == bindings.length) {
      emit(
        state.copyWith(
          status: state.items.isNotEmpty ? ShortsStatus.usable : ShortsStatus.error,
          error: failures.first,
        ),
      );
      return;
    }

    final seen = <MediaRef>{};
    final items = <VersionedMediaItem>[];
    for (final result in results) {
      for (final entry in result.items) {
        if (seen.add(entry.item.ref)) items.add(entry);
      }
    }

    emit(
      ShortsState(
        status: items.isEmpty ? ShortsStatus.empty : ShortsStatus.usable,
        items: items,
      ),
    );
  }

  Future<_BindingLoadResult> _loadBinding(CatalogBinding binding) async {
    try {
      final page = await registry.loadCatalog(binding);
      return _BindingLoadResult.page([for (final section in page.sections) ...section.items]);
    } catch (error) {
      return _BindingLoadResult.error(error);
    }
  }

  Future<void> retry() => load(refresh: true);

  Future<void> refresh() => load(refresh: true);

  /// Resolves [item]'s preview, picking the first source this app can
  /// actually play. Idempotent — a second call while already
  /// resolving/resolved is a no-op, so the page can call this freely from
  /// both `onPageChanged` (current item) and its own prefetch (next item)
  /// without double-fetching.
  Future<void> ensurePreviewResolved(MediaItemV2 item) async {
    final existing = state.previewFor(item.ref);
    if (existing.status != PreviewStatus.unresolved) return;

    final request = _request;
    _setPreview(item.ref, const PreviewResolution(status: PreviewStatus.resolving));

    final response = await registry.preview(item.ref, item);
    if (isClosed || request != _request) return;

    PreviewSource? supported;
    for (final source in response.sources) {
      if (source is DirectPreviewSource ||
          (source is EmbeddedPreviewSource && isSupportedPreviewProvider(source.provider))) {
        supported = source;
        break;
      }
    }

    _setPreview(
      item.ref,
      supported == null
          ? const PreviewResolution(status: PreviewStatus.unusable)
          : PreviewResolution(status: PreviewStatus.usable, source: supported),
    );
  }

  void _setPreview(MediaRef ref, PreviewResolution resolution) {
    emit(
      state.copyWith(previews: {...state.previews, _refKey(ref): resolution}),
    );
  }

  /// Prefetches [item]'s detail — only meaningful for a [SeriesItemV2],
  /// whose primary action can't be derived without its episode guide.
  /// Failure is silent and non-fatal, matching
  /// `DetailPageV2._loadDetail`'s same fallback: a missing `meta` role
  /// must not block the item's own listing data from being usable.
  Future<void> ensureDetailFetched(MediaItemV2 item) async {
    if (item is! SeriesItemV2) return;
    if (state.detailFor(item.ref) != null) return;

    final request = _request;
    try {
      final detail = await registry.meta(item.ref);
      if (isClosed || request != _request) return;
      emit(state.copyWith(details: {...state.details, _refKey(item.ref): detail}));
    } catch (_) {
      // Leave it unresolved; the primary action stays "Details" until a
      // retry, matching the source plan's "cannot be determined" case.
    }
  }
}

class _BindingLoadResult {
  const _BindingLoadResult.page(this.items) : error = null;
  const _BindingLoadResult.error(this.error) : items = const [];

  final List<VersionedMediaItem> items;
  final Object? error;
}

String _refKey(MediaRef ref) => '${ref.extensionId}/${ref.providerId}/${ref.id}';
