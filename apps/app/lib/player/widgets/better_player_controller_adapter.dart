import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../mappers/stream_player_mapping.dart';
import '../models/app_player_controller.dart';

/// Maps the existing BetterPlayer API to the app-owned player contract.
class BetterPlayerControllerAdapter implements AppPlayerController {
  BetterPlayerControllerAdapter(this._controller) {
    _controller.addEventsListener(_onEvent);
  }

  final BetterPlayerController _controller;
  final ValueNotifier<AppPlayerValue> _value = ValueNotifier(
    const AppPlayerValue(),
  );
  final StreamController<AppPlayerEvent> _events = StreamController.broadcast();

  @override
  ValueListenable<AppPlayerValue> get value => _value;
  @override
  Stream<AppPlayerEvent> get events => _events.stream;
  @override
  List<AppQualityTrack> get qualityTracks => [
    for (final track in _controller.betterPlayerAsmsTracks)
      if ((track.height ?? 0) > 0)
        AppQualityTrack(
          id: '${track.height}:${track.bitrate ?? 0}',
          height: track.height!,
          bitrate: track.bitrate,
          platformTrack: track,
        ),
  ];
  @override
  AppQualityTrack? get activeQuality {
    final track = _controller.betterPlayerAsmsTrack;
    return track == null || (track.height ?? 0) <= 0
        ? null
        : AppQualityTrack(
            id: '${track.height}:${track.bitrate ?? 0}',
            height: track.height!,
            bitrate: track.bitrate,
            platformTrack: track,
          );
  }

  @override
  List<AppAudioTrack> get audioTracks {
    final occurrences = <String, int>{};
    return [
      for (final (index, track)
          in (_controller.betterPlayerAsmsAudioTracks ?? const []).indexed)
        _audioTrack(track, index, occurrences),
    ];
  }

  /// The track BetterPlayer is playing.
  ///
  /// Matched on the backend's own id rather than by identity: the adapter
  /// wraps the track list afresh on every read, so an identity check only
  /// happens to hold while the underlying list object is the same one.
  @override
  AppAudioTrack? get activeAudio => audioTrackByNativeId(
    audioTracks,
    _betterPlayerNativeAudioId(_controller.betterPlayerAsmsAudioTrack),
  );

  @override
  SubtitleTrack? get activeSubtitle {
    final source = _controller.betterPlayerSubtitlesSource;
    final urls = source?.urls;
    return source == null ||
            source.type == BetterPlayerSubtitlesSourceType.none ||
            urls == null ||
            urls.isEmpty
        ? null
        : SubtitleTrack(
            url: urls.first ?? '',
            label: source.name ?? 'Subtitle',
            language: 'und',
          );
  }

  @override
  bool get isFullScreen => _controller.isFullScreen;
  @override
  Future<void> exitFullScreen() async => _controller.exitFullScreen();
  @override
  Future<void> pause() => _controller.pause();
  @override
  Future<void> play() => _controller.play();
  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);
  @override
  Future<void> setQuality(AppQualityTrack? track) => _controller.setTrack(
    track?.platformTrack as BetterPlayerAsmsTrack? ??
        BetterPlayerAsmsTrack.defaultTrack(),
  );
  @override
  Future<void> setAudioTrack(AppAudioTrack track) async => _controller
      .setAudioTrack(track.platformTrack! as BetterPlayerAsmsAudioTrack);

  @override
  Future<void> setFit(PlayerFitMode mode) async {
    _controller.setOverriddenFit(
      mode == PlayerFitMode.contain ? BoxFit.contain : BoxFit.cover,
    );
  }

  @override
  Future<void> setViewportAspectRatio(double ratio) async {
    _controller.setOverriddenAspectRatio(ratio);
  }

  @override
  Future<void> setSubtitle(SubtitleTrack? track) =>
      _controller.setupSubtitleSource(
        track == null
            ? BetterPlayerSubtitlesSource(
                type: BetterPlayerSubtitlesSourceType.none,
                name: 'Off',
              )
            : subtitleSourceFor(track),
      );

  @override
  Future<void> toggleFullScreen() async => _controller.toggleFullScreen();

  AppAudioTrack _audioTrack(
    BetterPlayerAsmsAudioTrack track,
    int index,
    Map<String, int> occurrences,
  ) {
    final base = audioTrackBaseId(
      id: track.id?.toString(),
      label: track.label,
      language: track.language,
      details: null,
    );
    final occurrence = occurrences[base] ?? 0;
    occurrences[base] = occurrence + 1;
    return AppAudioTrack(
      id: uniqueAudioTrackId(base: base, occurrence: occurrence, index: index),
      label: audioTrackLabel(label: track.label, language: track.language),
      language: track.language,
      nativeId: _betterPlayerNativeAudioId(track),
      platformTrack: track,
    );
  }

  /// BetterPlayer's own handle on a track: the playlist id where there is
  /// one, and the rendition URL where there is not — DASH tracks carry an
  /// index, HLS renditions frequently carry neither.
  static String? _betterPlayerNativeAudioId(BetterPlayerAsmsAudioTrack? track) {
    if (track == null) return null;
    final id = track.id;
    if (id != null) return 'id:$id';
    final url = track.url?.trim();
    if (url != null && url.isNotEmpty) return 'url:$url';
    final label = track.label?.trim();
    return label == null || label.isEmpty ? null : 'label:$label';
  }

  void syncValue() {
    final next = _controller.videoPlayerController?.value;
    if (next == null) return;
    _value.value = AppPlayerValue(
      initialized: next.initialized,
      isPlaying: next.isPlaying,
      isBuffering: next.isBuffering,
      position: next.position,
      duration: next.duration ?? Duration.zero,
      bufferedPosition: next.buffered.isEmpty
          ? Duration.zero
          : next.buffered.last.end,
    );
  }

  void _onEvent(BetterPlayerEvent event) {
    syncValue();
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.finished:
        _events.add(const AppPlayerEvent(AppPlayerEventType.completed));
      case BetterPlayerEventType.exception:
        _events.add(
          AppPlayerEvent(
            AppPlayerEventType.error,
            error: event.parameters?['exception'],
          ),
        );
      default:
        break;
    }
  }

  void dispose() {
    _controller.removeEventsListener(_onEvent);
    _value.dispose();
    unawaited(_events.close());
  }
}
