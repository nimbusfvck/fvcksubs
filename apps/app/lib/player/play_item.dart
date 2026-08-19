import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../platform/playback_capability.dart';
import '../theme/tokens.dart';
import 'player_page.dart';
import 'playback_media.dart';
import 'source_priority_controller.dart';
import 'subtitle_preference_controller.dart';

Future<void> playItem(
  BuildContext context,
  MediaItem item, {
  List<SeriesSeason> seasons = const [],
  bool replaceCurrent = false,
}) => _playMedia(
  context,
  PlaybackMedia.legacy(item),
  seasons: seasons,
  replaceCurrent: replaceCurrent,
);

Future<void> playItemV2(
  BuildContext context,
  MediaItemV2 item, {
  bool replaceCurrent = false,
}) =>
    _playMedia(context, PlaybackMedia.v2(item), replaceCurrent: replaceCurrent);

Future<void> _playMedia(
  BuildContext context,
  PlaybackMedia item, {
  List<SeriesSeason> seasons = const [],
  bool replaceCurrent = false,
}) async {
  final scope = AppScope.of(context);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final cached = scope.sourceCache.peek(item.ref);
  if (cached != null) {
    _openPlayer(navigator, scope, item, cached, seasons, replaceCurrent);
    if (scope.sourceCache.isStale(item.ref)) {
      unawaited(_revalidate(scope, item));
    }
    return;
  }

  final cachedList = scope.sourceCache.peekSourceList(item.ref);
  if (cachedList != null && cachedList.isNotEmpty) {
    final fast = await _resolveWithOverlay(
      context,
      navigator,
      (progress) =>
          _resolveKnownSources(scope, item, [cachedList.first], progress),
    );
    if (fast == null) return; // abandoned mid-resolve
    if (fast.isNotEmpty) {
      scope.sourceCache.store(item.ref, fast);
      final pendingSources = _revalidate(scope, item);
      _openPlayer(
        navigator,
        scope,
        item,
        fast,
        seasons,
        replaceCurrent,
        pendingSources: pendingSources,
      );
      return;
    }
  }

  final sources = await _resolveWithOverlay(
    context,
    navigator,
    (progress) => _playableSources(scope, item, progress),
  );
  if (sources == null) return;

  if (sources.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No playable sources found.')),
    );
    return;
  }

  scope.sourceCache.store(item.ref, sources);
  _openPlayer(navigator, scope, item, sources, seasons, replaceCurrent);
}

Future<List<ResolvedSource>?> _resolveWithOverlay(
  BuildContext context,
  NavigatorState navigator,
  Future<List<ResolvedSource>> Function(_ResolveProgress progress) resolve,
) async {
  final progress = _ResolveProgress();
  final overlay = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (_) => _PlayLoadingOverlay(progress: progress),
  );

  var abandoned = false;
  unawaited(overlay.popped.whenComplete(() => abandoned = true));
  unawaited(navigator.push(overlay));

  final result = await resolve(progress);
  progress.dispose();

  if (abandoned) return null;
  navigator.removeRoute(overlay);
  return result;
}

Future<List<ResolvedSource>?> _revalidate(
  AppScope scope,
  PlaybackMedia item,
) async {
  final progress = _ResolveProgress();
  final sources = await _playableSources(scope, item, progress);
  progress.dispose();
  if (sources.isEmpty) return null;
  scope.sourceCache.store(item.ref, sources);
  return sources;
}

void _openPlayer(
  NavigatorState navigator,
  AppScope scope,
  PlaybackMedia item,
  List<ResolvedSource> sources,
  List<SeriesSeason> seasons,
  bool replaceCurrent, {
  Future<List<ResolvedSource>?>? pendingSources,
}) {
  final resolved = _preferredFirst(
    sources,
    scope.sourcePriorityController,
    scope.subtitlePreferenceController,
  );
  final legacyItem = item.legacyItem;
  if (legacyItem == null) {
    scope.libraryController.recordWatched(item.v2Item!);
  } else {
    scope.legacyLibraryController.recordWatched(legacyItem);
  }
  final route = MaterialPageRoute<void>(
    builder: (_) => legacyItem == null
        ? PlayerPage.v2(
            item: item.v2Item!,
            resolvedSources: resolved,
            pendingSources: pendingSources,
          )
        : PlayerPage(
            item: legacyItem,
            resolvedSources: resolved,
            seasons: seasons,
            pendingSources: pendingSources,
          ),
  );
  unawaited(
    replaceCurrent ? navigator.pushReplacement(route) : navigator.push(route),
  );
}

List<ResolvedSource> _preferredFirst(
  List<ResolvedSource> sources,
  SourcePriorityController sourcePriority,
  SubtitlePreferenceController subtitlePreference,
) {
  final indexed = sources.indexed.toList();
  indexed.sort((a, b) {
    final providerResult = sourcePriority
        .rankOf(a.$2.source.providerId)
        .compareTo(sourcePriority.rankOf(b.$2.source.providerId));
    if (providerResult != 0) return providerResult;
    final aHasSubtitle = subtitlePreference.isSatisfiedBy(
      a.$2.stream.subtitles,
    );
    final bHasSubtitle = subtitlePreference.isSatisfiedBy(
      b.$2.stream.subtitles,
    );
    final subtitleResult = (bHasSubtitle ? 1 : 0).compareTo(
      aHasSubtitle ? 1 : 0,
    );
    return subtitleResult == 0 ? a.$1.compareTo(b.$1) : subtitleResult;
  });
  return [for (final entry in indexed) entry.$2];
}

Future<List<ResolvedSource>> _playableSources(
  AppScope scope,
  PlaybackMedia item,
  _ResolveProgress progress,
) async {
  List<StreamSource> sources;
  try {
    final legacyItem = item.legacyItem;
    sources = legacyItem == null
        ? await scope.registry.sourcesV2(item.v2Item!)
        : await scope.registry.sources(legacyItem);
  } catch (_) {
    return const [];
  }
  if (sources.isEmpty) return const [];

  scope.sourceCache.recordSourceList(item.ref, sources);
  return _resolveKnownSources(scope, item, sources, progress);
}

Future<List<ResolvedSource>> _resolveKnownSources(
  AppScope scope,
  PlaybackMedia item,
  List<StreamSource> sources,
  _ResolveProgress progress,
) async {
  sources = scope.sourcePriorityController.order(sources);
  progress.begin([for (final source in sources) source.label]);

  final target = PlaybackTarget.detect();
  final resolved = await Future.wait(
    sources.map((source) async {
      try {
        final stream = await scope.registry.resolveSource(item.ref, source.id);
        if (!target.canPlay(stream)) return null;
        return ResolvedSource(source: source, stream: stream);
      } catch (_) {
        return null;
      } finally {
        progress.markSettled(source.label);
      }
    }),
  );
  return resolved.whereType<ResolvedSource>().toList();
}

class _ResolveProgress extends ChangeNotifier {
  final List<String> _outstanding = [];
  int _total = 0;
  int _settled = 0;

  List<String> get outstanding => List.unmodifiable(_outstanding);

  int get settledCount => _settled;
  int get total => _total;

  void begin(List<String> names) {
    _outstanding
      ..clear()
      ..addAll(names);
    _total = names.length;
    _settled = 0;
    notifyListeners();
  }

  void markSettled(String name) {
    _outstanding.remove(name);
    _settled++;
    notifyListeners();
  }
}

class _PlayLoadingOverlay extends StatefulWidget {
  const _PlayLoadingOverlay({required this.progress});

  final _ResolveProgress progress;

  @override
  State<_PlayLoadingOverlay> createState() => _PlayLoadingOverlayState();
}

class _PlayLoadingOverlayState extends State<_PlayLoadingOverlay> {
  Timer? _ticker;
  int _cursor = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (mounted) setState(() => _cursor++);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ListenableBuilder(
          listenable: widget.progress,
          builder: (context, _) {
            final outstanding = widget.progress.outstanding;
            final total = widget.progress.total;
            final line = outstanding.isEmpty
                ? 'Finding sources…'
                : 'Checking ${outstanding[_cursor % outstanding.length]}…';

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                      Icon(
                        Icons.travel_explore,
                        color: AppColors.onDark,
                        size: 22,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  line,
                  textAlign: TextAlign.center,
                  style: AppTypography.titleSm.copyWith(
                    color: AppColors.onDark,
                    letterSpacing: 0.5,
                  ),
                ),
                if (total > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${widget.progress.settledCount} of $total ready',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onDarkSoft,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}
