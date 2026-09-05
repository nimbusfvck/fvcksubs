import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import '../diagnostics/player_diagnostics.dart';
import '../mappers/hls_playlists.dart';
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

/// How long a playlist is given before playback goes ahead without it.
@visibleForTesting
const Duration playlistFetchTimeout = Duration(seconds: 8);

/// Disabled while Darwin playback is verified against the newer libmpv payload.
///
/// The cut path re-opens fMP4 HLS to work around a seek stall, but it changes
/// the native media timeline and is the only app-owned path that can disturb
/// a selected external subtitle when audio tracks change. Re-enable only
/// after a clean-process test proves both seeking and audio/subtitle switching.
final bool hlsCutWorkaroundEnabled = false;

/// How much to add to what libmpv reports so the app keeps speaking in film
/// time after a cut playlist is opened.
///
/// A cut is a file in its own right, and libmpv may describe it either way:
/// as a stream starting at zero that runs for what remains, or — where the
/// fragments carry absolute timestamps, as FlyStream's do — as one that
/// already knows where it sits. The duration it reports says which: a cut
/// describes the runtime that is left, the whole film describes all of it.
@visibleForTesting
Duration resolveSliceOffset({
  required Duration reportedDuration,
  required Duration sliceStart,
  required Duration sliceDuration,
  required Duration fullDuration,
}) {
  if (reportedDuration <= Duration.zero) return sliceStart;
  final asSlice = (reportedDuration - sliceDuration).abs();
  final asWhole = (reportedDuration - fullDuration).abs();
  return asSlice <= asWhole ? sliceStart : Duration.zero;
}

/// The libmpv subtitle delay that maps a cut playlist's clock back onto the
/// original film timeline.
///
/// A cut opened at minute ten reports its position from zero, while an
/// external subtitle file still counts from the beginning of the film. The
/// inverse cut offset makes both clocks describe the same cue.
@visibleForTesting
double subtitleDelaySeconds(Duration timelineOffset) =>
    -timelineOffset.inMilliseconds / 1000;

/// Whether the audio picker must describe a locally cut HLS master.
///
/// Before any cut, libmpv's tracks still belong to the provider's original
/// master, so selecting one can keep the current media and subtitle clock.
/// A cut carries just one audio rendition, so its picker needs the saved
/// provider ladder instead.
@visibleForTesting
bool usesSliceAudioTracks({
  required bool sliceIsActive,
  required bool hasSliceTracks,
}) => sliceIsActive && hasSliceTracks;

/// Decodes an HLS playlist strictly, rejecting a media segment or an upstream
/// error page that only happened to arrive at a playlist URL.
///
/// Playlist inspection is optional: libmpv owns normal playback, and a
/// malformed response must only disable the cut workaround rather than throw
/// from its background prefetch.
@visibleForTesting
String? decodeHlsPlaylistBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
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

/// libmpv-backed player for Apple live playback, DASH VOD, and sources with a
/// separate external audio URL.
///
/// Live providers can mislabel MPEG-TS as `text/plain` or `application/zstd`,
/// so libmpv's container sniffing keeps those streams playable. It also owns
/// the external-audio composition that AVFoundation cannot provide here. The
/// native payload comes from media_kit_libs_macos_video and
/// media_kit_libs_ios_video.
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
  HlsMaster? _master;
  HlsVariant? _cutVariant;
  HlsAudioRendition? _cutAudio;
  HlsMediaPlaylist? _videoPlaylist;
  HlsMediaPlaylist? _audioPlaylist;
  int? _variantHeight;
  bool _playlistsResolved = false;
  int _sliceRevision = 0;
  final List<File> _sliceFiles = [];

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
    if (hlsCutWorkaroundEnabled) {
      _adapter
        ..sliceSeek = _sliceSeekTo
        ..sliceSelectAudio = _selectCutAudio
        ..sliceSelectQuality = _selectCutQuality;
    }
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
    if (hlsCutWorkaroundEnabled) {
      // Read ahead of the first jump: the pickers should describe the film
      // from the start, not only once a cut has replaced libmpv's track list.
      unawaited(_ensurePlaylists());
    }
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

  Future<bool> _sliceSeekTo(Duration target) => _cutAt(target);

  /// Re-opens the film at [target], optionally on another rendition or
  /// another audio track.
  ///
  /// Seeking, changing quality and changing audio all arrive here: on this
  /// packaging every one of them is a seek as far as FFmpeg is concerned, and
  /// a cut is how none of them has to be one.
  ///
  /// Answers `false` for everything this cannot serve — a live stream, a
  /// source that is not HLS, a playlist that cannot be read, packaging that
  /// seeks perfectly well — and for any failure along the way, so the worst
  /// it can do is hand the seek back to libmpv exactly as before.
  Future<bool> _cutAt(
    Duration target, {
    HlsVariant? variant,
    HlsAudioRendition? audio,
  }) async {
    if (widget.isLive || widget.stream.format != StreamFormat.hls) return false;
    try {
      await _ensurePlaylists();
      if (variant != null && !await _useVariant(variant)) return false;
      if (audio != null && !await _useAudio(audio)) return false;
      final video = _videoPlaylist;
      // Only fMP4 goes down this path: it is the packaging measured to hang,
      // and every other kind still seeks the ordinary way.
      if (video == null || !video.isFragmentedMp4 || !mounted) return false;

      final index = video.segmentIndexAt(target);
      final start = video.startOf(index);
      final videoCut = await _writeSlice(video.sliceFrom(index), 'video');
      final audioPlaylist = _audioPlaylist;
      // Cut the audio at the video's own starting moment rather than at the
      // target, so the two begin as close together as their segment
      // boundaries allow.
      final audioCut = audioPlaylist == null
          ? null
          : await _writeSlice(
              audioPlaylist.sliceFrom(audioPlaylist.segmentIndexAt(start)),
              'audio',
            );
      // Both cuts are named from one master, so FFmpeg keeps them in a single
      // demuxer and lines them up by the timestamps inside the segments.
      // Attaching the audio from outside instead makes libmpv treat it as a
      // stream of its own starting at zero, and the two boundaries are
      // seconds apart.
      final master = await _writeSlice(
        hlsSliceMaster(
          videoPlaylist: _basename(videoCut),
          audioPlaylist: audioCut == null ? null : _basename(audioCut),
          height: _variantHeight,
        ),
        'master',
      );
      if (!mounted) return false;

      // Re-opening drops the subtitle libmpv was showing; the viewer chose it
      // for the film, not for this stretch of it.
      final subtitle = _adapter.activeSubtitle;
      _adapter.beginSlice(start: start, fullDuration: video.totalDuration);
      await _player.open(
        mk.Media(master.path, httpHeaders: widget.stream.headers),
        play: true,
      );
      if (subtitle != null) {
        try {
          await _adapter.setSubtitle(subtitle);
        } catch (error) {
          // A subtitle that cannot be re-attached must not undo the audio
          // change or make this otherwise playable cut look like a failure.
          if (kDebugMode) {
            debugPrint(
              '[Player] subtitle unavailable after cut: '
              '${redactPlaybackLogText(error)}',
            );
          }
        }
      }
      _publishSliceSelection();
      if (kDebugMode) {
        debugPrint(
          '[Player] seek by cut: target=$target segment=$index start=$start',
        );
      }
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[Player] seek by cut unavailable: '
          '${redactPlaybackLogText(error)}',
        );
      }
      return false;
    }
  }

  /// Reads the playlists a cut is made from, once per source.
  Future<void> _ensurePlaylists() async {
    if (_playlistsResolved) return;
    _playlistsResolved = true;
    final source = Uri.tryParse(widget.stream.url);
    if (source == null ||
        (!source.isScheme('http') && !source.isScheme('https'))) {
      return;
    }
    final body = await _fetchPlaylist(source);
    if (body == null) return;

    final master = parseHlsMaster(body, base: source);
    if (!master.isMaster) {
      // Already a media playlist: it is its own rendition.
      final media = parseHlsMediaPlaylist(body, base: source);
      if (media.isMediaPlaylist) _videoPlaylist = media;
      return;
    }
    _master = master;
    final variant = master.variantFor(_startupMaxHeight);
    if (variant == null || !await _useVariant(variant)) return;
    final audio = master.audioFor(variant.audioGroup);
    if (audio != null) await _useAudio(audio);
    _publishSliceTracks();
  }

  /// Loads [variant]'s playlist and makes it the one cuts are taken from.
  Future<bool> _useVariant(HlsVariant variant) async {
    if (identical(variant, _cutVariant) && _videoPlaylist != null) return true;
    final body = await _fetchPlaylist(variant.url);
    if (body == null) return false;
    final playlist = parseHlsMediaPlaylist(body, base: variant.url);
    if (!playlist.isMediaPlaylist) return false;
    _videoPlaylist = playlist;
    _variantHeight = variant.height;
    _cutVariant = variant;
    return true;
  }

  Future<bool> _useAudio(HlsAudioRendition rendition) async {
    if (identical(rendition, _cutAudio) && _audioPlaylist != null) return true;
    final body = await _fetchPlaylist(rendition.url);
    if (body == null) return false;
    final playlist = parseHlsMediaPlaylist(body, base: rendition.url);
    if (!playlist.isMediaPlaylist) return false;
    _audioPlaylist = playlist;
    _cutAudio = rendition;
    return true;
  }

  /// Hands the pickers the ladder the provider actually offers.
  ///
  /// Only where cuts are in play. Anywhere else libmpv's own track list is
  /// the truthful one, and switching goes through libmpv as it always has.
  void _publishSliceTracks() {
    final master = _master;
    if (master == null || _videoPlaylist?.isFragmentedMp4 != true || !mounted) {
      return;
    }
    _adapter
      ..sliceQualityTracks = [
        for (final variant in master.variants)
          if ((variant.height ?? 0) > 0)
            AppQualityTrack(
              id: 'variant:${variant.height}',
              height: variant.height!,
              width: variant.width,
              platformTrack: variant,
            ),
      ]
      ..sliceAudioTracks = [
        for (final (index, rendition) in master.audio.indexed)
          AppAudioTrack(
            id: 'rendition:$index',
            label: rendition.name ?? 'Audio ${index + 1}',
            language: rendition.language,
            nativeId: 'rendition:$index',
            platformTrack: rendition,
          ),
      ];
    _publishSliceSelection();
  }

  void _publishSliceSelection() {
    AppQualityTrack? quality;
    for (final track in _adapter.sliceQualityTracks) {
      if (identical(track.platformTrack, _cutVariant)) quality = track;
    }
    AppAudioTrack? audio;
    for (final track in _adapter.sliceAudioTracks) {
      if (identical(track.platformTrack, _cutAudio)) audio = track;
    }
    _adapter
      ..sliceActiveQuality = quality
      ..sliceActiveAudio = audio;
  }

  Future<bool> _selectCutAudio(AppAudioTrack track) {
    // The original master has every audio track already. Re-opening it for a
    // simple selection changes the clock that an external subtitle follows.
    if (!_adapter.sliceIsActive) return Future.value(false);
    final rendition = track.platformTrack;
    if (rendition is! HlsAudioRendition) return Future.value(false);
    return _cutAt(_adapter.value.value.position, audio: rendition);
  }

  Future<bool> _selectCutQuality(AppQualityTrack? track) {
    final master = _master;
    if (master == null) return Future.value(false);
    final chosen = track?.platformTrack;
    // Auto arrives as a placeholder rather than a rendition: it means the
    // ceiling gets to choose again.
    final variant = chosen is HlsVariant
        ? chosen
        : master.variantFor(_startupMaxHeight);
    if (variant == null) return Future.value(false);
    return _cutAt(_adapter.value.value.position, variant: variant);
  }

  Future<String?> _fetchPlaylist(Uri url) async {
    final client = HttpClient()..connectionTimeout = playlistFetchTimeout;
    try {
      final request = await client.getUrl(url).timeout(playlistFetchTimeout);
      widget.stream.headers.forEach(request.headers.set);
      final response = await request.close().timeout(playlistFetchTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final bytes = await response
          .fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (buffer, chunk) => buffer..add(chunk),
          )
          .timeout(playlistFetchTimeout);
      return decodeHlsPlaylistBytes(bytes.takeBytes());
    } catch (error) {
      // Playlist inspection only supports the optional cut workaround. The
      // original URL stays with libmpv, which may still play it normally.
      if (kDebugMode) {
        debugPrint(
          '[Player] HLS playlist unavailable: ${redactPlaybackLogText(error)}',
        );
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  String _basename(File file) => file.uri.pathSegments.last;

  /// Writes a cut where libmpv can open it, and remembers it for cleanup.
  Future<File> _writeSlice(String body, String kind) async {
    final file = File(
      '${Directory.systemTemp.path}/fvcksubs-$kind-'
      '${identityHashCode(this)}-${_sliceRevision++}.m3u8',
    );
    await file.writeAsString(body, flush: true);
    _sliceFiles.add(file);
    return file;
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
      // Which libmpv is actually loaded, and which FFmpeg came with it. The
      // seek that hangs lives in FFmpeg's HLS demuxer, not in the decoder.
      debugPrint(
        '[Player] mpv=${await platform.getProperty('mpv-version')} '
        'ffmpeg=${await platform.getProperty('ffmpeg-version')}',
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
      if (_preferredQualitySelectionDone || _adapter.qualityTracks.isEmpty) {
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
    for (final file in _sliceFiles) {
      unawaited(file.delete().catchError((_) => file));
    }
    _sliceFiles.clear();
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
      // The app preference is already expressed in logical pixels. Do not
      // apply media_kit's viewport-area scaler on top of it.
      textScaler: TextScaler.noScaling,
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

/// A cut being opened, until libmpv says how it reads it.
class _PendingSlice {
  const _PendingSlice({
    required this.start,
    required this.sliceDuration,
    required this.fullDuration,
  });

  final Duration start;
  final Duration sliceDuration;
  final Duration fullDuration;
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
  Duration _timelineOffset = Duration.zero;
  Duration? _fullDuration;
  _PendingSlice? _pendingSlice;

  /// Seeks by re-opening the stream at the moment wanted, for packaging the
  /// bundled FFmpeg cannot seek. Answers `false` to leave the seek alone.
  Future<bool> Function(Duration target)? sliceSeek;

  /// What the provider's own master offers, once it has been read.
  ///
  /// A cut names one rendition and one audio track, so libmpv's track list
  /// describes the cut rather than the film — the pickers would lose every
  /// choice the viewer had before the first jump. These stand in for it.
  List<AppQualityTrack> sliceQualityTracks = const [];
  List<AppAudioTrack> sliceAudioTracks = const [];
  AppQualityTrack? sliceActiveQuality;
  AppAudioTrack? sliceActiveAudio;
  bool sliceIsActive = false;

  /// Switches by re-opening at the current moment rather than by moving a
  /// track inside the demuxer, which is a seek by another name — and the
  /// seek this whole path exists to avoid.
  Future<bool> Function(AppAudioTrack track)? sliceSelectAudio;
  Future<bool> Function(AppQualityTrack? track)? sliceSelectQuality;

  /// Announces that a cut beginning at [start] is being opened.
  ///
  /// The offset is provisional until libmpv reports a duration; only then is
  /// it clear whether it is describing the cut or the whole film.
  void beginSlice({required Duration start, required Duration fullDuration}) {
    sliceIsActive = true;
    _timelineOffset = start;
    _fullDuration = fullDuration;
    _pendingSlice = _PendingSlice(
      start: start,
      sliceDuration: fullDuration - start,
      fullDuration: fullDuration,
    );
  }

  /// Moves subtitle timing by as much as the cut moved the clock.
  ///
  /// Every subtitle here is a file libmpv loads beside the video, and its
  /// times are counted from the start of the film. A cut restarts libmpv's
  /// own clock at the moment it begins, so a line written for minute ten
  /// would wait ten minutes into the cut to appear. What the position gains
  /// as an offset, the subtitles owe back as a delay.
  Future<void> _applySubtitleDelay() async {
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) return;
    final seconds = subtitleDelaySeconds(_timelineOffset);
    try {
      await platform.setProperty('sub-delay', '$seconds');
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[Player] sub-delay rejected: ${redactPlaybackLogText(error)}',
        );
      }
    }
  }

  int get subtitleSelectionRevision => _subtitleSelectionRevision;

  @override
  ValueListenable<AppPlayerValue> get value => _value;

  @override
  Stream<AppPlayerEvent> get events => _events.stream;

  @override
  List<AppQualityTrack> get qualityTracks =>
      sliceQualityTracks.isNotEmpty ? sliceQualityTracks : _mpvQualityTracks;

  List<AppQualityTrack> get _mpvQualityTracks => [
    for (final track in _player.state.tracks.video)
      if ((track.h ?? 0) > 0)
        AppQualityTrack(
          id: track.id,
          height: track.h!,
          width: track.w,
          bitrate: track.bitrate?.round(),
          platformTrack: track,
        ),
  ];

  @override
  AppQualityTrack? get activeQuality {
    if (sliceQualityTracks.isNotEmpty) return sliceActiveQuality;
    final track = _player.state.track.video;
    if ((track.h ?? 0) <= 0) return null;
    return AppQualityTrack(
      id: track.id,
      height: track.h!,
      width: track.w,
      bitrate: track.bitrate?.round(),
      platformTrack: track,
    );
  }

  @override
  List<AppAudioTrack> get audioTracks {
    if (usesSliceAudioTracks(
      sliceIsActive: sliceIsActive,
      hasSliceTracks: sliceAudioTracks.isNotEmpty,
    )) {
      return sliceAudioTracks;
    }
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
    if (usesSliceAudioTracks(
      sliceIsActive: sliceIsActive,
      hasSliceTracks: sliceAudioTracks.isNotEmpty,
    )) {
      return sliceActiveAudio;
    }
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
    final slice = sliceSeek;
    final buffered = isWithinBuffer(position, _value.value);
    // Only a jump out of what is already here is worth re-opening for, and
    // only that jump is the one libmpv cannot make on this packaging.
    if (slice != null && !buffered && await slice(position)) return;
    await _setSeekPrecision(precise: buffered);
    await _player.seek(position - _timelineOffset);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) => _player.setRate(speed);

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
  Future<void> setQuality(AppQualityTrack? track) async {
    final select = sliceSelectQuality;
    if (select != null && await select(track)) return;
    await _setVideoTrack(track);
  }

  Future<void> _setVideoTrack(AppQualityTrack? track) => _player.setVideoTrack(
    track == null || track.id == 'auto'
        ? mk.VideoTrack.auto()
        : track.platformTrack! as mk.VideoTrack,
  );

  @override
  Future<void> setAudioTrack(AppAudioTrack track) async {
    final select = sliceSelectAudio;
    if (select != null && await select(track)) return;
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
      // Loading a subtitle is asynchronous and a cut has just opened a new
      // libmpv timeline. Apply the offset only after that load completes: an
      // earlier write can be reset by the new media or subtitle track.
      await _applySubtitleDelay();
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
    final pending = _pendingSlice;
    if (pending != null && duration != null && duration > Duration.zero) {
      _timelineOffset = resolveSliceOffset(
        reportedDuration: duration,
        sliceStart: pending.start,
        sliceDuration: pending.sliceDuration,
        fullDuration: pending.fullDuration,
      );
      _pendingSlice = null;
      // The reading that resolved the offset can overturn the provisional
      // one, and the subtitles follow it.
      unawaited(_applySubtitleDelay());
    }
    final offset = _timelineOffset;
    final initialized =
        _player.state.duration > Duration.zero ||
        _player.state.position > Duration.zero;
    _value.value = _value.value.copyWith(
      initialized: initialized,
      position: position == null ? null : position + offset,
      // A cut runs from where it begins to the end; the film it came from is
      // the timeline the rest of the app speaks in.
      duration: _fullDuration ?? duration,
      bufferedPosition: bufferedPosition == null
          ? null
          : bufferedPosition + offset,
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
