import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/foundation.dart';
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
  List<AppAudioTrack> get audioTracks => [
    for (final track in _controller.betterPlayerAsmsAudioTracks ?? const [])
      _audioTrack(track),
  ];

  @override
  AppAudioTrack? get activeAudio {
    final track = _controller.betterPlayerAsmsAudioTrack;
    return track == null ? null : _audioTrack(track);
  }

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

  AppAudioTrack _audioTrack(BetterPlayerAsmsAudioTrack track) => AppAudioTrack(
    id: '${track.id ?? track.label ?? track.language ?? 'audio'}',
    label: track.label ?? track.language ?? 'Audio',
    language: track.language,
    platformTrack: track,
  );

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
