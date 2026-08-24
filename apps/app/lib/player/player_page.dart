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
  Future<List<ResolvedSource>>? _refetch;
  late final NextEpisodeV2? _nextEpisode;
  bool _showUpNext = false;
  bool _upNextPaused = false;
  bool _advancing = false;
  LibraryController? _library;
  Timer? _progressTimer;
  ValueListenable<AppPlayerValue>? _videoValue;
  AppPlayerController? _trackedPositionController;
  bool _hasResumed = false;
  Duration? _lastPosition;
  Duration? _lastDuration;
  Duration? _pendingSwitchPosition;
  Duration? _pendingFitPosition;
  AppPlayerController? _pendingFitController;
  String? _playbackError;
  bool _retrying = false;
  int _sourceRevision = 0;
  int _playbackAttempt = 0;
  final Set<String> _failedSourceIds = <String>{};
  bool _sourceStarted = false;
  PlayerFitMode _fitMode = PlayerFitMode.contain;
  AppPlayerController? _aspectRatioController;
  double? _appliedViewportAspectRatio;
  bool? _systemUiImmersive;
  bool? _landscape;
  AppPlayerController? _controller;
  StreamSubscription<AppPlayerEvent>? _eventSubscription;
  void Function(bool visibility)? _onVisibilityChanged;

  bool get _isLive => widget.media.isLive;
  bool get _supportsFullScreen => defaultTargetPlatform == TargetPlatform.macOS;
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
    _syncSystemUi();
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

  /// Discovery again, on request, merged into what is already playing.
  ///
  /// One in-flight refetch at a time, and the guard lives here rather than in
  /// the sheet because closing and reopening the picker builds a fresh sheet:
  /// a sheet-local flag would let every reopen start another fan-out. That
  /// matters more than it looks — the extension runs on a single QuickJS
  /// event loop, so concurrent fan-outs compete with the resolves feeding
  /// playback instead of finishing any sooner.
  Future<List<ResolvedSource>> _refetchSources() =>
      _refetch ??= _runRefetch().whenComplete(() => _refetch = null);

  Future<List<ResolvedSource>> _runRefetch() async {
    final scope = AppScope.of(context);
    final found = await refetchPlayableSources(scope, widget.media);
    if (!mounted || found.isEmpty) return _resolvedSources;

    // Merge, never replace: the source being watched keeps playing and keeps
    // its place, exactly as it does for sources that settle late.
    final playingId = _current.source.id;
    final merged = mergeResolvedSources(_resolvedSources, found);
    scope.sourceCache.store(widget.media.ref, merged);
    scope.sourceCache.promote(widget.media.ref, playingId);
    setState(() {
      _resolvedSources = merged;
      _currentIndex = merged.indexWhere(
        (source) => source.source.id == playingId,
      );
      if (_currentIndex < 0) _currentIndex = 0;
    });
    return merged;
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _detachPositionListener();
    unawaited(_eventSubscription?.cancel());
    _reportProgress();
    final landscape = _landscape == true;
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
    super.dispose();
  }

  void _trackPosition(AppPlayerController controller) {
    final next = controller.value;
    if (identical(next, _videoValue) &&
        identical(controller, _trackedPositionController)) {
      return;
    }
    _detachPositionListener();
    _trackedPositionController = controller;
    _videoValue = next..addListener(_onVideoValueChanged);
    _onVideoValueChanged();
  }

  void _detachPositionListener() {
    _videoValue?.removeListener(_onVideoValueChanged);
    _videoValue = null;
    _trackedPositionController = null;
  }

  void _onVideoValueChanged() {
    final controller = _trackedPositionController;
    if (controller == null || !identical(controller, _controller)) return;
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
      unawaited(controller.seekTo(position));
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
      final position = _isLive ? null : _positionForSourceSwitch();
      _detachPositionListener();
      setState(() {
        _pendingSwitchPosition = position;
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
    if (!_supportsFullScreen) return;
    final controller = _controller;
    if (controller != null) unawaited(controller.toggleFullScreen());
  }

  void _toggleFit() {
    final controller = _controller;
    final position = !_isLive ? controller?.value.value.position : null;
    _pendingFitPosition = position;
    _pendingFitController = controller;
    final next = _fitMode.toggled;
    setState(() => _fitMode = next);
    _syncSystemUi();
    if (controller != null) unawaited(controller.setFit(next));
    if (position != null && controller != null) {
      unawaited(_restoreFitPosition(controller, position));
    }
  }

  Future<void> _restoreFitPosition(
    AppPlayerController controller,
    Duration position,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted ||
        _pendingFitPosition != position ||
        !identical(_pendingFitController, controller) ||
        !identical(_controller, controller)) {
      return;
    }
    _pendingFitPosition = null;
    _pendingFitController = null;
    final current = controller.value.value.position;
    final delta = current >= position ? current - position : position - current;
    if (delta > const Duration(seconds: 1)) {
      unawaited(controller.seekTo(position));
    }
  }

  void _syncSystemUi() {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    _landscape = landscape;
    final immersive = _fitMode == PlayerFitMode.cover || landscape;
    if (_systemUiImmersive == immersive) return;
    _systemUiImmersive = immersive;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _systemUiImmersive != immersive) return;
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        ),
      );
    });
  }

  void _switchToResolvedSource(int index) {
    if (index < 0 ||
        index >= _resolvedSources.length ||
        index == _currentIndex) {
      return;
    }
    final picked = _resolvedSources[index];
    final position = _isLive ? null : _positionForSourceSwitch();
    _detachPositionListener();
    _failedSourceIds.remove(picked.source.id);
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    setState(() {
      _pendingSwitchPosition = position;
      _currentIndex = index;
      _playbackAttempt++;
      _playbackError = null;
      _retrying = false;
      _sourceRevision++;
      _sourceStarted = false;
      _pendingFitPosition = null;
      _pendingFitController = null;
      _controller = null;
      _onVisibilityChanged = null;
    });
    AppScope.of(
      context,
    ).sourceCache.promote(widget.media.ref, picked.source.id);
  }

  Duration? _positionForSourceSwitch() {
    final value = _controller?.value.value;
    if (value != null && value.initialized) return value.position;
    return _lastPosition;
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
          onRefresh: _refetchSources,
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
        onToggleFullScreen: _supportsFullScreen ? _toggleFullScreen : null,
        fitMode: _fitMode,
        onToggleFit: _toggleFit,
        isLive: _isLive,
        episodeGuide: widget.episodeGuide,
        upNextV2: _showUpNext ? _nextEpisode : null,
        upNextPaused: _upNextPaused,
        onNearEnd: _showNextEpisode,
        onManualNext: _nextEpisode == null ? null : _playNextEpisode,
        onPlayNext: _playNextEpisode,
        onPauseUpNext: () => setState(() => _upNextPaused = true),
        onCancelUpNext: () => setState(() {
          _showUpNext = false;
          _upNextPaused = false;
        }),
      );

  Widget _buildPlayer(BuildContext context) =>
      AppScope.of(context).playerBuilder(
        context,
        _current.stream,
        isLive: _isLive,
        key: ValueKey('${_current.source.id}:$_sourceRevision'),
        preferredSubtitleLanguage: AppScope.of(
          context,
        ).subtitlePreferenceController.languageCode,
        subtitleAppearance: AppScope.of(
          context,
        ).subtitlePreferenceController.appearance,
        preferredExternalSubtitle: AppScope.of(context)
            .subtitlePreferenceController
            .rememberedExternalSubtitle(widget.media.ref),
        onControllerCreated: (value) {
          _controller = value as AppPlayerController?;
          if (_controller != null) {
            _attachEventListener(_controller!);
            unawaited(_controller!.setFit(_fitMode));
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        },
        onPlaybackReady: (value) {
          final controller = value as AppPlayerController?;
          if (controller != null) _trackPosition(controller);
        },
        customControlsBuilder: (context, value, onVisibilityChanged) {
          final controller = value as AppPlayerController?;
          _controller ??= controller;
          _onVisibilityChanged = onVisibilityChanged;
          return controller?.isFullScreen == true
              ? _controlsFor(controller)
              : const SizedBox.shrink();
        },
      );

  Widget _playerViewport(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final cover = _fitMode == PlayerFitMode.cover;
        final viewportRatio = maxHeight > 0 ? maxWidth / maxHeight : 16 / 9;
        final containWidth = maxHeight > 0 && viewportRatio > 16 / 9
            ? maxHeight * (16 / 9)
            : maxWidth;
        final containHeight = containWidth / (16 / 9);
        final ratio = cover ? viewportRatio : 16 / 9;
        final controller = _controller;
        if (controller != null &&
            (!identical(controller, _aspectRatioController) ||
                _appliedViewportAspectRatio != ratio)) {
          _aspectRatioController = controller;
          _appliedViewportAspectRatio = ratio;
          unawaited(controller.setViewportAspectRatio(ratio));
        }
        final player = _buildPlayer(context);
        return Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: cover ? maxWidth : containWidth,
            height: cover ? maxHeight : containHeight,
            child: player,
          ),
        );
      },
    );
  }

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
      if (_supportsFullScreen)
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
              _playerViewport(context),
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
                    onHide: () => setState(() => _playbackError = null),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
