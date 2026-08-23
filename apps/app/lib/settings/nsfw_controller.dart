import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class NsfwState {
  const NsfwState({required this.showNsfw, this.revision = 0});

  final bool showNsfw;
  final int revision;

  NsfwState next(bool enabled) =>
      NsfwState(showNsfw: enabled, revision: revision + 1);
}

class NsfwController extends Cubit<NsfwState> {
  NsfwController({
    required this.registry,
    required this.store,
    required bool showNsfw,
  }) : super(NsfwState(showNsfw: showNsfw)) {
    registry.setNsfwEnabled(showNsfw);
  }

  final ExtensionRegistry registry;
  final NsfwSettingsStore store;

  void setShowNsfw(bool enabled) {
    registry.setNsfwEnabled(enabled);
    unawaited(store.save(NsfwSettings(showNsfw: enabled)));
    emit(state.next(enabled));
  }
}
