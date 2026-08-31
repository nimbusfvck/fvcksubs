import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import '../diagnostics/player_diagnostics.dart';
import '../models/app_player_controller.dart';
import '../state/player_wakelock.dart';
import '../state/quality_preference_controller.dart';
import '../state/subtitle_preference_controller.dart';
import 'player_subtitle_style.dart';

@visibleForTesting
bool shouldApplyDeferredSubtitle({
  required bool mounted,
  required int expectedRevision,
  required int currentRevision,
}) => mounted && expectedRevision == currentRevision;

/// The track to select once the stream opens, or `null` to leave whatever
/// libmpv picked for itself.
///
/// An explicit external pick always wins — the viewer chose it for this item.
/// Otherwise the source's own tracks are matched on
/// [subtitleLanguageKey], never on the raw string: a track carries whatever
/// the upstream called the language ("Indonesian", "in", "English (Forced)"),
/// while the preference is stored as a bare subtag, so comparing the two
/// directly misses the track that is actually there.
///
/// Live streams are left alone; their tracks are the channel's own.
@visibleForTesting
SubtitleTrack? preferredSubtitleTrack({
  required List<SubtitleTrack> tracks,
  required bool isLive,
  String? preferredLanguage,
  SubtitleTrack? preferredExternal,
}) {
  if (preferredExternal != null) return preferredExternal;
  if (preferredLanguage == null || isLive) return null;
  final wanted = subtitleLanguageKey(preferredLanguage);
  for (final track in tracks) {
    if (subtitleLanguageKey(track.language) == wanted) return track;
  }
  return null;
}

/// libmpv properties applied on top of media_kit's defaults.
///
/// media_kit configures mpv for on-demand playback: it caches the stream to
/// disk, keeps a large back-buffer, and gives every network request five
/// seconds. On a live broadcast those choices cost a session — a match writes
/// gigabytes of disk cache nobody can seek back into, and a single slow
/// playlist reload burns retries until the demuxer stops feeding.
///
/// What helps an on-demand file can hurt a live one, so the two are tuned
/// apart rather than sharing a single set of "safer" values.
///
/// Values are strings because that is what `NativePlayer.setProperty` takes.
@visibleForTesting
Map<String, String> mpvPlaybackTuning({required bool isLive}) => {
  // Five seconds is tight for a large or slow playlist reload, and an abort
  // costs one of the demuxer's five segment retries.
  'network-timeout': '8',
  // Back to libmpv's own default, which media_kit turns off.
  //
  // Every seek here is absolute, and `hr-seek` lands them on the exact
  // frame asked for by decoding forward from the keyframe before it. With
  // framedrop off those in-between frames are not just decoded but shown,
  // so a seek into a long-GOP encode spends seconds replaying video nobody
  // asked to watch before the picture settles — the wait a browser does not
  // have, because it starts at the keyframe. Dropping them keeps the seek
  // exact and gives the time back.
  'hr-seek-framedrop': 'yes',
  if (isLive) ...{
    // Live providers are always network streams. Do not leave this to mpv's
    // auto detection: a cache gives segment downloads time to catch up before
    // the decoder reaches the moving live edge.
    'cache': 'yes',
    // Nothing seeks back into a live broadcast, so the disk cache is written
    // and never read.
    'cache-on-disk': 'no',
    // media_kit's 32 MiB default is quickly consumed by a high-bitrate live
    // rendition. Keep enough forward packet cache for a short upstream or
    // mobile-network dip without persisting it to disk.
    'demuxer-max-bytes': '${64 * 1024 * 1024}',
    'demuxer-max-back-bytes': '${8 * 1024 * 1024}',
    // A ceiling on the read-ahead, not a target: libmpv reads as far as the
    // playlist lets it, which on a live window is far less than this. Named
    // explicitly because the default has moved between libmpv releases, and
    // an old build's 10-second ceiling is inside the range live jitter needs.
    'cache-secs': '45',
    // Wait for a segment or two before the first frame and after an underrun,
    // and no more than that.
    //
    // This is a floor on the *rebuffer*, and a live playlist is a short
    // sliding window — Kora publishes six two-second segments, twelve
    // seconds in total. Asking for more cushion than the window holds cannot
    // be answered by downloading faster: the data does not exist yet, so mpv
    // sits frozen collecting it at one second per second. Every value here
    // must stay well under both the window and
    // [PlaybackStallDetector.threshold], or an ordinary rebuffer outlives the
    // stall timer and the app re-resolves a source that was about to resume.
    'cache-pause-initial': 'yes',
    'cache-pause-wait': '3',
  },
};

/// FFmpeg demuxer options merged into media_kit's own `demuxer-lavf-o` for a
/// live stream.
///
/// Applied with mpv's `change-list ... add` rather than by setting the
/// property: media_kit puts the protocol whitelist and the segment retry
/// count in that same list, and writing it wholesale would drop them.
@visibleForTesting
const Map<String, String> liveDemuxerLavfOptions = {
  // How far back from the live edge playback joins, in segments.
  //
  // FFmpeg's default of -3 is the cushion for the whole session: the demuxer
  // reads to the edge and stays there, so the distance playback started at is
  // the distance it keeps. Three of Kora's two-second segments is six
  // seconds, and one slow segment spends all of it. Joining five segments
  // back roughly doubles the cushion at the cost of a few seconds of latency
  // nothing in a live broadcast can seek past anyway. FFmpeg clamps this to
  // the segments the playlist actually lists, so a short window is not an
  // error.
  'live_start_index': '-5',
};

/// How long a deferred subtitle waits for the decoder to report a picture
/// before it is given up on.
///
/// The wait exists because applying a subtitle before libmpv knows the video
/// size leaves it selected with nothing drawn. Eight seconds was enough for a
/// short playlist, but a long VOD playlist — FlyStream ships one entry per
/// segment for the whole film, behind a fresh HTTPS connection per segment —
/// routinely spends longer than that before the first frame, and the viewer's
/// remembered subtitle was being dropped on exactly the sources that need it.
/// Nothing is held open by waiting: the apply is guarded by the widget still
/// being mounted and by the selection revision.
@visibleForTesting
const Duration videoParamsWait = Duration(seconds: 30);

/// FFmpeg demuxer options merged into media_kit's own `demuxer-lavf-o` for an
/// on-demand HLS stream.
///
/// Applied the same way as [liveDemuxerLavfOptions], and only to HLS: these
/// are options of FFmpeg's HLS demuxer, and handing them to any other demuxer
/// only earns a warning in the log.
@visibleForTesting
const Map<String, String> vodHlsDemuxerLavfOptions = {
  // Give every segment its own connection instead of reusing one.
  //
  // Seeking past the buffered range abandons the segment being read and asks
  // for a distant one. On a kept-alive connection that leaves an undrained
  // response body in front of the new request, and the read that follows
  // waits on data that will never come — playback freezes at the seek target
  // while FFmpeg burns `network-timeout` and its five segment retries.
  // Playing forward never trips it, which is why only seeks out of the cache
  // hang.
  //
  // The cost is a handshake per segment. Providers like FlyStream sign every
  // segment URL separately anyway, so the connection was buying less than it
  // looks. Live keeps persistence: it reads sequentially, never seeks far,
  // and pays that handshake at the live edge where there is no slack.
  'http_persistent': '0',
};

/// libmpv options applied to an on-demand HLS stream before it is opened.
@visibleForTesting
const Map<String, String> vodHlsMpvOptions = {
  // Open on the smallest rendition, never the largest.
  //
  // libmpv's own default is `max`, so a playlist offering 4K opens on 4K and
  // spends the first seconds decoding it — and downloading it — before
  // [_selectPreferredVariant] re-opens on the one actually wanted. Starting
  // at the bottom makes that opening moment cheap, and nothing stays there:
  // the re-open follows as soon as the track list arrives.
  'hls-bitrate': 'min',
};

/// The rendition ceiling for a viewer who has not chosen one.
///
/// Left to itself libmpv opens the largest rendition on offer, which on a
/// phone means downloading and decoding 4K nobody asked for and cannot see.
/// A viewer who wants more says so — in Settings, or in the player's own
/// quality picker, both of which override this.
@visibleForTesting
const int defaultStartupMaxHeight = 720;

/// The ceiling to open an on-demand stream at.
///
/// A live stream is left alone: its renditions are the channel's own, and it
/// has no picker to correct a choice made for the viewer.
@visibleForTesting
int? startupMaxHeight({required int? preference, required bool isLive}) =>
    isLive ? preference : preference ?? defaultStartupMaxHeight;

/// The `hls-bitrate` that makes libmpv open [track] instead of whatever it
/// would have chosen, or `null` when the choice cannot be expressed.
///
/// libmpv picks the highest variant whose bitrate does not exceed the value
/// given, so the wanted variant's own bitrate names it. A playlist that
/// declares no bitrate cannot be addressed this way, and a variant already
/// playing needs no addressing at all.
@visibleForTesting
int? hlsBitrateForVariant({
  required AppQualityTrack? wanted,
  required AppQualityTrack? active,
}) {
  if (wanted == null) return null;
  final bitrate = wanted.bitrate;
  if (bitrate == null || bitrate <= 0) return null;
  if (active != null && active.id == wanted.id) return null;
  return bitrate;
}

/// Whether [target] is inside the range libmpv has already downloaded.
///
/// The back edge is the current position: libmpv keeps a back-buffer, but how
/// much of it survives is not reported, so only the forward range is claimed.
@visibleForTesting
bool isWithinBuffer(Duration target, AppPlayerValue value) =>
    target >= value.position && target <= value.bufferedPosition;

@visibleForTesting
Duration mediaKitBufferedAhead({
  required Duration position,
  required Duration bufferedPosition,
}) => bufferedPosition > position ? bufferedPosition - position : Duration.zero;

/// libmpv-backed player, used on macOS and iOS.
///
/// iOS is here rather than on BetterPlayer because AVPlayer trusts a
/// segment's declared MIME type, and several live providers serve MPEG-TS
/// mislabelled as `text/plain` or `application/zstd`. libmpv sniffs the
/// container instead, so those streams play. The native payload comes from
/// media_kit_libs_macos_video and media_kit_libs_ios_video.
class MediaKitPlayerView extends StatefulWidget {
  const MediaKitPlayerView({
    super.key,
    required this.stream,
    required this.isLive,
    this.onControllerCreated,
    this.onPlaybackReady,
    this.preferredSubtitleLanguage,
    this.preferredQualityMaxHeight,
    this.preferredExternalSubtitle,
    this.subtitleAppearance,
    this.muted = false,
    this.looping = false,
    this.playing = true,
    this.preview = false,
    this.wakelock,
    this.transparentBackground = false,
    this.fit = BoxFit.contain,
  });

  final PlayableStream stream;
  final bool isLive;
  final void Function(Object? controller)? onControllerCreated;
  final void Function(Object? controller)? onPlaybackReady;
  final String? preferredSubtitleLanguage;

  final int? preferredQualityMaxHeight;
  final SubtitleTrack? preferredExternalSubtitle;
  final SubtitleAppearance? subtitleAppearance;

  /// Starts playback without audio, useful for autoplay previews.
  final bool muted;

  /// Repeats the stream instead of stopping at its end.
  final bool looping;

  /// Controls playback without destroying the native player.
  final bool playing;

  /// Uses a small buffer and skips disk caching for a short embedded
  /// preview.
  final bool preview;

  /// Whether to keep the screen awake while this player exists. Defaults to
  /// `!preview` — a decorative auto-loop preview doesn't hold the screen on,
  /// but a caller whose preview *is* the primary thing being watched (e.g.
  /// Shorts) can opt in explicitly.
  final bool? wakelock;

  /// Lets a `fit: contain` letterbox show whatever is painted behind this
  /// widget instead of opaque black bars — for a caller that layers its own
  /// backdrop underneath (e.g. Shorts' blurred poster).
  final bool transparentBackground;

  /// Initial fill mode. [BoxFit.cover] and anything else besides
  /// [BoxFit.contain] map to [PlayerFitMode.cover].
  final BoxFit fit;

  @override
  State<MediaKitPlayerView> createState() => _MediaKitPlayerViewState();
}

class _MediaKitPlayerViewState extends State<MediaKitPlayerView>
    with WidgetsBindingObserver {
  late final mk.Player _player;
  late final VideoController _video;
  late final _MediaKitControllerAdapter _adapter;
  final GlobalKey<VideoState> _videoKey = GlobalKey();
  late PlayerFitMode _fitMode;
  Timer? _wakelockRefreshTimer;
  PlayerWakelockLease? _wakelock;
  StreamSubscription<mk.Tracks>? _qualityTracksSubscription;
  bool _preferredQualitySelectionDone = false;

  @override
  void initState() {
    super.initState();
    _fitMode = widget.fit == BoxFit.contain
        ? PlayerFitMode.contain
        : PlayerFitMode.cover;
    if (widget.wakelock ?? !widget.preview) {
      WidgetsBinding.instance.addObserver(this);
      _wakelock = PlayerWakelockLease.acquire();
      _wakelockRefreshTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _wakelock?.refresh(),
      );
    }
    mk.MediaKit.ensureInitialized();
    _player = mk.Player();
    _video = VideoController(_player);
    _adapter = _MediaKitControllerAdapter(
      _player,
      audioUrl: widget.stream.audioUrl,
      videoUrl: widget.stream.url,
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

  /// Applies [mpvPlaybackTuning], and on a live stream
  /// [liveDemuxerLavfOptions], before the stream is opened.
  ///
  /// A property mpv does not recognise throws rather than being ignored, so
  /// each is applied on its own: an unknown key costs that one setting, not
  /// the whole tuning pass and not playback.
  Future<void> _applyPlaybackTuning() async {
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) return;
    final tuning = mpvPlaybackTuning(isLive: widget.isLive);
    for (final entry in tuning.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            '[Player] mpv property ${entry.key} rejected: '
            '${redactPlaybackLogText(error)}',
          );
        }
      }
    }
    if (!widget.isLive && widget.stream.format == StreamFormat.hls) {
      for (final entry in vodHlsMpvOptions.entries) {
        try {
          await platform.setProperty(entry.key, entry.value);
        } catch (error) {
          if (kDebugMode) {
            debugPrint(
              '[Player] mpv property ${entry.key} rejected: '
              '${redactPlaybackLogText(error)}',
            );
          }
        }
      }
    }
    final demuxerOptions = widget.isLive
        ? liveDemuxerLavfOptions
        : widget.stream.format == StreamFormat.hls
        ? vodHlsDemuxerLavfOptions
        : const <String, String>{};
    if (demuxerOptions.isEmpty) return;
    for (final entry in demuxerOptions.entries) {
      try {
        await platform.command([
          'change-list',
          'demuxer-lavf-o',
          'add',
          '${entry.key}=${entry.value}',
        ]);
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            '[Player] mpv demuxer option ${entry.key} rejected: '
            '${redactPlaybackLogText(error)}',
          );
        }
      }
    }
    // libmpv answers a bad list edit on its own log rather than to the
    // caller, so read the result back: this is the only place that shows
    // whether the additions landed and media_kit's own entries survived.
    if (kDebugMode) {
      try {
        debugPrint(
          '[Player] demuxer-lavf-o: '
          '${await platform.getProperty('demuxer-lavf-o')}',
        );
      } catch (_) {}
    }
  }

  Future<void> _open() async {
    await _applyPlaybackTuning();
    try {
      await _player.open(
        mk.Media(widget.stream.url, httpHeaders: widget.stream.headers),
        play: widget.playing,
      );
      if (widget.muted) await _player.setVolume(0);
      if (widget.looping) {
        await _player.setPlaylistMode(mk.PlaylistMode.single);
      }
    } catch (error) {
      _adapter.reportError(error);
      return;
    }

    await _selectPreferredVariant();

    final preferredSubtitle = _preferredSubtitle();
    if (preferredSubtitle != null) {
      try {
        await _adapter.setSubtitle(preferredSubtitle);
      } catch (error) {
        // A broken remembered or source subtitle must not turn a playable
        // video into a source failure.
        if (kDebugMode) {
          debugPrint(
            '[Player] subtitle unavailable: '
            '${redactPlaybackLogText(error)}',
          );
        }
      }
    }

    try {
      final audioUrl = widget.stream.audioUrl;
      if (audioUrl != null && audioUrl.isNotEmpty) {
        await _player.setAudioTrack(mk.AudioTrack.uri(audioUrl));
      }
    } catch (error) {
      // A broken external audio track must not turn a playable video into a
      // source failure.
      if (kDebugMode) {
        debugPrint(
          '[Player] audio unavailable: ${redactPlaybackLogText(error)}',
        );
      }
    }
    _watchPreferredQuality();
    unawaited(_logSeekability());
    try {
      widget.onPlaybackReady?.call(_adapter);
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[Player] playback-ready callback failed: '
          '${redactPlaybackLogText(error)}',
        );
      }
    }

    // media_kit's open() only queues the media. Applying an external subtitle
    // before mpv reports video dimensions can leave it selected in state while
    // no cues are rendered. Wait for the decoder, then apply the preference.
    if (preferredSubtitle != null) {
      unawaited(
        _applyPreferredSubtitle(
          preferredSubtitle,
          expectedRevision: _adapter.subtitleSelectionRevision,
        ),
      );
    }
  }

  /// Chooses the rendition the viewer asked for by re-opening the stream on
  /// it, rather than switching to it while it plays.
  ///
  /// An HLS variant is its own playlist with its own read position. Switching
  /// `vid` mid-stream leaves the newly wanted playlist to catch up with
  /// playback on its own, and a later seek has to reconcile positions that
  /// were never together — the demuxer answers by pulling segment after
  /// segment with no picture to show for it. Opening on the variant means
  /// there is only ever one playlist, from the first frame.
  ///
  /// Only for on-demand HLS with a preference set. Anything that cannot be
  /// expressed as a bitrate is left to [_watchPreferredQuality] and its
  /// mid-stream switch, which is worse but still better than ignoring the
  /// preference.
  Future<void> _selectPreferredVariant() async {
    final maxHeight = _startupMaxHeight;
    if (maxHeight == null || widget.stream.format != StreamFormat.hls) return;
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) return;
    // Only what libmpv already knows. A source can take twenty seconds to
    // report a rendition list, and blocking the rest of the open on it costs
    // the viewer that wait for nothing: [vodHlsMpvOptions] has already kept
    // the opening rendition off the largest one, and _watchPreferredQuality
    // still raises it to the ceiling when the list finally lands.
    if (_adapter.qualityTracks.isEmpty) return;
    try {
      final bitrate = hlsBitrateForVariant(
        wanted: preferredQualityTrack(
          tracks: _adapter.qualityTracks,
          maxHeight: maxHeight,
        ),
        active: _adapter.activeQuality,
      );
      if (bitrate == null) return;
      await platform.setProperty('hls-bitrate', '$bitrate');
      await _player.open(
        mk.Media(widget.stream.url, httpHeaders: widget.stream.headers),
        play: widget.playing,
      );
      // The re-opened stream is already on the wanted rendition, so the
      // watcher must not switch again on top of it.
      _preferredQualitySelectionDone = true;
    } catch (error) {
      // Falling through leaves the mid-stream switch in charge, which is how
      // this worked before.
      if (kDebugMode) {
        debugPrint(
          '[Player] variant selection unavailable: '
          '${redactPlaybackLogText(error)}',
        );
      }
    }
  }

  /// Reports whether libmpv can actually seek this stream.
  ///
  /// FFmpeg's HLS demuxer refuses to seek a playlist that carries neither
  /// `#EXT-X-ENDLIST` nor `#EXT-X-PLAYLIST-TYPE:VOD` — it treats it as live,
  /// however long it is. libmpv answers a seek it cannot delegate by reading
  /// *forward* to the target instead, which on a long film is an unbounded
  /// download that never reaches the position asked for: the picture never
  /// returns and the spinner never stops.
  ///
  /// That failure and an ordinary slow refill look identical from the
  /// outside, and only this property tells them apart. Debug builds only.
  Future<void> _logSeekability() async {
    if (!kDebugMode) return;
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) return;
    try {
      await _player.stream.duration
          .firstWhere((value) => value > Duration.zero)
          .timeout(videoParamsWait);
      debugPrint(
        '[Player] seekable=${await platform.getProperty('seekable')} '
        'partially-seekable='
        '${await platform.getProperty('partially-seekable')} '
        'duration=${_player.state.duration}',
      );
    } catch (_) {
      // Diagnostics only: a stream that never reports a duration has already
      // told the viewer more than this line would.
    }
  }

  int? get _startupMaxHeight => startupMaxHeight(
    preference: widget.preferredQualityMaxHeight,
    isLive: widget.isLive,
  );

  Future<void> _applyPreferredQuality() async {
    final track = preferredQualityTrack(
      tracks: _adapter.qualityTracks,
      maxHeight: _startupMaxHeight,
    );
    if (track == null || track.id == _adapter.activeQuality?.id) return;
    try {
      await _adapter.setQuality(track);
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[Player] preferred quality unavailable: '
          '${redactPlaybackLogText(error)}',
        );
      }
    }
  }

  void _watchPreferredQuality() {
    // The stream was re-opened on the wanted rendition already; switching
    // again is the mid-stream switch this exists to avoid.
    if (_preferredQualitySelectionDone) return;
    if (_startupMaxHeight == null) return;
    if (_adapter.qualityTracks.isNotEmpty) {
      _preferredQualitySelectionDone = true;
      unawaited(_applyPreferredQuality());
      return;
    }
    _qualityTracksSubscription = _player.stream.tracks.listen((_) {
      if (_preferredQualitySelectionDone ||
          _adapter.qualityTracks.isEmpty) {
        return;
      }
      _preferredQualitySelectionDone = true;
      unawaited(_applyPreferredQuality());
      unawaited(_qualityTracksSubscription?.cancel());
      _qualityTracksSubscription = null;
    });
  }

  SubtitleTrack? _preferredSubtitle() => preferredSubtitleTrack(
    tracks: widget.stream.subtitles,
    isLive: widget.isLive,
    preferredLanguage: widget.preferredSubtitleLanguage,
    preferredExternal: widget.preferredExternalSubtitle,
  );

  Future<void> _applyPreferredSubtitle(
    SubtitleTrack track, {
    required int expectedRevision,
  }) async {
    try {
      final params = _player.state.videoParams;
      if ((params.w ?? 0) <= 0 || (params.h ?? 0) <= 0) {
        await _player.stream.videoParams
            .firstWhere((value) => (value.w ?? 0) > 0 && (value.h ?? 0) > 0)
            .timeout(videoParamsWait);
      }
      if (!shouldApplyDeferredSubtitle(
        mounted: mounted,
        expectedRevision: expectedRevision,
        currentRevision: _adapter.subtitleSelectionRevision,
      )) {
        return;
      }
      await _adapter.setSubtitle(track);
    } catch (error) {
      // A broken remembered or source subtitle must not turn a playable video
      // into a source failure.
      if (kDebugMode) {
        debugPrint(
          '[Player] subtitle unavailable: '
          '${redactPlaybackLogText(error)}',
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant MediaKitPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) {
      unawaited(widget.playing ? _player.play() : _player.pause());
    }
    if (oldWidget.muted != widget.muted) {
      unawaited(_player.setVolume(widget.muted ? 0 : 100));
    }
  }

  @override
  void dispose() {
    _wakelockRefreshTimer?.cancel();
    unawaited(_qualityTracksSubscription?.cancel());
    if (widget.wakelock ?? !widget.preview) {
      WidgetsBinding.instance.removeObserver(this);
      _wakelock?.release();
    }
    _adapter.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _wakelock?.refresh();
  }

  @override
  Widget build(BuildContext context) => Video(
    key: _videoKey,
    controller: _video,
    fit: _fitMode == PlayerFitMode.contain ? BoxFit.contain : BoxFit.cover,
    fill: widget.transparentBackground
        ? Colors.transparent
        : const Color(0xFF000000),
    subtitleViewConfiguration: SubtitleViewConfiguration(
      style: widget.subtitleAppearance?.textStyle ?? playerSubtitleTextStyle,
    ),
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
    required String? audioUrl,
    required String videoUrl,
    required bool Function() isFullScreen,
    required Future<void> Function() toggleFullScreen,
    required Future<void> Function() exitFullScreen,
    required void Function(PlayerFitMode mode) setFit,
  }) : _audioUrl = audioUrl,
       _videoUrl = videoUrl,
       _isFullScreen = isFullScreen,
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
      _player.stream.error.listen(_onLogError),
      // libmpv rebuilds its track list on every load and whenever the tracks
      // change, and media_kit does not read back which one is selected — so
      // ask, each time the list moves.
      _player.stream.tracks.listen((_) => unawaited(_refreshSelectedAudioId())),
    ];
  }

  final mk.Player _player;
  final String? _audioUrl;
  final String _videoUrl;
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
  String? _failedSubtitleUrl;
  int _subtitleSelectionRevision = 0;
  String? _selectedAudioId;

  int get subtitleSelectionRevision => _subtitleSelectionRevision;

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
  List<AppAudioTrack> get audioTracks {
    final occurrences = <String, int>{};
    final tracks = _player.state.tracks.audio.where(
      (track) => track.id != 'no' && track.id != 'auto',
    );
    return [
      for (final (index, track) in tracks.indexed)
        _audioTrack(track, index, occurrences),
    ];
  }

  /// The track libmpv is playing, or `null` while that is still unknown.
  ///
  /// media_kit reports `auto` until something selects a track explicitly, and
  /// hands out a new [mk.AudioTrack] object every time the track list is
  /// rebuilt — so neither its value nor its identity can answer this. The
  /// `aid` libmpv actually resolved is read in the background and matched by
  /// id, with media_kit's own value standing in until the first reading
  /// lands.
  @override
  AppAudioTrack? get activeAudio {
    final tracks = audioTracks;
    final selected = audioTrackByNativeId(tracks, _selectedAudioId);
    if (selected != null) return selected;
    final track = _player.state.track.audio;
    if (track.id == 'no' || track.id == 'auto') return null;
    return audioTrackByNativeId(tracks, track.id);
  }

  Future<void> _refreshSelectedAudioId() async {
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) return;
    try {
      final aid = (await platform.getProperty('aid')).trim();
      // `auto` is libmpv still deciding, and `no` only appears while audio is
      // off. Neither replaces a selection already known.
      if (aid.isEmpty || aid == 'auto' || aid == 'no') return;
      _selectedAudioId = aid;
    } catch (_) {
      // Reading a property is best effort: without it the picker falls back
      // to media_kit's own value rather than failing.
    }
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

  /// Seeks, asking libmpv for frame accuracy only where it is cheap.
  ///
  /// `hr-seek` makes libmpv land on the exact frame requested by decoding
  /// forward from wherever the demuxer put it. Inside the buffered range that
  /// costs nothing — the packets are already here. Outside it, every one of
  /// those in-between frames has to be *downloaded* first, and if FFmpeg's
  /// HLS seek lands short (its timeline comes from segment durations, which a
  /// provider's own timestamps need not agree with), the distance to make up
  /// grows with the size of the jump. That is a seek that fetches segment
  /// after segment and never arrives.
  ///
  /// A jump out of the buffer takes the demuxer's own landing point instead —
  /// the nearest keyframe, a second or two off at worst, which is what a
  /// browser gives too. Short seeks and skip-intro keep their precision.
  @override
  Future<void> seekTo(Duration position) async {
    await _setSeekPrecision(precise: isWithinBuffer(position, _value.value));
    await _player.seek(position);
  }

  Future<void> _setSeekPrecision({required bool precise}) async {
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) return;
    try {
      await platform.setProperty('hr-seek', precise ? 'yes' : 'no');
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[Player] hr-seek rejected: ${redactPlaybackLogText(error)}',
        );
      }
    }
  }

  @override
  Future<void> setQuality(AppQualityTrack? track) => _player.setVideoTrack(
    track == null || track.id == 'auto'
        ? mk.VideoTrack.auto()
        : track.platformTrack! as mk.VideoTrack,
  );

  @override
  Future<void> setAudioTrack(AppAudioTrack track) async {
    // Recorded before the switch so the picker marks the viewer's choice
    // immediately, rather than after libmpv has finished re-buffering it.
    _selectedAudioId = track.nativeId;
    await _player.setAudioTrack(track.platformTrack! as mk.AudioTrack);
    await _refreshSelectedAudioId();
  }

  @override
  Future<void> setFit(PlayerFitMode mode) async => _setFit(mode);

  @override
  Future<void> setViewportAspectRatio(double ratio) async {}

  @override
  Future<void> setSubtitle(SubtitleTrack? track) async {
    _subtitleSelectionRevision++;
    _failedSubtitleUrl = null;
    _activeSubtitle = track;
    try {
      await _player.setSubtitleTrack(
        track == null
            ? mk.SubtitleTrack.no()
            : mk.SubtitleTrack.uri(
                track.url,
                title: track.label,
                language: track.language,
              ),
      );
    } catch (_) {
      if (identical(_activeSubtitle, track)) _activeSubtitle = null;
      _failedSubtitleUrl = track?.url;
      rethrow;
    }
  }

  AppAudioTrack _audioTrack(
    mk.AudioTrack track,
    int index,
    Map<String, int> occurrences,
  ) {
    final details = _audioTrackDetails(track);
    final base = audioTrackBaseId(
      id: track.id,
      label: track.title,
      language: track.language,
      details: details,
    );
    final occurrence = occurrences[base] ?? 0;
    occurrences[base] = occurrence + 1;
    return AppAudioTrack(
      id: uniqueAudioTrackId(base: base, occurrence: occurrence, index: index),
      label: audioTrackLabel(
        label: track.title,
        language: track.language,
        details: details,
      ),
      language: track.language,
      details: details,
      nativeId: track.id,
      platformTrack: track,
    );
  }

  String? _audioTrackDetails(mk.AudioTrack track) {
    final values = <String>[];
    final codec = track.codec?.trim();
    if (codec != null && codec.isNotEmpty) values.add(codec.toUpperCase());
    final channels = track.channels?.trim();
    if (channels != null && channels.isNotEmpty) {
      values.add(channels);
    } else if (track.channelscount != null && track.channelscount! > 0) {
      values.add('${track.channelscount}ch');
    }
    return values.isEmpty ? null : values.join(' · ');
  }

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

  /// mpv error *log lines*, which are not the same as playback failing —
  /// see [isFatalPlayerError]. A non-fatal one is kept for debugging rather
  /// than shown, so working video is never replaced by a failure screen.
  void _onLogError(Object error) {
    if (!isFatalPlayerError(
      error,
      playbackStarted: _value.value.initialized,
      subtitleUrl: _activeSubtitle?.url ?? _failedSubtitleUrl,
      audioUrl: _audioUrl,
      videoUrl: _videoUrl,
    )) {
      if (kDebugMode) {
        debugPrint('[Player] non-fatal: ${redactPlaybackLogText(error)}');
      }
      return;
    }
    reportError(error);
  }

  /// Reports a failure that really did stop playback — an `open` that threw,
  /// or an mpv error line that [isFatalPlayerError] judged fatal.
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
