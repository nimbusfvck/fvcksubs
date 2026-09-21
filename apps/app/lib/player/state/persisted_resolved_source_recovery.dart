import 'package:fvcksubs_core/fvcksubs_core.dart';

import 'source_cache.dart';

/// Limits stale persisted VOD streams to one automatic re-resolve per source.
class PersistedResolvedSourceRecovery {
  final Set<String> _attemptedSourceIds = <String>{};

  bool shouldRefreshAfterStartupFailure({
    required bool isPersistedSource,
    required SourceCache cache,
    required MediaRef ref,
    required String sourceId,
  }) {
    if (isPersistedSource && _attemptedSourceIds.add(sourceId)) {
      return true;
    }
    if (_attemptedSourceIds.contains(sourceId)) {
      cache.removeLastResolved(ref, sourceId);
    }
    return false;
  }
}
