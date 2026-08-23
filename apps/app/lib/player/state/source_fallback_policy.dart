import '../models/resolved_source.dart';

/// Returns the next source that has not failed during this playback attempt.
///
/// The source order is owned by the extension and must stay stable; fallback
/// only walks forward and never retries a source silently.
int? nextUnfailedSourceIndex({
  required List<ResolvedSource> sources,
  required int currentIndex,
  required Set<String> failedSourceIds,
}) {
  for (var index = currentIndex + 1; index < sources.length; index++) {
    if (!failedSourceIds.contains(sources[index].source.id)) return index;
  }
  return null;
}
