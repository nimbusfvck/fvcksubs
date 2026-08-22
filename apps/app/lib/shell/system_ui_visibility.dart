import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps system chrome aligned with the shell orientation.
class SystemUiVisibility extends StatefulWidget {
  const SystemUiVisibility({super.key, required this.child});

  final Widget child;

  @override
  State<SystemUiVisibility> createState() => _SystemUiVisibilityState();
}

class _SystemUiVisibilityState extends State<SystemUiVisibility> {
  bool? _landscape;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (_landscape == landscape) return;
    _landscape = landscape;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_setSystemUiMode(landscape));
    });
  }

  @override
  void dispose() {
    if (_landscape == true) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  Future<void> _setSystemUiMode(bool landscape) =>
      SystemChrome.setEnabledSystemUIMode(
        landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );

  @override
  Widget build(BuildContext context) => widget.child;
}
