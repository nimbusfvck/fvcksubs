import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class PictureInPicturePreferenceController extends ChangeNotifier {
  PictureInPicturePreferenceController({
    required this.store,
    bool initial = true,
  }) : _enabled = initial;

  final PictureInPicturePreferenceStore store;
  bool _enabled;

  bool get enabled => _enabled;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    unawaited(store.save(enabled));
    notifyListeners();
  }
}
