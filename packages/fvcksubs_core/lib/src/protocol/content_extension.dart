import '../content/media_item.dart';
import '../content/media_ref.dart';
import '../content/stream.dart';
import 'catalog.dart';
import 'manifest.dart';

/// The contract every extension fulfills, whatever runtime backs it.
///
/// JavaScript bundles implement this contract through the extension host. The
/// registry calls only methods for roles declared by the [manifest] (see
/// [ProviderRole]). Default implementations reject undeclared roles.
///
/// Everything crossing this boundary is a JSON-serializable protocol type — no
/// extension-private object reaches the app.
abstract class ContentExtension {
  /// This extension's manifest — identity, providers, permissions.
  Manifest get manifest;

  /// Lists items for a catalog. Fills [ProviderRole.catalog].
  Future<CatalogPage> catalog(CatalogQuery query) =>
      throw UnsupportedError('${manifest.id} does not provide a catalog');

  /// Returns one item's detail. Fills [ProviderRole.meta].
  Future<MediaDetail> meta(MediaRef ref) =>
      throw UnsupportedError('${manifest.id} does not provide meta');

  /// Lists playable sources for an item. Half of [ProviderRole.stream].
  ///
  /// Takes the full [item], not just its [MediaRef]: a stream extension that
  /// aggregates broadcast candidates from other providers (matching them by
  /// name/kickoff — see `EventMatchResolver`) needs the item's title and
  /// participants to do that matching, and the caller already holds the item
  /// it's asking about. Re-deriving that from an id alone would cost a second
  /// fetch for no reason.
  ///
  /// [enabledProviders] is the set of this extension's own declared provider
  /// ids (`"fvck.kora"`) currently switched on in Addons — `null` means no
  /// toggle exists yet, so every provider is in play. An extension whose
  /// stream role is a fan-out across several internal sources (see PLAN.md
  /// §7, "Stream sources are separate, toggleable providers") filters its own
  /// fan-out by this; an extension with a single, non-toggleable stream
  /// provider can ignore it.
  Future<List<StreamSource>> sources(
    MediaItem item, {
    Set<String>? enabledProviders,
  }) => throw UnsupportedError('${manifest.id} does not provide sources');

  /// Resolves a source id into a ready stream. Half of [ProviderRole.stream].
  Future<PlayableStream> resolve(String sourceId) =>
      throw UnsupportedError('${manifest.id} does not resolve streams');

  /// Free-text search. Fills [ProviderRole.search].
  Future<CatalogPage> search(String query, {String? page}) =>
      throw UnsupportedError('${manifest.id} does not provide search');

  /// Looks up subtitles for [item] independently of any resolved source.
  /// Fills [ProviderRole.subtitles].
  ///
  /// Takes the full [item], not just its [MediaRef] — a lookup keyed by an
  /// external id (TMDB, say) needs whatever [MediaItem.extra] carries for a
  /// series episode, and re-deriving that from a ref id alone isn't
  /// guaranteed to be possible.
  Future<List<SubtitleTrack>> externalSubtitles(MediaItem item) =>
      throw UnsupportedError('${manifest.id} does not provide subtitles');
}
