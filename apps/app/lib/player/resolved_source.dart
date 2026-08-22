import 'package:fvcksubs_core/fvcksubs_core.dart';

class ResolvedSource {
  const ResolvedSource({required this.source, required this.stream});

  final StreamSource source;
  final PlayableStream stream;
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
