import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../theme/tokens.dart';
import 'models/app_player_controller.dart';
import 'models/playback_media.dart';
import 'models/resolved_source.dart';
import 'multi_view_event_picker_page.dart';
import 'sheets/player_selection_sheets.dart';
import 'widgets/stream_player.dart';
import 'workflow/play_item.dart';

part 'multi_view_tile.dart';
part 'multi_view_layout.dart';

const int _maxMobileMultiViewSlots = 2;
const int _maxLargeMultiViewSlots = 8;
const double _largeMultiViewBreakpoint = 900;

int _maxMultiViewSlotsForWidth(double width) =>
    width >= _largeMultiViewBreakpoint
    ? _maxLargeMultiViewSlots
    : _maxMobileMultiViewSlots;
final ValueNotifier<AppPlayerValue> _emptyPlayerValue = ValueNotifier(
  const AppPlayerValue(),
);

class MultiViewPage extends StatefulWidget {
  const MultiViewPage({
    super.key,
    required this.initialEvent,
    required this.initialSource,
    this.onOpenSinglePlayer,
    this.onExitToMiniPlayer,
  });

  final EventItemV2 initialEvent;
  final ResolvedSource initialSource;
  final void Function(EventItemV2 event, ResolvedSource source)?
  onOpenSinglePlayer;
  final void Function(EventItemV2 event, ResolvedSource source)?
  onExitToMiniPlayer;

  @override
  State<MultiViewPage> createState() => _MultiViewPageState();
}

class _MultiViewEntry {
  const _MultiViewEntry({
    required this.event,
    required this.sources,
    required this.sourceIndex,
  });

  final EventItemV2 event;
  final List<ResolvedSource> sources;
  final int sourceIndex;

  ResolvedSource get source => sources[sourceIndex];

  String get key =>
      '${event.ref.extensionId}/${event.ref.providerId}/${event.ref.id}';

  _MultiViewEntry copyWith({
    List<ResolvedSource>? sources,
    ResolvedSource? source,
  }) {
    final nextSources = sources ?? this.sources;
    final nextIndex = source == null
        ? sourceIndex.clamp(0, nextSources.length - 1)
        : nextSources.indexWhere((item) => item.source.id == source.source.id);
    return _MultiViewEntry(
      event: event,
      sources: nextSources,
      sourceIndex: nextIndex < 0 ? 0 : nextIndex,
    );
  }
}

class _MultiViewPageState extends State<MultiViewPage> {
  late final List<_MultiViewEntry> _entries = [
    _MultiViewEntry(
      event: widget.initialEvent,
      sources: [widget.initialSource],
      sourceIndex: 0,
    ),
  ];
  final Map<String, AppPlayerController> _controllers = {};
  final Map<String, StreamSubscription<AppPlayerEvent>> _eventSubscriptions =
      {};
  final Map<String, String> _errors = {};
  final Set<String> _retrying = {};
  final Map<String, Set<String>> _failedPlaybackUrls = {};
  final Set<String> _loadingSources = {};
  int _audioIndex = 0;
  String? _pinnedKey;
  bool _backInFlight = false;
  bool _adding = false;

  Future<void> _addEvent() async {
    final maxSlots = _maxMultiViewSlotsForWidth(
      MediaQuery.sizeOf(context).width,
    );
    if (_adding || _entries.length >= maxSlots) return;
    final event = await Navigator.of(context).push<EventItemV2>(
      MaterialPageRoute<EventItemV2>(
        builder: (_) => MultiViewEventPickerPage(
          excludedRefs: {for (final entry in _entries) entry.event.ref},
        ),
      ),
    );
    if (!mounted || event == null) return;

    setState(() => _adding = true);
    final source = await resolveLiveEventForMultiView(context, event);
    if (!mounted) return;
    if (source == null) {
      setState(() => _adding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No playable source found for this event.'),
        ),
      );
      return;
    }
    setState(() {
      _entries.add(
        _MultiViewEntry(event: event, sources: [source], sourceIndex: 0),
      );
      _adding = false;
    });
  }

  void _removeAt(int index) {
    final removed = _entries[index];
    _controllers.remove(removed.key);
    unawaited(_eventSubscriptions.remove(removed.key)?.cancel());
    _errors.remove(removed.key);
    _retrying.remove(removed.key);
    _failedPlaybackUrls.remove(removed.key);
    if (_entries.length == 1) {
      final onExitToMiniPlayer = widget.onExitToMiniPlayer;
      if (onExitToMiniPlayer != null) {
        onExitToMiniPlayer(removed.event, removed.source);
        return;
      }
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      if (_pinnedKey == removed.key) _pinnedKey = null;
      _entries.removeAt(index);
      if (_audioIndex == index) {
        _audioIndex = 0;
      } else if (_audioIndex > index) {
        _audioIndex--;
      }
    });
  }

  void _togglePlayback(String key) {
    final controller = _controllers[key];
    if (controller == null) return;
    final action = controller.value.value.isPlaying
        ? controller.pause
        : controller.play;
    unawaited(action());
  }

  void _selectAudio(int index) {
    if (_audioIndex == index) return;
    setState(() => _audioIndex = index);
  }

  void _togglePinned(String key) {
    setState(() => _pinnedKey = _pinnedKey == key ? null : key);
  }

  void _handleBack() {
    if (_backInFlight || _entries.isEmpty) return;
    _backInFlight = true;
    _MultiViewEntry selected = _entries.first;
    for (final entry in _entries) {
      if (entry.key == _pinnedKey) {
        selected = entry;
        break;
      }
    }
    if (_pinnedKey == null) {
      final audioIndex = _audioIndex < _entries.length ? _audioIndex : 0;
      selected = _entries[audioIndex];
    }
    final onExitToMiniPlayer = widget.onExitToMiniPlayer;
    if (onExitToMiniPlayer != null) {
      onExitToMiniPlayer(selected.event, selected.source);
      return;
    }
    _backInFlight = false;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _retryAt(int index) async {
    final entry = _entries[index];
    if (!_retrying.add(entry.key)) return;
    _failedPlaybackUrls.remove(entry.key);
    setState(() => _errors.remove(entry.key));
    final source = await resolveLiveEventForMultiView(context, entry.event);
    if (!mounted) return;
    _retrying.remove(entry.key);
    if (source == null) {
      setState(() => _errors[entry.key] = 'Source unavailable.');
      return;
    }
    unawaited(_eventSubscriptions.remove(entry.key)?.cancel());
    _controllers.remove(entry.key);
    setState(() {
      _entries[index] = entry.copyWith(source: source);
    });
  }

  Future<void> _recoverAfterPlaybackError(String key) async {
    if (!_retrying.add(key)) return;
    final index = _entries.indexWhere((entry) => entry.key == key);
    if (index < 0) {
      _retrying.remove(key);
      return;
    }
    final entry = _entries[index];
    final failedUrls = _failedPlaybackUrls.putIfAbsent(key, () => {});
    failedUrls.add(entry.source.stream.url);
    setState(() {});

    final scope = AppScope.of(context);
    List<ResolvedSource> refreshed;
    try {
      refreshed = await refetchPlayableSources(
        scope,
        PlaybackMedia(entry.event),
      );
    } catch (_) {
      refreshed = const [];
    }
    if (!mounted) return;

    final currentIndex = _entries.indexWhere((item) => item.key == key);
    if (currentIndex < 0) {
      _retrying.remove(key);
      return;
    }
    final currentEntry = _entries[currentIndex];
    final merged = mergeResolvedSources(currentEntry.sources, refreshed);
    ResolvedSource? next;
    for (final candidate in merged) {
      if (!failedUrls.contains(candidate.stream.url)) {
        next = candidate;
        break;
      }
    }

    // A fresh resolution can produce a new signed URL even when the refresh
    // did not return a usable alternative. Try it once before surfacing the
    // failure to the viewer.
    if (next == null) {
      final fresh = await resolveLiveEventForMultiView(
        context,
        currentEntry.event,
      );
      if (mounted && fresh != null && !failedUrls.contains(fresh.stream.url)) {
        next = fresh;
      }
    }
    if (!mounted) return;

    _retrying.remove(key);
    if (next == null) {
      setState(() => _errors[key] = 'Playback failed.');
      return;
    }
    unawaited(_eventSubscriptions.remove(key)?.cancel());
    _controllers.remove(key);
    setState(() {
      _entries[currentIndex] = currentEntry.copyWith(
        sources: mergeResolvedSources(merged, [next!]),
        source: next,
      );
      _errors.remove(key);
    });
  }

  Future<void> _changeSourceAt(int index) async {
    final entry = _entries[index];
    if (!_loadingSources.add(entry.key)) return;
    setState(() {});
    final scope = AppScope.of(context);
    List<ResolvedSource> refreshed;
    try {
      refreshed = await refetchPlayableSources(
        scope,
        PlaybackMedia(entry.event),
      );
    } catch (_) {
      refreshed = const [];
    }
    if (!mounted) return;
    _loadingSources.remove(entry.key);
    if (index >= _entries.length || _entries[index].key != entry.key) {
      setState(() {});
      return;
    }
    final sources = mergeResolvedSources(entry.sources, refreshed);
    if (sources.isEmpty) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No source available for this event.')),
      );
      return;
    }
    final providerNames = {
      for (final manifest in scope.registry.installed)
        for (final provider in manifest.providers)
          if (provider.name != null) provider.id: provider.name!,
    };
    setState(() {
      _entries[index] = entry.copyWith(sources: sources);
    });
    final selected = await showModalBottomSheet<ResolvedSource>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      isScrollControlled: true,
      builder: (_) => PlayerSourcePickerSheet(
        resolvedSources: sources,
        current: entry.source,
        title: 'Source · ${multiViewEventTitle(entry.event)}',
        providerNames: providerNames,
      ),
    );
    if (!mounted || selected == null) return;
    if (index >= _entries.length || _entries[index].key != entry.key) return;
    final currentEntry = _entries[index];
    if (selected.stream.url == currentEntry.source.stream.url) return;
    unawaited(_eventSubscriptions.remove(currentEntry.key)?.cancel());
    _controllers.remove(currentEntry.key);
    setState(() {
      _entries[index] = currentEntry.copyWith(source: selected);
      _errors.remove(currentEntry.key);
    });
  }

  void _onControllerCreated(String key, Object? value) {
    if (!mounted || value is! AppPlayerController) return;
    final controller = value;
    if (identical(_controllers[key], controller)) return;
    unawaited(_eventSubscriptions.remove(key)?.cancel());
    _controllers[key] = controller;
    _eventSubscriptions[key] = controller.events.listen((event) {
      if (!mounted || event.type != AppPlayerEventType.error) return;
      unawaited(_recoverAfterPlaybackError(key));
    });
    setState(() {});
  }

  Widget _buildEntryTile(int index, AppScope scope) {
    final entry = _entries[index];
    return _MultiViewTile(
      key: ValueKey('${entry.key}/${entry.source.stream.url}'),
      entry: entry,
      muted: index != _audioIndex,
      controller: _controllers[entry.key],
      playerBuilder: scope.playerBuilder,
      error: _errors[entry.key],
      retrying: _retrying.contains(entry.key),
      onControllerCreated: (controller) =>
          _onControllerCreated(entry.key, controller),
      onTogglePlayback: () => _togglePlayback(entry.key),
      onSelectAudio: () => _selectAudio(index),
      onRemove: () => _removeAt(index),
      onRetry: () => _retryAt(index),
      onChangeSource: () => _changeSourceAt(index),
      sourceLoading: _loadingSources.contains(entry.key),
      onTogglePinned: () => _togglePinned(entry.key),
      pinned: _pinnedKey == entry.key,
      onOpenSinglePlayer: widget.onOpenSinglePlayer == null
          ? null
          : () => widget.onOpenSinglePlayer!(entry.event, entry.source),
      audioActive: _audioIndex == index,
    );
  }

  @override
  void dispose() {
    for (final subscription in _eventSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceDark,
        appBar: AppBar(title: const Text('Multi-view')),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxSlots = _maxMultiViewSlotsForWidth(constraints.maxWidth);
              return _buildResponsiveLayout(this, scope, constraints, maxSlots);
            },
          ),
        ),
      ),
    );
  }
}
