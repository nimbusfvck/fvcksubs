import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class SourcePriorityState {
  const SourcePriorityState({this.orderedProviderIds = const []});

  final List<String> orderedProviderIds;
}

class SourcePriorityController extends Cubit<SourcePriorityState> {
  SourcePriorityController({
    required this.registry,
    required this.store,
    List<String> initial = const [],
  }) : super(
         SourcePriorityState(orderedProviderIds: List.unmodifiable(initial)),
       );

  final ExtensionRegistry registry;
  final SourcePriorityStore store;

  List<ProviderDecl> get availableProviders {
    final providers = [
      for (final manifest in registry.installed)
        for (final provider in manifest.providers)
          if (provider.roles.contains(ProviderRole.stream)) provider,
    ];
    final byId = {for (final provider in providers) provider.id: provider};
    return [
      for (final id in state.orderedProviderIds) ?byId.remove(id),
      ...byId.values,
    ];
  }

  void reorder(int oldIndex, int newIndex) {
    final ids = [for (final provider in availableProviders) provider.id];
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    _save(ids);
  }

  void reset() => _save(const []);

  int rankOf(String providerId) {
    final rank = state.orderedProviderIds.indexOf(providerId);
    return rank < 0 ? state.orderedProviderIds.length : rank;
  }

  List<StreamSource> order(List<StreamSource> sources) {
    final indexed = sources.indexed.toList();
    indexed.sort((a, b) {
      final aRank = rankOf(a.$2.providerId);
      final bRank = rankOf(b.$2.providerId);
      final result = aRank.compareTo(bRank);
      return result == 0 ? a.$1.compareTo(b.$1) : result;
    });
    return [for (final entry in indexed) entry.$2];
  }

  void _save(List<String> ids) {
    final value = List<String>.unmodifiable(ids);
    emit(SourcePriorityState(orderedProviderIds: value));
    unawaited(store.save(value));
  }
}
