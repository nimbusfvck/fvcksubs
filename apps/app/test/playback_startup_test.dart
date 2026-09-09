import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/mappers/startup_stream.dart';
import 'package:fvcksubs_app/player/models/app_player_controller.dart';
import 'package:fvcksubs_app/player/models/playback_start_position.dart';
import 'package:fvcksubs_app/player/state/video_player_startup.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:video_player/video_player.dart' as vp;

import 'support/harness.dart';

const _variants = [
  StreamVariant(id: '1080', url: 'https://video/1080', height: 1080),
  StreamVariant(id: '720', url: 'https://video/720', height: 720),
  StreamVariant(id: '480', url: 'https://video/480', height: 480),
];
const _stream = PlayableStream(
  url: 'https://video/master',
  variants: _variants,
);

void main() {
  test(
    'selects the startup URL under the cap while retaining all variants',
    () {
      final variant = preferredStartupVariant(_stream, 720);
      final stream = streamForVariant(_stream, variant);
      expect(stream.url, 'https://video/720');
      expect(stream.variants, _variants);
      expect(preferredStartupVariant(_stream, 360)?.height, 480);
      expect(preferredStartupVariant(_stream, null), isNull);
      expect(streamForVariant(_stream, null), same(_stream));
      expect(
        preferredStartupVariant(
          const PlayableStream(url: 'https://video'),
          720,
        ),
        isNull,
      );
    },
  );

  test('variant selection preserves playback data and header precedence', () {
    const stream = PlayableStream(
      url: 'https://video/master',
      headers: {'Referer': 'https://watch'},
      audioUrl: 'https://video/audio',
      subtitles: [SubtitleTrack(language: 'id', url: 'https://video/sub')],
      variants: _variants,
    );
    final inherited = streamForVariant(stream, _variants[1]);
    expect(inherited.headers, stream.headers);
    expect(inherited.audioUrl, stream.audioUrl);
    expect(inherited.subtitles, stream.subtitles);
    expect(inherited.drm, stream.drm);
    final overridden = streamForVariant(
      stream,
      const StreamVariant(
        id: 'custom',
        url: 'https://video/custom',
        format: StreamFormat.hls,
        headers: {'Cookie': 'session'},
      ),
    );
    expect(overridden.headers, {'Cookie': 'session'});
    expect(overridden.format, StreamFormat.hls);
  });

  test('resume guards and exact source switch position remain distinct', () {
    const duration = Duration(minutes: 10);
    expect(
      const PlaybackStartPosition.resume(
        Duration(seconds: 4),
      ).target(duration, isLive: false),
      isNull,
    );
    expect(
      const PlaybackStartPosition.resume(
        Duration(seconds: 580),
      ).target(duration, isLive: false),
      isNull,
    );
    expect(
      const PlaybackStartPosition.resume(
        Duration(minutes: 3),
      ).target(duration, isLive: false),
      const Duration(minutes: 3),
    );
    expect(
      const PlaybackStartPosition.exact(
        Duration(minutes: 11),
      ).target(duration, isLive: false),
      duration,
    );
    expect(
      const PlaybackStartPosition.exact(
        Duration(seconds: 2),
      ).target(duration, isLive: false),
      const Duration(seconds: 2),
    );
    expect(
      const PlaybackStartPosition.resume(
        Duration(minutes: 3),
      ).target(duration, isLive: true),
      isNull,
    );
  });

  test(
    'opens the preferred variant once and waits for resume before play',
    () async {
      final stream = streamForVariant(
        _stream,
        preferredStartupVariant(_stream, 720),
      );
      final player = _NativePlayer(stream.url)..seekGate = Completer<void>();
      final controller = _Controller(player.calls);
      final startup = _startup(
        player,
        controller,
        stream: stream,
        preselected: true,
      );
      final open = startup.open(
        initialized: false,
        looping: false,
        muted: false,
        playing: true,
        isLive: false,
        startPosition: const PlaybackStartPosition.resume(Duration(minutes: 3)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(player.dataSource, 'https://video/720');
      expect(player.calls, [
        'initialize',
        'looping',
        'volume',
        'tracks',
        'seek:180',
      ]);
      player.seekGate!.complete();
      expect(await open, isTrue);
      expect(player.calls.last, 'play');
      expect(player.calls.where((call) => call == 'initialize'), hasLength(1));
      expect(controller.qualityCalls, 0);
    },
  );

  test(
    'native quality selection precedes resume when no URL ladder exists',
    () async {
      final player = _NativePlayer(_stream.url);
      final controller = _Controller(player.calls);
      final startup = _startup(player, controller);
      await startup.open(
        initialized: false,
        looping: false,
        muted: false,
        playing: true,
        isLive: false,
        startPosition: const PlaybackStartPosition.resume(Duration(minutes: 3)),
      );
      expect(player.calls, [
        'initialize',
        'looping',
        'volume',
        'tracks',
        'quality',
        'seek:180',
        'play',
      ]);
    },
  );

  test(
    'does not poll native tracks after metadata is already complete',
    () async {
      final player = _NativePlayer(_stream.url);
      final controller = _Controller(player.calls);
      final startup = _startup(player, controller);

      await startup.refreshAfterMetadata();

      expect(player.calls, isEmpty);
    },
  );

  test(
    'replacement during initial seek cannot start the old controller',
    () async {
      final player = _NativePlayer(_stream.url)..seekGate = Completer<void>();
      var current = true;
      final startup = _startup(
        player,
        _Controller(player.calls),
        isCurrent: () => current,
      );
      final open = startup.open(
        initialized: false,
        looping: false,
        muted: false,
        playing: true,
        isLive: false,
        startPosition: const PlaybackStartPosition.resume(Duration(minutes: 3)),
      );
      await Future<void>.delayed(Duration.zero);
      current = false;
      player.seekGate!.complete();
      expect(await open, isFalse);
      expect(player.calls, isNot(contains('play')));
    },
  );

  test('a failed initial seek does not start at the beginning', () async {
    final player = _NativePlayer(_stream.url)..seekGate = Completer<void>();
    final open = _startup(player, _Controller(player.calls)).open(
      initialized: false,
      looping: false,
      muted: false,
      playing: true,
      isLive: false,
      startPosition: const PlaybackStartPosition.resume(Duration(minutes: 3)),
    );
    final result = expectLater(open, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    player.seekGate!.completeError(StateError('seek failed'));
    await result;
    expect(player.calls, isNot(contains('play')));
  });
}

VideoPlayerStartup _startup(
  _NativePlayer player,
  _Controller controller, {
  PlayableStream stream = _stream,
  bool preselected = false,
  bool Function()? isCurrent,
}) => VideoPlayerStartup(
  player: player,
  controller: controller,
  stream: stream,
  refreshTracks: () async {
    player.calls.add('tracks');
  },
  isCurrent: isCurrent ?? () => true,
  log: (_, {details}) {},
  maxHeight: 720,
  preferredQualityDone: preselected,
);

class _NativePlayer extends vp.VideoPlayerController {
  _NativePlayer(String url) : super.networkUrl(Uri.parse(url));
  final List<String> calls = [];
  Completer<void>? seekGate;
  @override
  Future<void> initialize() async {
    calls.add('initialize');
    value = const vp.VideoPlayerValue(
      duration: Duration(minutes: 10),
      isInitialized: true,
    );
  }

  @override
  Future<void> setLooping(bool looping) async {
    calls.add('looping');
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume');
  }

  @override
  Future<void> seekTo(Duration position) async {
    calls.add('seek:${position.inSeconds}');
    await seekGate?.future;
    value = value.copyWith(position: position);
  }

  @override
  Future<void> play() async {
    calls.add('play');
  }
}

class _Controller extends FakeAppPlayerController {
  _Controller(this.calls);
  final List<String> calls;
  int qualityCalls = 0;

  @override
  List<AppAudioTrack> get audioTracks => const [
    AppAudioTrack(id: 'audio', label: 'Audio'),
  ];

  @override
  List<AppQualityTrack> get qualityTracks => const [
    AppQualityTrack(id: '720', height: 720),
  ];
  @override
  Future<void> setQuality(AppQualityTrack? track) async {
    calls.add('quality');
    qualityCalls++;
  }
}
