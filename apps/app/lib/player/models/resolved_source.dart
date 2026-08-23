import 'package:fvcksubs_core/fvcksubs_core.dart';

class ResolvedSource {
  const ResolvedSource({required this.source, required this.stream});

  final StreamSource source;
  final PlayableStream stream;

  /// Whether the resolved URL can be handed to a network media player.
  ///
  /// Providers should return absolute HTTP(S) URLs. Keep stale or malformed
  /// cached results out of the player so they are resolved again instead of
  /// being interpreted as local file paths by the platform player.
  bool get hasAbsoluteHttpUrl {
    final uri = Uri.tryParse(stream.url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}

/// Refreshes resolved sources without dropping the source already playing.
///
/// A background refresh can fail to resolve one of the sources that opened the
/// player. Keep that entry until the current session ends, while replacing
/// refreshed entries and appending newly discovered ones.
List<ResolvedSource> mergeResolvedSources(
  List<ResolvedSource> current,
  List<ResolvedSource> refreshed,
) {
  final refreshedById = {
    for (final source in refreshed) source.source.id: source,
  };
  final merged = <ResolvedSource>[
    for (final source in current)
      refreshedById.remove(source.source.id) ?? source,
    ...refreshedById.values,
  ];
  return merged;
}
