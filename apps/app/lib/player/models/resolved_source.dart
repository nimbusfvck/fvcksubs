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

/// Stable identity for a source descriptor across refreshes.
///
/// Some providers embed a short-lived token in [StreamSource.id], so the id
/// can change even when the same named server is returned again. Keep those
/// refreshes from appearing as duplicate picker entries.
String sourceDescriptorKey(StreamSource source) {
  final provider = source.providerId.isNotEmpty
      ? source.providerId
      : source.provider;
  return '$provider\u0000${source.label}';
}

/// Refreshes resolved sources without dropping the source already playing.
///
/// A background refresh can fail to resolve one of the sources that opened the
/// player. Keep that entry until the current session ends, while replacing
/// refreshed entries and appending newly discovered ones.
List<ResolvedSource> mergeResolvedSources(
  List<ResolvedSource> current,
  List<ResolvedSource> refreshed, {
  String? preserveSourceId,
}) {
  final refreshedByKey = {
    for (final source in refreshed) sourceDescriptorKey(source.source): source,
  };
  final seenKeys = <String>{};
  final merged = <ResolvedSource>[
    for (final source in current)
      if (seenKeys.add(sourceDescriptorKey(source.source))) ...[
        if (refreshedByKey.containsKey(sourceDescriptorKey(source.source)))
          refreshedByKey.remove(sourceDescriptorKey(source.source))!
        else
          source,
      ],
    ...refreshedByKey.values,
  ];
  if (preserveSourceId == null) return merged;

  final preservedIndex = current.indexWhere(
    (source) => source.source.id == preserveSourceId,
  );
  if (preservedIndex < 0) return merged;
  final preservedKey = sourceDescriptorKey(current[preservedIndex].source);
  final refreshedIndex = merged.indexWhere(
    (source) => sourceDescriptorKey(source.source) == preservedKey,
  );
  if (refreshedIndex >= 0) merged[refreshedIndex] = current[preservedIndex];
  return merged;
}
