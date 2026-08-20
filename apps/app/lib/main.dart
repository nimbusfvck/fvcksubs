import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import 'addons/addons_controller.dart';
import 'addons/installer_controller.dart';
import 'addons/permission_dialog.dart';
import 'app.dart';
import 'catalog/catalog_cache.dart';
import 'catalog/catalog_page_store.dart';
import 'catalog/plugin_controller.dart';
import 'library/library_controller.dart';
import 'library/legacy_library_controller.dart';
import 'player/source_cache.dart';
import 'player/source_priority_controller.dart';
import 'player/subtitle_preference_controller.dart';
import 'platform/device_class.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final deviceClass = await DeviceClassResolver.resolve();

  final settingsStore = SharedPreferencesAddonSettingsStore();
  final settings = await settingsStore.load();
  final registry = buildRegistry(
    disabledExtensionIds: settings.disabledExtensionIds,
    disabledProviderIds: settings.disabledProviderIds,
  );
  final addonsController = AddonsController(
    registry: registry,
    store: settingsStore,
  );

  final installedStore = SharedPreferencesInstalledExtensionStore();
  await loadInstalledExtensions(registry, installedStore);

  final navigatorKey = GlobalKey<NavigatorState>();

  final repoStore = SharedPreferencesRepoStore();
  final installerController = InstallerController(
    registry: registry,
    installer: ExtensionInstaller(),
    installedStore: installedStore,
    repoStore: repoStore,
    repoUrl: await repoStore.load(),
    requestConsent: (request) async {
      final context = navigatorKey.currentContext;
      if (context == null) return false;
      return showPermissionDialog(context, request);
    },
  );

  final legacyLibraryStore = SharedPreferencesLegacyLibraryStore();
  final legacyLibraryController = LegacyLibraryController(
    store: legacyLibraryStore,
    initial: await legacyLibraryStore.load(),
  );
  final libraryStore = SharedPreferencesLibraryStore();
  final libraryController = LibraryController(
    store: libraryStore,
    initial: await libraryStore.load(),
  );

  const pluginStore = SharedPreferencesPluginSelectionStore();
  final pluginController = PluginController(
    store: pluginStore,
    initial: await pluginStore.load(),
  );

  const subtitleStore = SharedPreferencesSubtitlePreferenceStore();
  final subtitlePreferenceController = SubtitlePreferenceController(
    store: subtitleStore,
    initial: await subtitleStore.load(),
  );

  const sourcePriorityStore = SharedPreferencesSourcePriorityStore();
  final sourcePriorityController = SourcePriorityController(
    registry: registry,
    store: sourcePriorityStore,
    initial: await sourcePriorityStore.load(),
  );

  final sourceListStore = SharedPreferencesSourceListStore();
  final sourceCache = SourceCache(
    sourceListStore: sourceListStore,
    initial: await sourceListStore.load(),
  );

  runApp(
    FvcksubsApp(
      registry: registry,
      deviceClass: deviceClass,
      addonsController: addonsController,
      installerController: installerController,
      legacyLibraryController: legacyLibraryController,
      libraryController: libraryController,
      pluginController: pluginController,
      catalogCache: CatalogCache(store: await SembastCatalogPageStore.open()),
      subtitlePreferenceController: subtitlePreferenceController,
      sourcePriorityController: sourcePriorityController,
      homeCategoryStore: const SharedPreferencesCategorySelectionStore('home'),
      sourceCache: sourceCache,
      navigatorKey: navigatorKey,
    ),
  );
}

Future<void> loadInstalledExtensions(
  ExtensionRegistry registry,
  InstalledExtensionStore store,
) async {
  final Map<String, InstalledExtension> installed;
  try {
    installed = await store.loadAll();
  } catch (error, stack) {
    debugPrint('Could not read installed extensions: $error\n$stack');
    return;
  }

  for (final record in installed.values) {
    try {
      final manifest = Manifest.parse(
        jsonDecode(record.manifestJson) as Map<String, Object?>,
      );
      final replaced = registry.install(
        JsExtension.load(manifest: manifest, source: record.bundleJs),
      );
      if (replaced is JsExtension) replaced.dispose();
    } catch (error, stack) {
      debugPrint('Skipping installed extension ${record.id}: $error\n$stack');
    }
  }
}

ExtensionRegistry buildRegistry({
  Set<String> disabledExtensionIds = const {},
  Set<String> disabledProviderIds = const {},
  ContentExtension? initialExtension,
}) => ExtensionRegistry(
  [?initialExtension],
  disabledExtensionIds: disabledExtensionIds,
  disabledProviderIds: disabledProviderIds,
);
