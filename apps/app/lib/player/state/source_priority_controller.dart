import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class SourcePriorityState {
  const SourcePriorityState({
    this.orderedProviderIds = const [],
    this.sourceLocale = SourceLocalePreference.auto,
  });

  final List<String> orderedProviderIds;
  final SourceLocalePreference sourceLocale;
}

class SourcePriorityController extends Cubit<SourcePriorityState> {
  SourcePriorityController({
    required this.registry,
    required this.store,
    this.localeStore,
    List<String> initial = const [],
    SourceLocalePreference sourceLocale = SourceLocalePreference.auto,
  }) : super(
         SourcePriorityState(
           orderedProviderIds: List.unmodifiable(initial),
           sourceLocale: sourceLocale,
         ),
       );

  final ExtensionRegistry registry;
  final SourcePriorityStore store;
  final SourceLocalePreferenceStore? localeStore;

  /// The selected source locale override, or [SourceLocalePreference.auto].
  SourceLocalePreference get sourceLocale => state.sourceLocale;

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

  /// Changes the locale used for generic provider ranking.
  void setSourceLocale(SourceLocalePreference sourceLocale) {
    emit(
      SourcePriorityState(
        orderedProviderIds: state.orderedProviderIds,
        sourceLocale: sourceLocale,
      ),
    );
    final store = localeStore;
    if (store != null) unawaited(store.save(sourceLocale));
  }

  int rankOf(String providerId) {
    final rank = state.orderedProviderIds.indexOf(providerId);
    if (rank >= 0) return rank;
    return state.orderedProviderIds.length + _localeRank(providerId) * 1000;
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

  int _localeRank(String providerId) {
    final provider = _providerById(providerId);
    if (provider == null || provider.locales.isEmpty) return 3;
    final preferredCountryCode =
        state.sourceLocale.countryCode ??
        ui.PlatformDispatcher.instance.locale.countryCode;
    final preferredLanguageCode =
        state.sourceLocale.languageCode ??
        ui.PlatformDispatcher.instance.locale.languageCode;
    final country =
        preferredCountryCode != null &&
        provider.locales.countries.any(
          (value) => value.toUpperCase() == preferredCountryCode.toUpperCase(),
        );
    final language =
        preferredLanguageCode.isNotEmpty &&
        provider.locales.languages.any(
          (value) => value.toLowerCase() == preferredLanguageCode.toLowerCase(),
        );
    if (country && language) return 0;
    if (country) return 1;
    if (language) return 2;
    return 3;
  }

  ProviderDecl? _providerById(String providerId) {
    for (final manifest in registry.installed) {
      for (final provider in manifest.providers) {
        if (provider.id == providerId) return provider;
      }
    }
    return null;
  }

  void _save(List<String> ids) {
    final value = List<String>.unmodifiable(ids);
    emit(
      SourcePriorityState(
        orderedProviderIds: value,
        sourceLocale: state.sourceLocale,
      ),
    );
    unawaited(store.save(value));
  }
}
