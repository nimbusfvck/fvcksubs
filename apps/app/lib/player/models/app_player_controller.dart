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
    this.width,
    this.bitrate,
    this.platformTrack,
  });

  final String id;
  final int height;

  /// The frame width, where the backend reports one. It is what names the
  /// rendition — see [qualityRungLabel].
  final int? width;

  final int? bitrate;
  final Object? platformTrack;
}

/// Names a rendition the way viewers meet it elsewhere: 720p, 1080p, 4K.
///
/// A wide release is letterboxed into its frame, so the rung a provider calls
/// 1080p arrives as 1920x800 and its 720p as 1280x534. The height is whatever
/// the aspect ratio left over — calling that "800p" names nothing anyone
/// recognises — while the width is the rung itself. So width decides, and
/// height only stands in for a backend that reports no width.
///
/// Answers `null` when neither says anything useful, which is a caller's cue
/// to say nothing rather than to invent a number.
String? qualityRungLabel({int? width, int? height}) {
  // Descending, and read as "at least this wide": the first rung a
  // measurement reaches is the one it belongs to.
  const byWidth = <int, String>{
    7680: '8K',
    3840: '4K',
    2560: '1440p',
    1920: '1080p',
    1280: '720p',
    854: '480p',
    640: '360p',
  };
  const byHeight = <int, String>{
    4320: '8K',
    2160: '4K',
    1440: '1440p',
    1080: '1080p',
    720: '720p',
    480: '480p',
    360: '360p',
  };

  String? rungFor(int? value, Map<int, String> rungs) {
    if (value == null || value <= 0) return null;
    for (final rung in rungs.entries) {
      // A little short still counts: encoders round, and 1912 wide is 1080p
      // by any reading.
      if (value >= rung.key * 0.95) return rung.value;
    }
    return null;
  }

  final named = rungFor(width, byWidth) ?? rungFor(height, byHeight);
  if (named != null) return named;
  // Below every rung the app names, the height is at least honest.
  return height != null && height > 0 ? '${height}p' : null;
}

class AppAudioTrack {
  const AppAudioTrack({
    required this.id,
    required this.label,
    this.language,
    this.details,
    this.nativeId,
    this.platformTrack,
  });

  final String id;
  final String label;
  final String? language;
  final String? details;

  /// The backend's own id for this track — libmpv's `aid`, ExoPlayer's track
  /// index. Kept alongside [id] because [id] is built for the picker and is
  /// not what the backend answers with when asked what is playing.
  final String? nativeId;

  final Object? platformTrack;
}

/// Finds the track a backend says it is playing.
///
/// Both backends hand out a *fresh* track object every time they rebuild
/// their track list, so the playing track can never be found by identity —
/// only by the backend's own id. Getting this wrong leaves the picker with
/// nothing marked as active.
AppAudioTrack? audioTrackByNativeId(
  List<AppAudioTrack> tracks,
  String? nativeId,
) {
  if (nativeId == null || nativeId.isEmpty) return null;
  for (final track in tracks) {
    if (track.nativeId == nativeId) return track;
  }
  return null;
}

String audioTrackLabel({
  required String? label,
  required String? language,
  String? details,
}) {
  final named = label?.trim();
  if (named != null && named.isNotEmpty && named.toLowerCase() != 'audio') {
    return named;
  }

  final normalizedLanguage = language?.trim();
  if (normalizedLanguage != null && normalizedLanguage.isNotEmpty) {
    final primary = normalizedLanguage
        .split(RegExp('[-_]'))
        .first
        .toLowerCase();
    return switch (primary) {
      'id' => 'Indonesia',
      'en' => 'English',
      'ja' => 'Japanese',
      'ko' => 'Korean',
      'zh' => 'Chinese',
      'ar' => 'Arabic',
      'es' => 'Spanish',
      'fr' => 'French',
      'de' => 'German',
      'pt' => 'Portuguese',
      'ru' => 'Russian',
      'und' => details?.trim().isNotEmpty == true ? details!.trim() : 'Audio',
      _ => normalizedLanguage,
    };
  }

  final technical = details?.trim();
  return technical == null || technical.isEmpty ? 'Audio' : technical;
}

String audioTrackBaseId({
  required String? id,
  required String? label,
  required String? language,
  required String? details,
}) {
  final candidates = [id, language, details, label];
  for (final candidate in candidates) {
    final value = candidate?.trim();
    if (value != null &&
        value.isNotEmpty &&
        value.toLowerCase() != 'audio' &&
        value.toLowerCase() != 'unknown') {
      return value;
    }
  }
  return 'audio';
}

String uniqueAudioTrackId({
  required String base,
  required int occurrence,
  required int index,
}) => occurrence == 0 ? base : '$base-$index';

String audioTrackPickerLabel(AppAudioTrack track, int index) {
  final label = audioTrackLabel(
    label: track.label,
    language: track.language,
    details: track.details,
  );
  return label.toLowerCase() == 'audio' ? 'Audio ${index + 1}' : label;
}

/// Picker labels for [tracks], one per track, each distinct.
///
/// Sources routinely name every rendition the same thing — the same title,
/// the same language tag, or nothing at all — and a picker showing
/// "Indonesia" three times cannot be chosen from: there is no way to tell
/// which row is the one being played, or which one the last tap selected.
///
/// A repeated label is qualified by what the tracks do not share: their codec
/// and channel layout first, since that is a real difference the viewer can
/// hear, and a position in the list only for tracks that are identical in
/// every respect the backend reports.
List<String> audioTrackPickerLabels(List<AppAudioTrack> tracks) {
  final labels = [
    for (final (index, track) in tracks.indexed)
      audioTrackPickerLabel(track, index),
  ];

  final repeated = _repeatedValues(labels);
  for (var index = 0; index < labels.length; index++) {
    if (!repeated.contains(labels[index])) continue;
    final details = tracks[index].details?.trim();
    if (details == null || details.isEmpty) continue;
    if (labels[index].toLowerCase().contains(details.toLowerCase())) continue;
    labels[index] = '${labels[index]} · $details';
  }

  final stillRepeated = _repeatedValues(labels);
  final ordinals = <String, int>{};
  for (var index = 0; index < labels.length; index++) {
    final label = labels[index];
    if (!stillRepeated.contains(label)) continue;
    final ordinal = (ordinals[label] ?? 0) + 1;
    ordinals[label] = ordinal;
    labels[index] = '$label $ordinal';
  }

  return labels;
}

Set<String> _repeatedValues(List<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return {
    for (final entry in counts.entries)
      if (entry.value > 1) entry.key,
  };
}

class PlayerSubtitleSelection {
  const PlayerSubtitleSelection.off() : track = null, isExternal = false;

  const PlayerSubtitleSelection.track(this.track, {this.isExternal = false});

  final SubtitleTrack? track;
  final bool isExternal;
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
  Future<void> setPlaybackSpeed(double speed);
  Future<void> setSubtitle(SubtitleTrack? track);
  Future<void> setQuality(AppQualityTrack? track);
  Future<void> setAudioTrack(AppAudioTrack track);
  Future<void> setFit(PlayerFitMode mode);
  Future<void> setViewportAspectRatio(double ratio);
  Future<void> toggleFullScreen();
  Future<void> exitFullScreen();
}
