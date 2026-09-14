part of 'video_player_view.dart';

class _VideoPlayerControllerAdapter
    implements
        AppPlayerController,
        AppPlayerPictureInPictureRestorer,
        AppPlayerPictureInPicturePolicy {
  _VideoPlayerControllerAdapter(
    this._player, {
    required this.onSetFit,
    required this.onSelectVariant,
    required String streamUrl,
    this.variants = const [],
  }) : _activeUrl = streamUrl;

  vp.VideoPlayerController _player;
  final void Function(PlayerFitMode mode) onSetFit;
  final Future<bool> Function(StreamVariant? variant) onSelectVariant;
  final List<StreamVariant> variants;
  String _activeUrl;
  final ValueNotifier<AppPlayerValue> _value = ValueNotifier(
    const AppPlayerValue(),
  );
  final StreamController<AppPlayerEvent> _events = StreamController.broadcast();
  List<vp.VideoAudioTrack> _nativeAudioTracks = const [];
  List<vp.VideoTrack> _nativeVideoTracks = const [];
  SubtitleTrack? _activeSubtitle;
  String? _selectedAudioId;
  String? _requestedVideoId;
  String? _selectedVariantId;
  String? _pendingVariantId;
  bool _hasPendingVariant = false;
  int _qualityRequestGeneration = 0;
  bool _reportedCompletion = false;
  String? _reportedError;
  bool _disposed = false;

  @override
  ValueListenable<AppPlayerValue> get value => _value;
  @override
  Stream<AppPlayerEvent> get events => _events.stream;
  @override
  List<AppQualityTrack> get qualityTracks => dedupedQualityTracks([
    for (final track in _nativeVideoTracks)
      if ((track.height ?? 0) > 0)
        AppQualityTrack(
          id: track.id,
          height: track.height!,
          width: track.width,
          bitrate: track.bitrate,
          platformTrack: track,
        ),
    for (final variant in variants)
      if ((variant.height ?? 0) > 0)
        AppQualityTrack(
          id: variant.id,
          height: variant.height!,
          width: variant.width,
          bitrate: variant.bitrate,
          variant: variant,
        ),
  ]);
  @override
  AppQualityTrack? get activeQuality {
    final variantId = _hasPendingVariant
        ? _pendingVariantId
        : _selectedVariantId;
    if (variantId != null) {
      return qualityTracks.where((track) => track.id == variantId).firstOrNull;
    }
    final id = _selectedNativeVideoId ?? _requestedVideoId;
    if (id == null) {
      final matching = variants
          .where((variant) => variant.url == _activeUrl)
          .firstOrNull;
      if (matching != null) {
        return qualityTracks
            .where((track) => track.id == matching.id)
            .firstOrNull;
      }
      return null;
    }
    for (final track in qualityTracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  @override
  List<AppAudioTrack> get audioTracks {
    final occurrences = <String, int>{};
    return [
      for (final (index, track) in _nativeAudioTracks.indexed)
        _audioTrack(track, index, occurrences),
    ];
  }

  @override
  AppAudioTrack? get activeAudio => audioTrackByNativeId(
    audioTracks,
    _selectedAudioId ??
        _nativeAudioTracks
            .where((track) => track.isSelected)
            .map((track) => track.id)
            .firstOrNull,
  );
  @override
  SubtitleTrack? get activeSubtitle => _activeSubtitle;
  @override
  bool get isFullScreen => false;

  Future<void> refreshTracks() async {
    if (_disposed) return;
    try {
      if (_player.isAudioTrackSupportAvailable()) {
        final tracks = await _player.getAudioTracks();
        if (_disposed) return;
        _nativeAudioTracks = tracks;
      }
    } catch (error) {
      _nativeAudioTracks = const [];
      _logTrackError('audio', error);
    }
    try {
      if (_player.isVideoTrackSupportAvailable()) {
        final tracks = await _player.getVideoTracks();
        if (_disposed) return;
        _nativeVideoTracks = tracks;
      }
    } catch (error) {
      _nativeVideoTracks = const [];
      _logTrackError('video', error);
    }
    _selectedAudioId ??= _nativeAudioTracks
        .where((track) => track.isSelected)
        .map((track) => track.id)
        .firstOrNull;
    _requestedVideoId ??= _selectedNativeVideoId;
    if (kDebugMode) {
      debugPrint(
        '[VideoPlayerVOD] tracks '
        'audio=${_nativeAudioTracks.length} '
        'video=${_nativeVideoTracks.length} '
        'quality_requested=${_videoTrackDescriptionById(_requestedVideoId)} '
        'quality_target=${_videoTrackDescription(_selectedNativeVideo)}',
      );
    }
    if (!_disposed) _value.value = _value.value.copyWith();
  }

  /// Rebinds the adapter after the app swaps the network URL for a provider
  /// rendition. The provider selection remains active across the native
  /// controller replacement.
  void attachPlayer(vp.VideoPlayerController player) {
    _player = player;
    _nativeAudioTracks = const [];
    _nativeVideoTracks = const [];
    _selectedAudioId = null;
    _requestedVideoId = null;
    _reportedCompletion = false;
    _reportedError = null;
    if (!_disposed) _value.value = _value.value.copyWith();
  }

  void setActiveUrl(String url) => _activeUrl = url;

  void _logTrackError(String kind, Object error) {
    if (!kDebugMode) return;
    debugPrint(
      '[VideoPlayerVOD] ${kind}_tracks_unavailable ${error.runtimeType}',
    );
  }

  void syncValue() {
    final source = _player.value;
    final buffered = source.buffered.fold<Duration>(
      Duration.zero,
      (latest, range) => range.end > latest ? range.end : latest,
    );
    final seekable = source.seekable.fold<Duration>(
      Duration.zero,
      (latest, range) => range.end > latest ? range.end : latest,
    );
    _value.value = AppPlayerValue(
      initialized: source.isInitialized,
      isPlaying: source.isPlaying,
      isBuffering: source.isBuffering,
      position: source.position,
      duration: source.duration,
      bufferedPosition: buffered,
      bufferedRanges: [
        for (final range in source.buffered)
          AppPlayerTimeRange(range.start, range.end),
      ],
      seekablePosition: seekable,
    );
  }

  void reportCompleted() {
    if (_disposed || _reportedCompletion) return;
    _reportedCompletion = true;
    _events.add(const AppPlayerEvent(AppPlayerEventType.completed));
  }

  void reportError(Object error) {
    if (_disposed) return;
    final text = error.toString();
    if (_reportedError == text) return;
    _reportedError = text;
    _events.add(AppPlayerEvent(AppPlayerEventType.error, error: error));
  }

  void reportPictureInPictureRestore() {
    if (_disposed) return;
    _events.add(
      const AppPlayerEvent(AppPlayerEventType.pictureInPictureRestore),
    );
  }

  void reportPictureInPictureStarted() {
    if (_disposed) return;
    _events.add(
      const AppPlayerEvent(AppPlayerEventType.pictureInPictureStarted),
    );
  }

  void reportPictureInPictureClosed() {
    if (_disposed) return;
    _events.add(
      const AppPlayerEvent(AppPlayerEventType.pictureInPictureClosed),
    );
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seekTo(Duration position) => _player.seekTo(position);
  @override
  Future<void> setPlaybackSpeed(double speed) =>
      _player.setPlaybackSpeed(speed);
  @override
  Future<void> setQuality(AppQualityTrack? track) async {
    final variant = track?.variant;
    final requestGeneration = ++_qualityRequestGeneration;
    if (variant != null) {
      _hasPendingVariant = true;
      _pendingVariantId = variant.id;
      if (!_disposed) _value.value = _value.value.copyWith();
      if (kDebugMode) {
        debugPrint('[VideoPlayerVOD] quality_request variant=${variant.label}');
      }
      final switched = await onSelectVariant(variant);
      if (!_disposed && requestGeneration == _qualityRequestGeneration) {
        if (switched) _selectedVariantId = variant.id;
        _hasPendingVariant = false;
        _pendingVariantId = null;
        _value.value = _value.value.copyWith();
      }
      if (!switched) {
        throw StateError('Video variant switch did not complete.');
      }
      return;
    }
    if (track == null || track.id == 'auto') {
      _hasPendingVariant = true;
      _pendingVariantId = null;
      if (!_disposed) _value.value = _value.value.copyWith();
      final switched = await onSelectVariant(null);
      if (!_disposed && requestGeneration == _qualityRequestGeneration) {
        if (switched) _selectedVariantId = null;
        _hasPendingVariant = false;
        _pendingVariantId = null;
        _value.value = _value.value.copyWith();
      }
      if (!switched) {
        throw StateError('Automatic quality switch did not complete.');
      }
      return;
    }
    _hasPendingVariant = false;
    _pendingVariantId = null;
    if (!_disposed) _value.value = _value.value.copyWith();
    final native = track.platformTrack as vp.VideoTrack?;
    if (kDebugMode) {
      debugPrint(
        '[VideoPlayerVOD] quality_request '
        'target=${_videoTrackDescription(native)}',
      );
    }
    await _player.selectVideoTrack(native);
    _requestedVideoId = native?.id;
    // AVFoundation applies a preferred peak bitrate asynchronously. Refreshing
    // after this turn records the cap accepted by the native player.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await refreshTracks();
  }

  @override
  Future<void> setViewportAspectRatio(double ratio) async {}
  @override
  Future<void> toggleFullScreen() async {}
  @override
  Future<void> exitFullScreen() async {}
  @override
  Future<bool> startPictureInPicture() => _player.startPictureInPicture();

  @override
  Future<void> setPictureInPictureAllowed(bool allowed) =>
      _player.setPictureInPictureAllowed(allowed);

  @override
  Future<void> stopPictureInPicture() => _player.stopPictureInPicture();

  @override
  Future<void> completePictureInPictureRestore() =>
      _player.completePictureInPictureRestore();
  @override
  Future<void> setFit(PlayerFitMode mode) async => onSetFit(mode);

  @override
  Future<void> setAudioTrack(AppAudioTrack track) async {
    final native = track.platformTrack as vp.VideoAudioTrack;
    await _player.selectAudioTrack(native.id);
    _selectedAudioId = native.id;
    await refreshTracks();
  }

  @override
  Future<void> setSubtitle(SubtitleTrack? track) async {
    if (track == null) {
      await _player.setClosedCaptionFile(null);
      _activeSubtitle = null;
      if (kDebugMode) debugPrint('[VideoPlayerVOD] subtitle_disabled');
      return;
    }
    try {
      final format = _subtitleFormat(track.url);
      if (kDebugMode) {
        debugPrint(
          '[VideoPlayerVOD] subtitle_request '
          'language=${track.language} format=$format',
        );
      }
      final captionDownload = await _downloadCaptionFile(track.url);
      if (kDebugMode) {
        final captions = captionDownload.captionFile.captions;
        debugPrint(
          '[VideoPlayerVOD] subtitle_clock '
          'video_duration_ms=${_player.value.duration.inMilliseconds} '
          'first_cue_ms=${captions.firstOrNull?.start.inMilliseconds ?? '-'} '
          'last_cue_ms=${captions.lastOrNull?.end.inMilliseconds ?? '-'}',
        );
      }
      if (captionDownload.captionFile.captions.isEmpty) {
        throw _UnsupportedCaptionFormat(
          format: captionDownload.format,
          contentType: captionDownload.contentType,
        );
      }
      await _player.setClosedCaptionFile(
        Future<vp.ClosedCaptionFile>.value(captionDownload.captionFile),
      );
      _activeSubtitle = track;
      if (kDebugMode) {
        debugPrint(
          '[VideoPlayerVOD] subtitle_applied '
          'language=${track.language} source_format=$format '
          'content_format=${captionDownload.format} '
          'content_type=${captionDownload.contentType ?? 'unknown'} '
          'cues=${captionDownload.captionFile.captions.length}',
        );
      }
    } catch (error) {
      reportSubtitleError(track, error);
    }
  }

  void reportSubtitleError(SubtitleTrack track, Object error) {
    if (!kDebugMode) return;
    final details = switch (error) {
      _UnsupportedCaptionFormat(
        format: final format,
        contentType: final contentType,
      ) =>
        'content_format=$format content_type=${contentType ?? 'unknown'}',
      _ => 'source_format=${_subtitleFormat(track.url)}',
    };
    debugPrint(
      '[VideoPlayerVOD] subtitle_unavailable '
      'language=${track.language} $details error=${error.runtimeType}',
    );
  }

  String? get _selectedNativeVideoId => _selectedNativeVideo?.id;

  vp.VideoTrack? get _selectedNativeVideo =>
      _nativeVideoTracks.where((track) => track.isSelected).firstOrNull;

  String _videoTrackDescriptionById(String? id) {
    if (id == null) return 'auto';
    return _videoTrackDescription(
      _nativeVideoTracks.where((track) => track.id == id).firstOrNull,
    );
  }

  String _videoTrackDescription(vp.VideoTrack? track) {
    if (track == null) return 'auto';
    final dimensions = switch ((track.width, track.height)) {
      (final width?, final height?) => '${width}x$height',
      _ => 'unknown',
    };
    return '${track.id} $dimensions bitrate=${track.bitrate ?? 'unknown'}';
  }

  AppAudioTrack _audioTrack(
    vp.VideoAudioTrack track,
    int index,
    Map<String, int> occurrences,
  ) {
    final details = [
      track.codec,
      if (track.channelCount != null) '${track.channelCount}ch',
    ].whereType<String>().join(' · ');
    final base = audioTrackBaseId(
      id: track.id,
      label: track.label,
      language: track.language,
      details: details,
    );
    final occurrence = occurrences[base] ?? 0;
    occurrences[base] = occurrence + 1;
    return AppAudioTrack(
      id: uniqueAudioTrackId(base: base, occurrence: occurrence, index: index),
      nativeId: track.id,
      label: audioTrackLabel(
        label: track.label,
        language: track.language,
        details: details,
      ),
      language: track.language,
      details: details.isEmpty ? null : details,
      platformTrack: track,
    );
  }

  void dispose() {
    _disposed = true;
    _value.dispose();
    unawaited(_events.close());
  }
}
