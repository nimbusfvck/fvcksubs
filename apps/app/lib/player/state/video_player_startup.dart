import 'dart:async';

import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:video_player/video_player.dart' as vp;

import '../diagnostics/player_diagnostics.dart';
import '../models/app_player_controller.dart';
import '../models/playback_start_position.dart';
import 'quality_preference_controller.dart';
import 'subtitle_preference_controller.dart';

/// Configures one native controller generation before starting playback.
/// Every await is guarded so replacement or disposal cannot resume old work.
class VideoPlayerStartup {
  VideoPlayerStartup({
    required this.player,
    required this.controller,
    required this.stream,
    required this.refreshTracks,
    required this.isCurrent,
    required this.log,
    required this.maxHeight,
    this.preferredQualityDone = false,
    // Live HLS can expose a valid playlist and segment before AVPlayer marks
    // the item ready. Keep replay/source-renewal initialization alive long
    // enough for that first moving live window to become playable.
    this.liveInitializeTimeout = const Duration(seconds: 20),
    this.initialSeekTimeout = const Duration(seconds: 8),
  });

  final vp.VideoPlayerController player;
  final AppPlayerController controller;
  final PlayableStream stream;
  final Future<void> Function() refreshTracks;
  final bool Function() isCurrent;
  final void Function(String stage, {String? details}) log;
  final int? maxHeight;
  bool preferredQualityDone;

  /// Prevents a live source that buffers forever before AVPlayer becomes ready
  /// from leaving the player route in an endless loading state.
  final Duration liveInitializeTimeout;

  /// Bounds a resume/source-switch seek that is waiting on a slow HLS origin.
  /// The controller generation is replaced after this error, so a late native
  /// completion cannot start playback from an obsolete source.
  final Duration initialSeekTimeout;

  Future<bool> open({
    required bool initialized,
    required bool looping,
    required bool muted,
    required bool playing,
    required bool isLive,
    PlaybackStartPosition? startPosition,
    String? subtitleLanguage,
    SubtitleTrack? externalSubtitle,
  }) async {
    if (!isCurrent()) return false;
    if (stream.audioUrl?.isNotEmpty == true) {
      throw UnsupportedError(
        'The native player does not support a separate audio URL.',
      );
    }
    if (!initialized) {
      log(
        'initialize_start',
        details:
            'url=${safePlaybackUrlForLog(stream.url)} '
            'format=${stream.format.name} '
            'live=$isLive '
            'timeout_s=${isLive ? liveInitializeTimeout.inMilliseconds / 1000 : 'none'}',
      );
      try {
        final initialization = player.initialize();
        if (isLive) {
          await initialization.timeout(liveInitializeTimeout);
        } else {
          await initialization;
        }
      } on TimeoutException {
        log(
          'initialize_timeout',
          details:
              'live=true timeout_s=${liveInitializeTimeout.inMilliseconds / 1000}',
        );
        rethrow;
      }
      if (!isCurrent()) return false;
      log(
        'initialize_done',
        details:
            'duration=${player.value.duration.inMilliseconds}ms '
            'size=${player.value.size.width}x${player.value.size.height}',
      );
    } else {
      log('initialize_reused');
    }
    await player.setLooping(looping);
    if (!isCurrent()) return false;
    await player.setVolume(muted ? 0 : 1);
    if (!isCurrent()) return false;
    log('player_configured');
    await refreshTracks();
    if (!isCurrent()) return false;
    log(
      'tracks_initial_done',
      details:
          'audio=${controller.audioTracks.length} '
          'video=${controller.qualityTracks.length}',
    );
    await applyPreferredQuality();
    if (!isCurrent()) return false;
    log(
      'quality_initial_done',
      details: 'active=${controller.activeQuality?.id ?? 'auto'}',
    );
    final target = startPosition?.target(player.value.duration, isLive: isLive);
    if (target != null) {
      log('initial_seek_start', details: 'target_ms=${target.inMilliseconds}');
      try {
        await player.seekTo(target).timeout(initialSeekTimeout);
      } on TimeoutException {
        log(
          'initial_seek_timeout',
          details:
              'target_ms=${target.inMilliseconds} '
              'timeout_s=${initialSeekTimeout.inMilliseconds / 1000}',
        );
        rethrow;
      }
      if (!isCurrent()) return false;
      log('initial_seek_done');
    }
    final subtitle =
        externalSubtitle ??
        stream.subtitles
            .where(
              (track) =>
                  subtitleLanguage != null &&
                  subtitleLanguageKey(track.language) ==
                      subtitleLanguageKey(subtitleLanguage),
            )
            .firstOrNull;
    if (subtitle != null) {
      log('subtitle_start', details: 'language=${subtitle.language}');
      try {
        await controller.setSubtitle(subtitle);
      } catch (_) {
        // An external caption must not fail otherwise playable video.
      }
      if (!isCurrent()) return false;
      log('subtitle_done');
    } else {
      log('subtitle_skipped');
    }
    if (playing) {
      log('play_start');
      await player.play();
      if (!isCurrent()) return false;
      log('play_done');
    } else {
      log('play_skipped');
    }
    return true;
  }

  Future<void> applyPreferredQuality() async {
    if (!isCurrent() || preferredQualityDone) return;
    final track = preferredQualityTrack(
      tracks: controller.qualityTracks,
      maxHeight: maxHeight,
    );
    if (track == null) return;
    if (track.id == controller.activeQuality?.id) {
      preferredQualityDone = true;
      return;
    }
    try {
      await controller.setQuality(track);
      if (!isCurrent()) return;
      preferredQualityDone = true;
    } catch (error) {
      log('preferred_quality_unavailable', details: '${error.runtimeType}');
    }
  }

  Future<void> refreshAfterMetadata() async {
    if (_hasUsableTrackMetadata) return;
    var attempt = 0;
    for (final delay in const [
      Duration(seconds: 1),
      Duration(seconds: 3),
      Duration(seconds: 6),
    ]) {
      await Future<void>.delayed(delay);
      if (!isCurrent()) return;
      attempt++;
      log('tracks_retry_start', details: 'attempt=$attempt');
      try {
        await refreshTracks();
        if (!isCurrent()) return;
        await applyPreferredQuality();
        if (!isCurrent()) return;
        log(
          'tracks_retry_done',
          details:
              'attempt=$attempt '
              'audio=${controller.audioTracks.length} video=${controller.qualityTracks.length}',
        );
        if (_hasUsableTrackMetadata) return;
      } catch (_) {
        log('tracks_retry_failed', details: 'attempt=$attempt');
      }
    }
  }

  bool get _hasUsableTrackMetadata =>
      controller.audioTracks.isNotEmpty && controller.qualityTracks.isNotEmpty;
}
