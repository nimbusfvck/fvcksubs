import 'package:video_player_mini_player/video_player_mini_player.dart';

export 'package:video_player_mini_player/video_player_mini_player.dart'
    show
        MiniPlayerMode,
        MiniPlayerDock,
        MiniPlayerPlaybackState,
        MiniPlayerPresentationState,
        MiniPlayerSession,
        MiniPlayerHost,
        MiniPlayerNavigatorObserver;

/// App-facing name kept for the existing playback and test seams.
typedef PictureInPictureSession = MiniPlayerSession;

/// App-facing name kept for the existing navigator wiring.
typedef PictureInPictureNavigatorObserver = MiniPlayerNavigatorObserver;

/// App-facing name kept for the existing overlay wiring.
typedef PictureInPictureHost = MiniPlayerHost;
