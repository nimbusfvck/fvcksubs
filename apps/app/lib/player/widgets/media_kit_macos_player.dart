import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import '../models/app_player_controller.dart';

/// macOS-native player. This file is reached only by the macOS platform
/// builder; its libmpv payload is provided by media_kit_libs_macos_video.
class MediaKitMacosPlayerView extends StatefulWidget {
  const MediaKitMacosPlayerView({
    super.key,
    required this.stream,
    required this.isLive,
    this.onControllerCreated,
    this.onPlaybackReady,
    this.preferredSubtitleLanguage,
  });

  final PlayableStream stream;
  final bool isLive;
  final void Function(Object? controller)? onControllerCreated;
  final void Function(Object? controller)? onPlaybackReady;
  final String? preferredSubtitleLanguage;

  @override
  State<MediaKitMacosPlayerView> createState() =>
      _MediaKitMacosPlayerViewState();
}

class _MediaKitMacosPlayerViewState extends State<MediaKitMacosPlayerView> {
  late final mk.Player _player;
  late final VideoController _video;
  late final _MediaKitControllerAdapter _adapter;
  final GlobalKey<VideoState> _videoKey = GlobalKey();
  PlayerFitMode _fitMode = PlayerFitMode.contain;

  @override
  void initState() {
    super.initState();
    mk.MediaKit.ensureInitialized();
    _player = mk.Player();
    _video = VideoController(_player);
    _adapter = _MediaKitControllerAdapter(
      _player,
      isFullScreen: () => _videoKey.currentState?.isFullscreen() ?? false,
      toggleFullScreen: () async => _videoKey.currentState?.toggleFullscreen(),
      exitFullScreen: () async => _videoKey.currentState?.exitFullscreen(),
      setFit: (mode) {
        if (mounted) setState(() => _fitMode = mode);
      },
    );
    widget.onControllerCreated?.call(_adapter);
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _player.open(
        mk.Media(widget.stream.url, httpHeaders: widget.stream.headers),
      );
      final preferred = widget.preferredSubtitleLanguage;
      if (preferred != null && !widget.isLive) {
        final track = widget.stream.subtitles.cast<SubtitleTrack?>().firstWhere(
          (item) => item?.language.toLowerCase() == preferred.toLowerCase(),
          orElse: () => null,
        );
        if (track != null) await _adapter.setSubtitle(track);
      }
      final audioUrl = widget.stream.audioUrl;
      if (audioUrl != null && audioUrl.isNotEmpty) {
        await _player.setAudioTrack(mk.AudioTrack.uri(audioUrl));
      }
      widget.onPlaybackReady?.call(_adapter);
    } catch (error) {
      _adapter.reportError(error);
    }
  }

  @override
  void dispose() {
    _adapter.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Video(
    key: _videoKey,
    controller: _video,
    fit: _fitMode == PlayerFitMode.contain ? BoxFit.contain : BoxFit.cover,
    // MediaKit moves only the Video widget into its fullscreen route. Use its
    // desktop controls there so pointer input and keyboard focus stay inside
    // that route; the app-owned overlay remains responsible while embedded.
    controls: (state) => state.isFullscreen()
        ? MaterialDesktopVideoControls(state)
        : const SizedBox.shrink(),
    wakelock: false,
  );
}

class _MediaKitControllerAdapter implements AppPlayerController {
  _MediaKitControllerAdapter(
    this._player, {
    required bool Function() isFullScreen,
    required Future<void> Function() toggleFullScreen,
    required Future<void> Function() exitFullScreen,
    required void Function(PlayerFitMode mode) setFit,
  }) : _isFullScreen = isFullScreen,
       _toggleFullScreen = toggleFullScreen,
       _exitFullScreen = exitFullScreen,
       _setFit = setFit {
    _subscriptions = [
      _player.stream.position.listen((value) => _update(position: value)),
      _player.stream.duration.listen((value) => _update(duration: value)),
      _player.stream.buffer.listen((value) => _update(bufferedPosition: value)),
      _player.stream.playing.listen((value) => _update(isPlaying: value)),
      _player.stream.buffering.listen((value) => _update(isBuffering: value)),
      _player.stream.completed
          .where((value) => value)
          .listen(
            (_) =>
                _events.add(const AppPlayerEvent(AppPlayerEventType.completed)),
          ),
      _player.stream.error.listen(reportError),
    ];
  }

  final mk.Player _player;
  final bool Function() _isFullScreen;
  final Future<void> Function() _toggleFullScreen;
  final Future<void> Function() _exitFullScreen;
  final void Function(PlayerFitMode mode) _setFit;
  final ValueNotifier<AppPlayerValue> _value = ValueNotifier(
    const AppPlayerValue(),
  );
  final StreamController<AppPlayerEvent> _events = StreamController.broadcast();
  late final List<StreamSubscription<Object?>> _subscriptions;
  SubtitleTrack? _activeSubtitle;

  @override
  ValueListenable<AppPlayerValue> get value => _value;

  @override
  Stream<AppPlayerEvent> get events => _events.stream;

  @override
  List<AppQualityTrack> get qualityTracks => [
    for (final track in _player.state.tracks.video)
      if ((track.h ?? 0) > 0)
        AppQualityTrack(
          id: track.id,
          height: track.h!,
          bitrate: track.bitrate?.round(),
          platformTrack: track,
        ),
  ];

  @override
  AppQualityTrack? get activeQuality {
    final track = _player.state.track.video;
    if ((track.h ?? 0) <= 0) return null;
    return AppQualityTrack(
      id: track.id,
      height: track.h!,
      bitrate: track.bitrate?.round(),
      platformTrack: track,
    );
  }

  @override
  List<AppAudioTrack> get audioTracks => [
    for (final track in _player.state.tracks.audio)
      if (track.id != 'no' && track.id != 'auto') _audioTrack(track),
  ];

  @override
  AppAudioTrack? get activeAudio {
    final track = _player.state.track.audio;
    return track.id == 'no' || track.id == 'auto' ? null : _audioTrack(track);
  }

  @override
  SubtitleTrack? get activeSubtitle => _activeSubtitle;

  @override
  bool get isFullScreen => _isFullScreen();

  @override
  Future<void> exitFullScreen() => _exitFullScreen();

  @override
  Future<void> toggleFullScreen() => _toggleFullScreen();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

  @override
  Future<void> setQuality(AppQualityTrack? track) => _player.setVideoTrack(
    track == null || track.id == 'auto'
        ? mk.VideoTrack.auto()
        : track.platformTrack! as mk.VideoTrack,
  );

  @override
  Future<void> setAudioTrack(AppAudioTrack track) =>
      _player.setAudioTrack(track.platformTrack! as mk.AudioTrack);

  @override
  Future<void> setFit(PlayerFitMode mode) async => _setFit(mode);

  @override
  Future<void> setSubtitle(SubtitleTrack? track) async {
    _activeSubtitle = track;
    await _player.setSubtitleTrack(
      track == null
          ? mk.SubtitleTrack.no()
          : mk.SubtitleTrack.uri(
              track.url,
              title: track.label,
              language: track.language,
            ),
    );
  }

  AppAudioTrack _audioTrack(mk.AudioTrack track) => AppAudioTrack(
    id: track.id,
    label: track.title ?? track.language ?? 'Audio',
    language: track.language,
    platformTrack: track,
  );

  void _update({
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    bool? isPlaying,
    bool? isBuffering,
  }) {
    final initialized =
        _player.state.duration > Duration.zero ||
        _player.state.position > Duration.zero;
    _value.value = _value.value.copyWith(
      initialized: initialized,
      position: position,
      duration: duration,
      bufferedPosition: bufferedPosition,
      isPlaying: isPlaying,
      isBuffering: isBuffering,
    );
  }

  void reportError(Object error) =>
      _events.add(AppPlayerEvent(AppPlayerEventType.error, error: error));

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _value.dispose();
    unawaited(_events.close());
  }
}
