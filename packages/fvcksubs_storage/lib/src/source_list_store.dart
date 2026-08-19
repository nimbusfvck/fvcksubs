import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One item's discovered stream sources, persisted for a fast reopen.
///
/// Deliberately holds only source *metadata* (id/label/provider) — never a
/// resolved stream (url/headers/DRM). A resolved stream is a signed link
/// that dies in minutes; persisting it wouldn't survive to the next visit.
/// What's actually worth keeping across a restart is the *discovery* result
/// — which providers had this item, under which source ids — since that
/// rarely changes hour to hour, and skipping it means playback can start
/// with one fast `resolve()` instead of the full multi-provider fan-out.
class CachedSourceList extends Equatable {
  /// Creates a cached source list.
  const CachedSourceList({
    required this.ref,
    required this.sources,
    required this.fetchedAt,
  });

  /// Builds a [CachedSourceList] from decoded JSON.
  factory CachedSourceList.fromJson(Map<String, Object?> json) => CachedSourceList(
    ref: MediaRef.fromJson(json['ref']! as Map<String, Object?>),
    sources: [
      for (final entry in json['sources']! as List<Object?>)
        StreamSource.fromJson(entry! as Map<String, Object?>),
    ],
    fetchedAt: DateTime.parse(json['fetchedAt']! as String),
  );

  /// The item these sources were discovered for.
  final MediaRef ref;

  /// What `registry.sources(item)` returned — the discovery result, not a
  /// resolved stream.
  final List<StreamSource> sources;

  /// When this was discovered. Not used to expire the entry — a stale entry
  /// still saves the discovery round-trip, and a `resolve()` that fails
  /// against it falls back to fresh discovery regardless — but kept so a
  /// future eviction policy (oldest-first, say) has something to sort on.
  final DateTime fetchedAt;

  /// Same key convention `UserMediaState.keyFor` uses — extension and
  /// provider included, since [MediaRef.id] alone isn't unique across
  /// extensions.
  static String keyFor(MediaRef ref) => '${ref.extensionId}/${ref.providerId}/${ref.id}';

  /// This record's own key — see [keyFor].
  String get key => keyFor(ref);

  /// Encodes to a JSON map.
  Map<String, Object?> toJson() => {
    'ref': ref.toJson(),
    'sources': [for (final source in sources) source.toJson()],
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  @override
  List<Object?> get props => [ref, sources, fetchedAt];
}

/// Persists discovered source lists across app restarts.
abstract class SourceListStore {
  /// Loads every saved entry, keyed by [CachedSourceList.key].
  Future<Map<String, CachedSourceList>> load();

  /// Saves the full set of entries, replacing whatever was there before.
  Future<void> save(Map<String, CachedSourceList> records);
}

/// [SourceListStore] backed by `shared_preferences` — the whole set as one
/// JSON-encoded string, same approach as `LibraryStore` and at a similar
/// scale (bounded by how many distinct titles get eviction-capped in by
/// whatever holds this, not by the store itself).
class SharedPreferencesSourceListStore implements SourceListStore {
  static const String _key = 'player.sourceLists';

  @override
  Future<Map<String, CachedSourceList>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as List<Object?>;
    final records = <String, CachedSourceList>{};
    for (final entry in decoded) {
      final cached = CachedSourceList.fromJson(entry! as Map<String, Object?>);
      records[cached.key] = cached;
    }
    return records;
  }

  @override
  Future<void> save(Map<String, CachedSourceList> records) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode([for (final cached in records.values) cached.toJson()]);
    await prefs.setString(_key, encoded);
  }
}
