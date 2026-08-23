import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../detail/episode_target_v2.dart';
import '../library/library_controller.dart';
import '../platform/playback_capability.dart';
import '../theme/tokens.dart';
import 'controls/player_playback_controls.dart';
import 'models/playback_media.dart';
import 'models/app_player_controller.dart';
import 'models/resolved_source.dart';
import 'sheets/player_selection_sheets.dart';
import 'state/source_fallback_policy.dart';
import 'widgets/player_overlays.dart';
import 'workflow/play_item.dart';

export 'models/resolved_source.dart' show ResolvedSource, mergeResolvedSources;

const Duration _minResumeProgress = Duration(seconds: 5);
const Duration _resumeEndGuard = Duration(seconds: 30);
const Duration _progressInterval = Duration(seconds: 10);

Duration? sourceSwitchSeekPosition({
  required bool isLive,
  required Duration? previousPosition,
  required Duration? duration,
}) {
  if (isLive ||
      previousPosition == null ||
      duration == null ||
      duration <= Duration.zero) {
    return null;
  }
  return previousPosition > duration ? duration : previousPosition;
}

class PlayerPage extends StatefulWidget {
  PlayerPage({
    super.key,
    required MediaItemV2 item,
    required this.resolvedSources,
    this.episodeGuide,
    this.pendingSources,
    this.returnToDetail = false,
  }) : media = PlaybackMedia(item),
       assert(resolvedSources.isNotEmpty, 'Must provide at least one source');

  final PlaybackMedia media;
  final List<ResolvedSource> resolvedSources;
  final EpisodeGuide? episodeGuide;
  final Stream<ResolvedSource>? pendingSources;
  final bool returnToDetail;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late int _currentIndex;
  late List<ResolvedSource> _resolvedSources;
  late final NextEpisodeV2? _nextEpisode;
  bool _showUpNext = false;
  bool _upNextPaused = false;
  bool _advancing = false;
  LibraryController? _library;
  Timer? _progressTimer;
  ValueListenable<AppPlayerValue>? _videoValue;
  bool _hasResumed = false;
  Duration? _lastPosition;
  Duration? _lastDuration;
  Duration? _pendingSwitchPosition;
  String? _playbackError;
  bool _retrying = false;
  int _sourceRevision = 0;
  int _playbackAttempt = 0;
  final Set<String> _failedSourceIds = <String>{};
  bool _sourceStarted = false;
  AppPlayerController? _controller;
  StreamSubscription<AppPlayerEvent>? _eventSubscription;
  void Function(bool visibility)? _onVisibilityChanged;

  bool get _isLive => widget.media.isLive;
  ResolvedSource get _current => _resolvedSources[_currentIndex];

  @override
  void initState() {
    super.initState();
    _currentIndex = 0;
    _resolvedSources = widget.resolvedSources;
    final item = widget.media.item;
    _nextEpisode = item is EpisodeItemV2 && widget.episodeGuide != null
        ? nextEpisodeOfV2(item, widget.episodeGuide!)
        : null;
    final pending = widget.pendingSources;
    if (pending != null) unawaited(_addPendingSources(pending));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _library = AppScope.of(context).libraryController;
    _progressTimer ??= Timer.periodic(
      _progressInterval,
      (_) => _reportProgress(),
    );
  }

  Future<void> _addPendingSources(Stream<ResolvedSource> pending) async {
    await for (final source in pending) {
      if (!mounted) return;
      final playingId = _current.source.id;
      final merged = mergeResolvedSources(_resolvedSources, [source]);
      final cache = AppScope.of(context).sourceCache;
      cache.store(widget.media.ref, merged);
      cache.promote(widget.media.ref, playingId);
      setState(() {
        _resolvedSources = merged;
        _currentIndex = merged.indexWhere(
          (source) => source.source.id == playingId,
        );
        if (_currentIndex < 0) _currentIndex = 0;
      });
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _videoValue?.removeListener(_onVideoValueChanged);
    unawaited(_eventSubscription?.cancel());
    _reportProgress();
    super.dispose();
  }

  void _trackPosition(AppPlayerController controller) {
    final next = controller.value;
    if (identical(next, _videoValue)) return;
    _videoValue?.removeListener(_onVideoValueChanged);
    _videoValue = next..addListener(_onVideoValueChanged);
    _onVideoValueChanged();
  }

  void _onVideoValueChanged() {
    final value = _videoValue?.value;
    if (value == null || !value.initialized) return;
    _sourceStarted = true;
    _lastPosition = value.position;
    _lastDuration = value.duration;
    final position = sourceSwitchSeekPosition(
      isLive: _isLive,
      previousPosition: _pendingSwitchPosition,
      duration: value.duration,
    );
    if (position != null) {
      _pendingSwitchPosition = null;
      _lastPosition = position;
      final controller = _controller;
      if (controller != null) {
        unawaited(controller.seekTo(position));
      }
    }
    if (!_hasResumed) {
      _hasResumed = true;
      _resumeSavedPosition(value.duration);
    }
  }

  void _attachEventListener(AppPlayerController controller) {
    if (identical(controller, _controller) && _eventSubscription != null) {
      return;
    }
    unawaited(_eventSubscription?.cancel());
    final attempt = _playbackAttempt;
    _eventSubscription = controller.events.listen(
      (event) => _handlePlayerEvent(controller, attempt, event),
    );
    _playbackError = null;
  }

  void _handlePlayerEvent(
    AppPlayerController controller,
    int attempt,
    AppPlayerEvent event,
  ) {
    if (attempt != _playbackAttempt) return;
    if (event.type == AppPlayerEventType.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            attempt == _playbackAttempt &&
            identical(controller, _controller)) {
          _showNextEpisode();
        }
      });
      return;
    }
    if (event.type != AppPlayerEventType.error) return;
    final message = event.error?.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          attempt != _playbackAttempt ||
          !identical(controller, _controller)) {
        return;
      }
      _failedSourceIds.add(_current.source.id);
      if (!_sourceStarted) {
        final nextIndex = nextUnfailedSourceIndex(
          sources: _resolvedSources,
          currentIndex: _currentIndex,
          failedSourceIds: _failedSourceIds,
        );
        if (nextIndex != null) {
          _switchToResolvedSource(nextIndex);
          return;
        }
      }
      setState(() {
        _playbackError = (message == null || message.isEmpty)
            ? 'Playback failed.'
            : message;
        _retrying = false;
      });
    });
  }

  Future<void> _retryPlayback() async {
    if (_controller == null || _retrying) return;
    final attempt = ++_playbackAttempt;
    _failedSourceIds.remove(_current.source.id);
    _sourceStarted = false;
    setState(() {
      _retrying = true;
      _playbackError = null;
    });
    try {
      final scope = AppScope.of(context);
      final stream = await scope.registry.resolveSource(
        widget.media.ref,
        _current.source.id,
      );
      if (!PlaybackTarget.detect().canPlay(stream)) {
        throw StateError(
          'The refreshed source is not playable on this device.',
        );
      }
      if (!mounted || attempt != _playbackAttempt) return;
      setState(() {
        _resolvedSources[_currentIndex] = ResolvedSource(
          source: _current.source,
          stream: stream,
        );
        _sourceRevision++;
        _controller = null;
        _retrying = false;
      });
      scope.sourceCache.store(widget.media.ref, _resolvedSources);
    } catch (_) {
      if (!mounted || attempt != _playbackAttempt) return;
      setState(() {
        _retrying = false;
        _playbackError =
            'Source is unavailable. Try another source or retry later.';
      });
    }
  }

  void _resumeSavedPosition(Duration? duration) {
    if (_isLive || _controller == null) return;
    final progress = _library?.recordFor(widget.media.ref)?.progress;
    if (progress == null || progress < _minResumeProgress) return;
    if (duration != null && duration - progress < _resumeEndGuard) return;
    unawaited(_controller!.seekTo(progress));
  }

  void _reportProgress() {
    if (_isLive || _lastPosition == null) return;
    _library?.recordWatched(
      widget.media.item,
      progress: _lastPosition,
      duration: _lastDuration,
    );
  }

  void _showNextEpisode() {
    if (_nextEpisode == null || _showUpNext) return;
    setState(() {
      _showUpNext = true;
      _upNextPaused = false;
    });
  }

  void _playNextEpisode() {
    final next = _nextEpisode;
    if (_advancing || next == null) return;
    _advancing = true;
    unawaited(
      playItemV2(
        context,
        next.item,
        episodeGuide: widget.episodeGuide,
        replaceCurrent: true,
      ),
    );
  }

  void _dismiss(AppPlayerController? controller) {
    if (controller?.isFullScreen == true) {
      unawaited(controller!.exitFullScreen());
    }
    Navigator.of(context).pop();
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
  }

  void _seekBy(Duration offset) {
    final controller = _controller;
    if (controller == null || _isLive) return;
    final target = controller.value.value.position + offset;
    unawaited(
      controller.seekTo(target < Duration.zero ? Duration.zero : target),
    );
  }

  void _toggleFullScreen() {
    final controller = _controller;
    if (controller != null) unawaited(controller.toggleFullScreen());
  }

  void _switchToResolvedSource(int index) {
    if (index < 0 ||
        index >= _resolvedSources.length ||
        index == _currentIndex) {
      return;
    }
    final picked = _resolvedSources[index];
    _failedSourceIds.remove(picked.source.id);
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    setState(() {
      _pendingSwitchPosition = _isLive ? null : _lastPosition;
      _currentIndex = index;
      _playbackAttempt++;
      _playbackError = null;
      _retrying = false;
      _sourceRevision++;
      _sourceStarted = false;
      _controller = null;
      _onVisibilityChanged = null;
    });
    AppScope.of(
      context,
    ).sourceCache.promote(widget.media.ref, picked.source.id);
  }

  Future<void> _changeSource() async {
    final picked = await showModalBottomSheet<ResolvedSource>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final registry = AppScope.of(context).registry;
        final providerNames = {
          for (final manifest in registry.installed)
            for (final provider in manifest.providers)
              if (provider.name != null) provider.id: provider.name!,
        };
        return PlayerSourcePickerSheet(
          resolvedSources: _resolvedSources,
          current: _current,
          providerNames: providerNames,
        );
      },
    );
    if (!mounted || picked == null) return;
    final index = _resolvedSources.indexOf(picked);
    if (index < 0 || index == _currentIndex) return;
    _switchToResolvedSource(index);
  }

  Widget _controlsFor(AppPlayerController? controller) =>
      PlayerPlaybackControls(
        controller: controller,
        onVisibilityChanged: _onVisibilityChanged ?? (_) {},
        media: widget.media,
        resolvedSources: _resolvedSources,
        currentIndex: _currentIndex,
        onChangeSource: _changeSource,
        onBack: () => _dismiss(controller),
        onToggleFullScreen: _toggleFullScreen,
        isLive: _isLive,
        upNextV2: _showUpNext ? _nextEpisode : null,
        upNextPaused: _upNextPaused,
        onNearEnd: _showNextEpisode,
        onPlayNext: _playNextEpisode,
        onPauseUpNext: () => setState(() => _upNextPaused = true),
        onCancelUpNext: () => setState(() {
          _showUpNext = false;
          _upNextPaused = false;
        }),
      );

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.space): _togglePlayback,
      const SingleActivator(LogicalKeyboardKey.keyJ): () =>
          _seekBy(const Duration(seconds: -10)),
      const SingleActivator(LogicalKeyboardKey.keyL): () =>
          _seekBy(const Duration(seconds: 10)),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          _seekBy(const Duration(seconds: -5)),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          _seekBy(const Duration(seconds: 5)),
      const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullScreen,
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          unawaited(_controller?.exitFullScreen()),
    },
    child: Focus(
      autofocus: true,
      child: PlayerDragToClose(
        onDismiss: () => _dismiss(_controller),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: AppScope.of(context).playerBuilder(
                    context,
                    _current.stream,
                    isLive: _isLive,
                    key: ValueKey('${_current.source.id}:$_sourceRevision'),
                    preferredSubtitleLanguage: AppScope.of(
                      context,
                    ).subtitlePreferenceController.languageCode,
                    onControllerCreated: (value) {
                      _controller = value as AppPlayerController?;
                      if (_controller != null) {
                        _attachEventListener(_controller!);
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() {});
                      });
                    },
                    onPlaybackReady: (value) {
                      final controller = value as AppPlayerController?;
                      if (controller != null) _trackPosition(controller);
                    },
                    customControlsBuilder:
                        (context, value, onVisibilityChanged) {
                          final controller = value as AppPlayerController?;
                          _controller ??= controller;
                          _onVisibilityChanged = onVisibilityChanged;
                          return controller?.isFullScreen == true
                              ? _controlsFor(controller)
                              : const SizedBox.shrink();
                        },
                  ),
                ),
              ),
              Positioned.fill(child: _controlsFor(_controller)),
              if (_playbackError != null)
                Positioned.fill(
                  child: PlayerPlaybackErrorOverlay(
                    message: _playbackError!,
                    retrying: _retrying,
                    onRetry: _retryPlayback,
                    onChangeSource: _resolvedSources.length > 1
                        ? _changeSource
                        : null,
                    onBack: () => _dismiss(_controller),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
