import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

/// Backend-independent playback state consumed by the player route and UI.
class AppPlayerValue {
  const AppPlayerValue({
    this.initialized = false,
    this.isPlaying = false,
    this.isBuffering = true,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
  });

  final bool initialized;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;

  AppPlayerValue copyWith({
    bool? initialized,
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
  }) => AppPlayerValue(
    initialized: initialized ?? this.initialized,
    isPlaying: isPlaying ?? this.isPlaying,
    isBuffering: isBuffering ?? this.isBuffering,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    bufferedPosition: bufferedPosition ?? this.bufferedPosition,
  );
}

enum AppPlayerEventType { completed, error }

class AppPlayerEvent {
  const AppPlayerEvent(this.type, {this.error});

  final AppPlayerEventType type;
  final Object? error;
}

class AppQualityTrack {
  const AppQualityTrack({
    required this.id,
    required this.height,
    this.bitrate,
    this.platformTrack,
  });

  final String id;
  final int height;
  final int? bitrate;
  final Object? platformTrack;
}

class AppAudioTrack {
  const AppAudioTrack({
    required this.id,
    required this.label,
    this.language,
    this.platformTrack,
  });

  final String id;
  final String label;
  final String? language;
  final Object? platformTrack;
}

class PlayerSubtitleSelection {
  const PlayerSubtitleSelection.off() : track = null;

  const PlayerSubtitleSelection.track(this.track);

  final SubtitleTrack? track;
}

/// Controls whether the video keeps its source ratio or fills the viewport.
enum PlayerFitMode {
  contain,
  cover;

  PlayerFitMode get toggled => this == contain ? cover : contain;

  String get label => this == contain ? 'Fit ratio' : 'Fit screen';
}

abstract interface class AppPlayerController {
  ValueListenable<AppPlayerValue> get value;
  Stream<AppPlayerEvent> get events;
  List<AppQualityTrack> get qualityTracks;
  AppQualityTrack? get activeQuality;
  List<AppAudioTrack> get audioTracks;
  AppAudioTrack? get activeAudio;
  SubtitleTrack? get activeSubtitle;
  bool get isFullScreen;

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setSubtitle(SubtitleTrack? track);
  Future<void> setQuality(AppQualityTrack? track);
  Future<void> setAudioTrack(AppAudioTrack track);
  Future<void> setFit(PlayerFitMode mode);
  Future<void> setViewportAspectRatio(double ratio);
  Future<void> toggleFullScreen();
  Future<void> exitFullScreen();
}
