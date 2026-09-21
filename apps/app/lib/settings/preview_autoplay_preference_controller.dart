import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class PreviewAutoplayPreferenceController extends ChangeNotifier {
  PreviewAutoplayPreferenceController({
    required this.store,
    bool initial = true,
  }) : _enabled = initial;

  final PreviewAutoplayPreferenceStore store;
  bool _enabled;

  bool get enabled => _enabled;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    unawaited(store.save(enabled));
    notifyListeners();
  }
}
