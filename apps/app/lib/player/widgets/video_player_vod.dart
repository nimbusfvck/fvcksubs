import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:video_player/video_player.dart' as vp;

import '../diagnostics/player_diagnostics.dart';
import '../models/app_player_controller.dart';
import '../state/quality_preference_controller.dart';
import '../state/subtitle_preference_controller.dart';
import 'player_subtitle_style.dart';

/// Video player backend for on-demand playback on iOS and macOS.
class VideoPlayerVodView extends StatefulWidget {
  const VideoPlayerVodView({
    super.key,
    required this.stream,
    this.onControllerCreated,
    this.onPlaybackReady,
    this.preferredSubtitleLanguage,
    this.preferredQualityMaxHeight,
    this.preferredExternalSubtitle,
    this.subtitleAppearance,
    this.muted = false,
    this.looping = false,
    this.playing = true,
    this.fit = BoxFit.contain,
  });

  final PlayableStream stream;
  final void Function(Object? controller)? onControllerCreated;
  final void Function(Object? controller)? onPlaybackReady;
  final String? preferredSubtitleLanguage;
  final int? preferredQualityMaxHeight;
  final SubtitleTrack? preferredExternalSubtitle;
  final SubtitleAppearance? subtitleAppearance;
  final bool muted;
  final bool looping;
  final bool playing;
  final BoxFit fit;

  @override
  State<VideoPlayerVodView> createState() => _VideoPlayerVodViewState();
}

class _VideoPlayerVodViewState extends State<VideoPlayerVodView> {
  late final vp.VideoPlayerController _player;
  late final _VideoPlayerControllerAdapter _adapter;
  late PlayerFitMode _fitMode;
  bool _readyReported = false;
  bool _preferredQualitySelectionDone = false;
  Stopwatch? _openStopwatch;
  bool _nativePlayingReported = false;

  @override
  void initState() {
    super.initState();
    _fitMode = widget.fit == BoxFit.contain
        ? PlayerFitMode.contain
        : PlayerFitMode.cover;
    _player = vp.VideoPlayerController.networkUrl(
      Uri.parse(widget.stream.url),
      httpHeaders: widget.stream.headers,
    );
    _adapter = _VideoPlayerControllerAdapter(
      _player,
      onSetFit: (mode) {
        if (mounted) setState(() => _fitMode = mode);
      },
    );
    _player.addListener(_onValueChanged);
    widget.onControllerCreated?.call(_adapter);
    unawaited(_open());
  }

  Future<void> _open() async {
    final stopwatch = Stopwatch()..start();
    _openStopwatch = stopwatch;
    try {
      _logOpenStage(
        'initialize_start',
        stopwatch,
        details:
            'url=${safePlaybackUrlForLog(widget.stream.url)} '
            'format=${widget.stream.format.name}',
      );
      await _player.initialize();
      _logOpenStage(
        'initialize_done',
        stopwatch,
        details:
            'duration=${_player.value.duration.inMilliseconds}ms '
            'size=${_player.value.size.width}x${_player.value.size.height}',
      );
      await _player.setLooping(widget.looping);
      await _player.setVolume(widget.muted ? 0 : 1);
      _logOpenStage('player_configured', stopwatch);
      await _adapter.refreshTracks();
      _logOpenStage(
        'tracks_initial_done',
        stopwatch,
        details:
            'audio=${_adapter.audioTracks.length} '
            'video=${_adapter.qualityTracks.length}',
      );
      await _applyPreferredQuality();
      _logOpenStage(
        'quality_initial_done',
        stopwatch,
        details: 'active=${_adapter.activeQuality?.id ?? 'auto'}',
      );
      // AVFoundation can report the first frame before it has finished
      // populating its HLS media-selection and variant groups. FlyStream's
      // large master can take seconds, so keep checking briefly rather than
      // freezing the picker empty at the instant its first frame appears.
      unawaited(_refreshTracksAfterMetadata(stopwatch));
      final subtitle = _preferredSubtitle();
      if (subtitle != null) {
        _logOpenStage(
          'subtitle_start',
          stopwatch,
          details: 'language=${subtitle.language}',
        );
        try {
          await _adapter.setSubtitle(subtitle);
        } catch (_) {
          // An external caption must not make an otherwise playable video fail.
        }
        _logOpenStage('subtitle_done', stopwatch);
      } else {
        _logOpenStage('subtitle_skipped', stopwatch);
      }
      if (widget.playing) {
        _logOpenStage('play_start', stopwatch);
        await _player.play();
        _logOpenStage('play_done', stopwatch);
      } else {
        _logOpenStage('play_skipped', stopwatch);
      }
      if (!mounted) return;
      _readyReported = true;
      _logOpenStage('ready_reported', stopwatch);
      widget.onPlaybackReady?.call(_adapter);
    } catch (error) {
      _logOpenStage(
        'failed',
        stopwatch,
        details: 'error=${redactPlaybackLogText(error)}',
      );
      _adapter.reportError(error);
    }
  }

  void _logOpenStage(String stage, Stopwatch stopwatch, {String? details}) {
    if (!kDebugMode) return;
    debugPrint(
      '[VideoPlayerVOD] open_stage=$stage '
      'elapsed=${stopwatch.elapsedMilliseconds}ms'
      '${details == null ? '' : ' $details'}',
    );
  }

  Future<void> _refreshTracksAfterMetadata(Stopwatch stopwatch) async {
    var attempt = 0;
    for (final delay in const [
      Duration(seconds: 1),
      Duration(seconds: 3),
      Duration(seconds: 6),
    ]) {
      await Future<void>.delayed(delay);
      if (!mounted) return;
      attempt++;
      _logOpenStage(
        'tracks_retry_start',
        stopwatch,
        details: 'attempt=$attempt',
      );
      try {
        await _adapter.refreshTracks();
        await _applyPreferredQuality();
        _logOpenStage(
          'tracks_retry_done',
          stopwatch,
          details:
              'attempt=$attempt audio=${_adapter.audioTracks.length} '
              'video=${_adapter.qualityTracks.length}',
        );
      } catch (_) {
        // An HLS source with no selectable group simply keeps an empty picker.
        _logOpenStage(
          'tracks_retry_failed',
          stopwatch,
          details: 'attempt=$attempt',
        );
      }
    }
  }

  Future<void> _applyPreferredQuality() async {
    if (_preferredQualitySelectionDone) return;
    final track = preferredQualityTrack(
      tracks: _adapter.qualityTracks,
      maxHeight: widget.preferredQualityMaxHeight,
    );
    if (track == null) return;
    if (track.id == _adapter.activeQuality?.id) {
      _preferredQualitySelectionDone = true;
      return;
    }
    try {
      await _adapter.setQuality(track);
      _preferredQualitySelectionDone = true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[VideoPlayerVOD] preferred_quality_unavailable '
          '${error.runtimeType}',
        );
      }
    }
  }

  SubtitleTrack? _preferredSubtitle() {
    final external = widget.preferredExternalSubtitle;
    if (external != null) return external;
    final language = widget.preferredSubtitleLanguage;
    if (language == null) return null;
    for (final track in widget.stream.subtitles) {
      if (subtitleLanguageKey(track.language) ==
          subtitleLanguageKey(language)) {
        return track;
      }
    }
    return null;
  }

  void _onValueChanged() {
    _adapter.syncValue();
    final value = _player.value;
    if (value.isPlaying && !_nativePlayingReported) {
      _nativePlayingReported = true;
      final stopwatch = _openStopwatch;
      if (stopwatch != null) {
        _logOpenStage('native_playing', stopwatch);
      }
    }
    if (value.hasError) {
      _adapter.reportError(value.errorDescription!);
    }
    if (value.isCompleted) {
      _adapter.reportCompleted();
    }
    if (value.isInitialized && !_readyReported) {
      _readyReported = true;
      widget.onPlaybackReady?.call(_adapter);
    }
  }

  @override
  void didUpdateWidget(covariant VideoPlayerVodView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fit != widget.fit) {
      final nextFit = widget.fit == BoxFit.contain
          ? PlayerFitMode.contain
          : PlayerFitMode.cover;
      if (_fitMode != nextFit) setState(() => _fitMode = nextFit);
    }
    if (oldWidget.playing != widget.playing) {
      unawaited(widget.playing ? _player.play() : _player.pause());
    }
    if (oldWidget.muted != widget.muted) {
      unawaited(_player.setVolume(widget.muted ? 0 : 1));
    }
  }

  @override
  void dispose() {
    _player.removeListener(_onValueChanged);
    _adapter.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<vp.VideoPlayerValue>(
        valueListenable: _player,
        builder: (context, value, _) {
          if (!value.isInitialized) {
            return const ColoredBox(color: Colors.black);
          }
          final videoSize = value.size;
          final child = SizedBox(
            width: videoSize.width,
            height: videoSize.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                vp.VideoPlayer(_player),
                vp.ClosedCaption(
                  text: value.caption.text,
                  textStyle:
                      widget.subtitleAppearance?.textStyle ??
                      playerSubtitleTextStyle,
                ),
              ],
            ),
          );
          return ColoredBox(
            color: Colors.black,
            child: ClipRect(
              child: SizedBox.expand(
                child: FittedBox(
                  fit: _fitMode == PlayerFitMode.contain
                      ? BoxFit.contain
                      : BoxFit.cover,
                  alignment: Alignment.center,
                  clipBehavior: Clip.hardEdge,
                  child: child,
                ),
              ),
            ),
          );
        },
      );
}

class _VideoPlayerControllerAdapter implements AppPlayerController {
  _VideoPlayerControllerAdapter(this._player, {required this.onSetFit});

  final vp.VideoPlayerController _player;
  final void Function(PlayerFitMode mode) onSetFit;
  final ValueNotifier<AppPlayerValue> _value = ValueNotifier(
    const AppPlayerValue(),
  );
  final StreamController<AppPlayerEvent> _events = StreamController.broadcast();
  List<vp.VideoAudioTrack> _nativeAudioTracks = const [];
  List<vp.VideoTrack> _nativeVideoTracks = const [];
  SubtitleTrack? _activeSubtitle;
  String? _selectedAudioId;
  String? _requestedVideoId;
  bool _reportedCompletion = false;
  String? _reportedError;

  @override
  ValueListenable<AppPlayerValue> get value => _value;
  @override
  Stream<AppPlayerEvent> get events => _events.stream;
  @override
  List<AppQualityTrack> get qualityTracks => [
    for (final track in _nativeVideoTracks)
      if ((track.height ?? 0) > 0)
        AppQualityTrack(
          id: track.id,
          height: track.height!,
          width: track.width,
          bitrate: track.bitrate,
          platformTrack: track,
        ),
  ];
  @override
  AppQualityTrack? get activeQuality {
    final id = _selectedNativeVideoId ?? _requestedVideoId;
    if (id == null) return null;
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
    try {
      if (_player.isAudioTrackSupportAvailable()) {
        _nativeAudioTracks = await _player.getAudioTracks();
      }
    } catch (error) {
      _nativeAudioTracks = const [];
      _logTrackError('audio', error);
    }
    try {
      if (_player.isVideoTrackSupportAvailable()) {
        _nativeVideoTracks = await _player.getVideoTracks();
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
    _value.value = _value.value.copyWith();
  }

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
    _value.value = AppPlayerValue(
      initialized: source.isInitialized,
      isPlaying: source.isPlaying,
      isBuffering: source.isBuffering,
      position: source.position,
      duration: source.duration,
      bufferedPosition: buffered,
    );
  }

  void reportCompleted() {
    if (_reportedCompletion) return;
    _reportedCompletion = true;
    _events.add(const AppPlayerEvent(AppPlayerEventType.completed));
  }

  void reportError(Object error) {
    final text = error.toString();
    if (_reportedError == text) return;
    _reportedError = text;
    _events.add(AppPlayerEvent(AppPlayerEventType.error, error: error));
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
    final native = track?.platformTrack as vp.VideoTrack?;
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
    _value.dispose();
    unawaited(_events.close());
  }
}

Future<_DownloadedCaptionFile> _downloadCaptionFile(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException('Subtitle request failed: ${response.statusCode}');
    }
    final contentType = response.headers.contentType?.mimeType.toLowerCase();
    final text = await utf8.decoder.bind(response).join();
    final parsedCaptions = _parseCaptions(text);
    if (kDebugMode) {
      final lineEnding = text.contains('\r\n')
          ? 'crlf'
          : text.contains('\n')
          ? 'lf'
          : text.contains('\r')
          ? 'cr'
          : 'none';
      final timingMarkers = RegExp(r'-->').allMatches(text).length;
      final firstTimingLine = text
          .split(RegExp(r'\r?\n'))
          .where((line) => line.contains('-->'))
          .firstOrNull;
      debugPrint(
        '[VideoPlayerVOD] subtitle_payload '
        'chars=${text.length} line_ending=$lineEnding '
        'timing_markers=$timingMarkers '
        'timing_shape=${_timingShape(firstTimingLine)} '
        'parsed_cues=${parsedCaptions.length}',
      );
    }
    return _DownloadedCaptionFile(
      captionFile: _CaptionFile(parsedCaptions),
      format: _captionContentFormat(text, contentType),
      contentType: contentType,
    );
  } finally {
    client.close(force: true);
  }
}

String _subtitleFormat(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final extension = path.lastIndexOf('.') < 0
      ? ''
      : path.substring(path.lastIndexOf('.') + 1).toLowerCase();
  return extension.isEmpty ? 'unknown' : extension;
}

class _CaptionFile extends vp.ClosedCaptionFile {
  _CaptionFile(this.captions);

  @override
  final List<vp.Caption> captions;
}

class _DownloadedCaptionFile {
  const _DownloadedCaptionFile({
    required this.captionFile,
    required this.format,
    required this.contentType,
  });

  final _CaptionFile captionFile;
  final String format;
  final String? contentType;
}

class _UnsupportedCaptionFormat implements Exception {
  const _UnsupportedCaptionFormat({
    required this.format,
    required this.contentType,
  });

  final String format;
  final String? contentType;
}

List<vp.Caption> _parseCaptions(String raw) {
  final captions = <vp.Caption>[];
  var normalized = raw
      .replaceFirst('\ufeff', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  // Some plain-text subtitle endpoints return escaped newlines rather than
  // actual line breaks. Decode that transport detail before parsing cues.
  if (!normalized.contains('\n') && normalized.contains(r'\n')) {
    normalized = normalized
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\n', '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
  }
  final blocks = normalized.split(RegExp(r'\n\s*\n'));
  for (final block in blocks) {
    final lines = block.split('\n');
    final timingIndex = lines.indexWhere((line) => line.contains('-->'));
    if (timingIndex < 0 || timingIndex + 1 >= lines.length) continue;
    final times = lines[timingIndex].split('-->');
    if (times.length != 2) continue;
    final start = _captionTime(times[0]);
    final end = _captionTime(times[1].trim().split(RegExp(r'\s+')).first);
    final text = lines.sublist(timingIndex + 1).join('\n').trim();
    if (start == null || end == null || end <= start || text.isEmpty) continue;
    captions.add(
      vp.Caption(
        number: captions.length + 1,
        start: start,
        end: end,
        text: text,
      ),
    );
  }
  return captions.isNotEmpty ? captions : _parseAssCaptions(raw);
}

List<vp.Caption> _parseAssCaptions(String raw) {
  final captions = <vp.Caption>[];
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    if (!line.startsWith('Dialogue:')) continue;
    final fields = line.substring('Dialogue:'.length).split(',');
    if (fields.length < 10) continue;
    final start = _assCaptionTime(fields[1]);
    final end = _assCaptionTime(fields[2]);
    final text = fields
        .sublist(9)
        .join(',')
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\n', '\n')
        .trim();
    if (start == null || end == null || end <= start || text.isEmpty) continue;
    captions.add(
      vp.Caption(
        number: captions.length + 1,
        start: start,
        end: end,
        text: text,
      ),
    );
  }
  return captions;
}

String _captionContentFormat(String raw, String? contentType) {
  final content = raw.trimLeft();
  if (content.startsWith('WEBVTT')) return 'vtt';
  if (content.startsWith('#EXTM3U')) return 'hls-playlist';
  if (RegExp(
    r'^\[Script Info\]|^Dialogue:',
    multiLine: true,
  ).hasMatch(content)) {
    return 'ass';
  }
  if (RegExp(
    r'<(?:tt:)?tt\b|<tt:p\b',
    caseSensitive: false,
  ).hasMatch(content)) {
    return 'ttml';
  }
  if (contentType == 'application/x-subrip' ||
      contentType == 'application/srt' ||
      contentType == 'text/srt') {
    return 'srt';
  }
  if (content.contains('-->')) return 'timed-text';
  return contentType ?? 'unknown';
}

Duration? _captionTime(String raw) {
  final numeric = RegExp(r'^\s*(\d+(?:[.,]\d+)?)\s*$').firstMatch(raw);
  if (numeric != null) {
    final value = double.tryParse(numeric.group(1)!.replaceAll(',', '.'));
    if (value != null) {
      // Small values are conventionally seconds; large integer values are
      // conventionally milliseconds (both variants occur in plain text feeds).
      final milliseconds = value > 1000
          ? value.round()
          : (value * 1000).round();
      return Duration(milliseconds: milliseconds);
    }
  }
  final match = RegExp(
    r'(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})(?:[.,:](\d{1,3}))?',
  ).firstMatch(raw.trim());
  if (match == null) return null;
  final fraction = match.group(4) ?? '0';
  return Duration(
    hours: int.parse(match.group(1) ?? '0'),
    minutes: int.parse(match.group(2)!),
    seconds: int.parse(match.group(3)!),
    milliseconds: int.parse(fraction.padRight(3, '0').substring(0, 3)),
  );
}

String _timingShape(String? line) {
  if (line == null) return 'none';
  final shape = line.replaceAll(RegExp(r'[^0-9:.,>\-]'), '');
  return shape.isEmpty ? 'unrecognized' : shape;
}

Duration? _assCaptionTime(String raw) {
  final match = RegExp(
    r'^(\d+):(\d{1,2}):(\d{2})[.](\d{1,2})$',
  ).firstMatch(raw.trim());
  if (match == null) return null;
  final fraction = match.group(4)!;
  return Duration(
    hours: int.parse(match.group(1)!),
    minutes: int.parse(match.group(2)!),
    seconds: int.parse(match.group(3)!),
    milliseconds: int.parse(fraction.padRight(3, '0').substring(0, 3)),
  );
}
