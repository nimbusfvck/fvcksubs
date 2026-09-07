# video_player_mini_player

Reusable YouTube-style in-app mini-player presentation for Flutter.

The package keeps one player widget in a persistent overlay while changing its
bounds between full screen and a corner-docked card. This is intentionally
separate from system Picture-in-Picture: an app can use the forked
`video_player` controller for native PiP and this package for the in-app
gesture and overlay.

```dart
final session = MiniPlayerSession();

MaterialApp(
  navigatorObservers: [
    MiniPlayerNavigatorObserver(session: session),
  ],
  // Attach the same player widget for the lifetime of the playback session.
);

session.attach(
  playerWidget,
  onPlaybackToggleRequested: togglePlayback,
);
```

The host keeps the player mounted while it is minimized, so native platform
views are not recreated during the transition. Tapping the card restores full
screen; the mini bar exposes playback toggle on the left and close on the right.
The compact frame is capped at 200px wide with a 16:9 ratio, and each action
button has its own 24px rounded translucent-black background instead of a
full-width toolbar. Dragging moves the card with the user's finger and snaps it
to the nearest corner when released.
Publish the native status so the toggle can show pause, play, or loading:

```dart
session.setPlaybackState(
  isPlaying: controller.value.isPlaying,
  isBuffering: controller.value.isBuffering,
);
```

`setInteractionEnabled(false)` can temporarily release input to the underlying
route while native PiP owns the surface.
