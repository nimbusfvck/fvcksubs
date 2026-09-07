import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The presentation state of the persistent in-app player.
enum MiniPlayerMode {
  /// The player occupies the available host surface.
  fullScreen,

  /// The player is following an active downward drag.
  dragging,

  /// The player is docked as a small card above the current route.
  minimized,
}

/// The corner where a minimized player is docked.
enum MiniPlayerDock {
  /// Dock the player near the top-left corner.
  topLeft,

  /// Dock the player near the top-right corner.
  topRight,

  /// Dock the player near the bottom-right corner.
  bottomRight,

  /// Dock the player near the bottom-left corner.
  bottomLeft,
}

/// Immutable presentation snapshot shared by the player and its host.
class MiniPlayerPresentationState {
  /// Creates a full-screen presentation state.
  const MiniPlayerPresentationState({
    this.mode = MiniPlayerMode.fullScreen,
    this.dragProgress = 0,
    this.interactionEnabled = true,
    this.dock = MiniPlayerDock.bottomRight,
  });

  /// The current visual mode.
  final MiniPlayerMode mode;

  /// The current normalized drag amount, from zero to one.
  final double dragProgress;

  /// Whether the host accepts in-app gestures and input.
  final bool interactionEnabled;

  /// The corner used by the minimized player.
  final MiniPlayerDock dock;

  /// Whether full-screen controls should be rendered by the player.
  bool get showControls => mode == MiniPlayerMode.fullScreen;

  /// Whether the player presentation should paint its full-screen background.
  bool get showBackground => mode == MiniPlayerMode.fullScreen;

  /// Returns a state with selected presentation fields replaced.
  MiniPlayerPresentationState copyWith({
    MiniPlayerMode? mode,
    double? dragProgress,
    bool? interactionEnabled,
    MiniPlayerDock? dock,
  }) => MiniPlayerPresentationState(
    mode: mode ?? this.mode,
    dragProgress: dragProgress ?? this.dragProgress,
    interactionEnabled: interactionEnabled ?? this.interactionEnabled,
    dock: dock ?? this.dock,
  );

  @override
  bool operator ==(Object other) =>
      other is MiniPlayerPresentationState &&
      other.mode == mode &&
      other.dragProgress == dragProgress &&
      other.interactionEnabled == interactionEnabled &&
      other.dock == dock;

  @override
  int get hashCode => Object.hash(mode, dragProgress, interactionEnabled, dock);
}

/// Playback status consumed by the compact controls.
class MiniPlayerPlaybackState {
  /// Creates a playback status snapshot.
  const MiniPlayerPlaybackState({
    this.isPlaying = false,
    this.isBuffering = true,
  });

  /// Whether the native player is currently playing.
  final bool isPlaying;

  /// Whether the native player is waiting for data.
  final bool isBuffering;

  @override
  bool operator ==(Object other) =>
      other is MiniPlayerPlaybackState &&
      other.isPlaying == isPlaying &&
      other.isBuffering == isBuffering;

  @override
  int get hashCode => Object.hash(isPlaying, isBuffering);
}

/// Keeps one player widget alive while its presentation changes.
///
/// The session deliberately owns a widget rather than a video controller. A
/// player widget can contain native platform views, and moving that same
/// widget between routes can recreate the native surface. The host therefore
/// keeps it in one overlay entry for the whole session.
class MiniPlayerSession extends ValueNotifier<MiniPlayerPresentationState> {
  /// Creates a session in its full-screen state.
  MiniPlayerSession() : super(const MiniPlayerPresentationState());

  Widget? _player;
  VoidCallback? _onCloseRequested;
  VoidCallback? _onPlaybackToggleRequested;
  final ValueNotifier<MiniPlayerPlaybackState> _playback = ValueNotifier(
    const MiniPlayerPlaybackState(),
  );

  /// Navigator key for app-owned sheets that must appear above the player.
  final GlobalKey<NavigatorState> modalNavigatorKey =
      GlobalKey<NavigatorState>();

  /// Whether an app-owned modal is currently above the player.
  final ValueNotifier<bool> modalOpen = ValueNotifier<bool>(false);

  /// The player widget currently owned by this session.
  Widget? get player => _player;

  /// The presentation state consumed by player surfaces and hosts.
  ValueListenable<MiniPlayerPresentationState> get presentation => this;

  /// The playback state consumed by the compact controls.
  ValueListenable<MiniPlayerPlaybackState> get playback => _playback;

  /// The current visual mode.
  MiniPlayerMode get mode => value.mode;

  /// The current normalized drag amount.
  double get dragProgress => value.dragProgress;

  /// Whether the player is currently docked as a mini-player.
  bool get isMinimized => value.mode == MiniPlayerMode.minimized;

  /// Whether the player is still in its full-screen presentation.
  bool get isFullScreen => value.mode == MiniPlayerMode.fullScreen;

  /// Whether the host should accept in-app gestures for this session.
  bool get interactionEnabled => value.interactionEnabled;

  /// Attaches a player widget to this persistent session.
  void attach(
    Widget player, {
    VoidCallback? onCloseRequested,
    VoidCallback? onPlaybackToggleRequested,
  }) {
    _player = player;
    _onCloseRequested = onCloseRequested;
    _onPlaybackToggleRequested = onPlaybackToggleRequested;
    _playback.value = const MiniPlayerPlaybackState();
    _setPresentation(const MiniPlayerPresentationState());
  }

  /// Detaches [player] when it is still the active session widget.
  void detach(Widget player) {
    if (!identical(_player, player)) return;
    _player = null;
    _onCloseRequested = null;
    _onPlaybackToggleRequested = null;
    _playback.value = const MiniPlayerPlaybackState();
    _setPresentation(const MiniPlayerPresentationState());
  }

  /// Publishes a normalized drag amount while the host is tracking a gesture.
  void updateDrag(double progress) {
    final next = progress.clamp(0.0, 1.0).toDouble();
    final nextMode = next == 0
        ? MiniPlayerMode.fullScreen
        : MiniPlayerMode.dragging;
    if (value.dragProgress == next && value.mode == nextMode) return;
    _setPresentation(value.copyWith(mode: nextMode, dragProgress: next));
  }

  /// Commits the current player position as the minimized state.
  void minimize() {
    _setPresentation(
      value.copyWith(mode: MiniPlayerMode.minimized, dragProgress: 1),
    );
  }

  /// Expands the player to its full-screen state.
  void restore() {
    _setPresentation(
      value.copyWith(mode: MiniPlayerMode.fullScreen, dragProgress: 0),
    );
  }

  /// Enables or disables host gestures while a native surface owns input.
  void setInteractionEnabled(bool enabled) {
    if (value.interactionEnabled == enabled) return;
    _setPresentation(value.copyWith(interactionEnabled: enabled));
  }

  /// Moves the minimized player to [dock].
  void setDock(MiniPlayerDock dock) {
    if (value.dock == dock) return;
    _setPresentation(value.copyWith(dock: dock));
  }

  /// Closes the player, invoking the optional close callback first.
  void close() {
    final callback = _onCloseRequested;
    if (callback != null) {
      callback();
      return;
    }
    final player = _player;
    if (player != null) detach(player);
  }

  /// Requests a playback toggle while keeping the mini-player open.
  void togglePlayback() => _onPlaybackToggleRequested?.call();

  /// Updates the playback toggle command after the player is ready.
  void setPlaybackToggleRequested(VoidCallback? callback) {
    _onPlaybackToggleRequested = callback;
  }

  /// Publishes playback status for compact controls without changing layout.
  void setPlaybackState({required bool isPlaying, required bool isBuffering}) {
    final next = MiniPlayerPlaybackState(
      isPlaying: isPlaying,
      isBuffering: isBuffering,
    );
    if (_playback.value == next) return;
    _playback.value = next;
  }

  void _setPresentation(MiniPlayerPresentationState next) {
    if (value == next) {
      // Attaching or detaching a different widget still needs to rebuild the
      // persistent host even when the visual state itself is unchanged.
      notifyListeners();
      return;
    }
    value = next;
  }

  @override
  void dispose() {
    _playback.dispose();
    modalOpen.dispose();
    super.dispose();
  }
}
