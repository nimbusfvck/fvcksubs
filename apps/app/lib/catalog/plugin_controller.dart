import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class PluginController extends ChangeNotifier {
  PluginController({required this.store, String? initial})
    : _selectedId = initial;

  final PluginSelectionStore store;

  String? _selectedId;

  String? get selectedId => _selectedId;

  void select(String extensionId) {
    if (_selectedId == extensionId) return;
    _selectedId = extensionId;
    unawaited(store.save(extensionId));
    notifyListeners();
  }

  String? resolve(List<String> availableIds) {
    if (availableIds.isEmpty) return null;
    final selected = _selectedId;
    if (selected != null && availableIds.contains(selected)) return selected;
    return availableIds.first;
  }
}
