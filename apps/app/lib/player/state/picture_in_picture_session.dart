import 'package:flutter/widgets.dart';

/// Owns the player widget while native iOS PiP is detached from navigation.
///
/// The widget is moved out of the Navigator rather than rebuilt. Its global
/// key therefore keeps the native player controller alive while the caller's
/// routes continue to push, pop, and switch destinations normally.
class PictureInPictureSession extends ChangeNotifier {
  Widget? _player;

  Widget? get player => _player;

  void attach(Widget player) {
    _player = player;
    notifyListeners();
  }

  void detach(Widget player) {
    if (!identical(_player, player)) return;
    _player = null;
    notifyListeners();
  }
}

/// Renders the active PiP player outside the app Navigator.
class PictureInPictureHost extends StatelessWidget {
  const PictureInPictureHost({super.key, required this.session});

  final PictureInPictureSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final player = session.player;
      return player ?? const SizedBox.shrink();
    },
  );
}
