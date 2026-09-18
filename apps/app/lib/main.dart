import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_js_runtime/fvcksubs_js_runtime.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

import 'addons/addons_controller.dart';
import 'addons/extension_storage_hub.dart';
import 'addons/installer_controller.dart';
import 'addons/permission_dialog.dart';
import 'app.dart';
import 'catalog/catalog_cache.dart';
import 'catalog/catalog_page_store.dart';
import 'catalog/plugin_controller.dart';
import 'library/library_controller.dart';
import 'player/state/source_cache.dart';
import 'player/state/picture_in_picture_session.dart';
import 'player/state/picture_in_picture_preference_controller.dart';
import 'player/state/source_priority_controller.dart';
import 'player/state/quality_preference_controller.dart';
import 'player/state/subtitle_preference_controller.dart';
import 'platform/device_class.dart';
import 'platform/cloudflare_killer.dart';
import 'platform/web_view_resolver.dart';
import 'settings/nsfw_controller.dart';
import 'settings/preview_autoplay_preference_controller.dart';
import 'settings/febbox_cookie_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cloudflareKiller = CloudflareKiller();
  final webViewResolver = WebViewResolver();

  // These reads do not depend on one another. Starting them together keeps
  // the first frame from paying each storage/platform round-trip in series.
  // Extension loading remains below this barrier because it needs the loaded
  // settings and storage hub to establish the registry and its permissions.
  final settingsStore = SharedPreferencesAddonSettingsStore();
  final nsfwStore = SharedPreferencesNsfwSettingsStore();
  final settingsFuture = settingsStore.load();
  final nsfwSettingsFuture = nsfwStore.load();
  final febboxCookieStore = SecureFebboxCookieStore();
  final febboxCookieFuture = febboxCookieStore.read();
  final deviceClassFuture = DeviceClassResolver.resolve();

  final extensionStorageFuture = ExtensionStorageHub.open();
  final installedStore = SharedPreferencesInstalledExtensionStore();

  final repoStore = SharedPreferencesRepoStore();
  final repoUrlFuture = repoStore.load();

  final libraryStore = SharedPreferencesLibraryStore();
  final libraryFuture = _loadPersistedOrDefault(
    name: 'library',
    load: libraryStore.load,
    fallback: const <String, UserMediaState>{},
  );

  const pluginStore = SharedPreferencesPluginSelectionStore();
  final pluginSelectionFuture = pluginStore.load();

  final subtitleStore = SharedPreferencesSubtitlePreferenceStore();
  final subtitleLanguageFuture = subtitleStore.load();
  final subtitleAppearanceFuture = subtitleStore.loadAppearance();
  final subtitleSelectionsFuture = subtitleStore.loadExternalSelections();

  const qualityStore = SharedPreferencesQualityPreferenceStore();
  final qualityFuture = qualityStore.load();

  const pictureInPictureStore =
      SharedPreferencesPictureInPicturePreferenceStore();
  final pictureInPictureFuture = pictureInPictureStore.load();
  const previewAutoplayStore =
      SharedPreferencesPreviewAutoplayPreferenceStore();
  final previewAutoplayFuture = previewAutoplayStore.load();

  const sourcePriorityStore = SharedPreferencesSourcePriorityStore();
  final sourcePriorityFuture = sourcePriorityStore.load();
  const sourceLocaleStore = SharedPreferencesSourceLocalePreferenceStore();
  final sourceLocaleFuture = sourceLocaleStore.load();

  final sourceListStore = SharedPreferencesSourceListStore();
  final sourceCacheFuture = _loadPersistedOrDefault(
    name: 'source lists',
    load: sourceListStore.load,
    fallback: const <String, CachedSourceList>{},
  );

  final catalogCacheFuture = _loadPersistedOrDefault(
    name: 'catalog cache',
    load: () async => CatalogCache(store: await SembastCatalogPageStore.open()),
    fallback: CatalogCache(),
  );

  final deviceClass = await deviceClassFuture;
  final settings = await settingsFuture;
  final nsfwSettings = await nsfwSettingsFuture;
  final febboxCookie = await _loadPersistedOrDefault<String?>(
    name: 'Febbox cookie',
    load: () => febboxCookieFuture,
    fallback: null,
  );
  final registry = buildRegistry(
    disabledExtensionIds: settings.disabledExtensionIds,
    disabledProviderIds: settings.disabledProviderIds,
    showNsfw: nsfwSettings.showNsfw,
  );
  final addonsController = AddonsController(
    registry: registry,
    store: settingsStore,
  );
  final nsfwController = NsfwController(
    registry: registry,
    store: nsfwStore,
    showNsfw: nsfwSettings.showNsfw,
  );

  final extensionStorage = await extensionStorageFuture;
  late final SourceCache sourceCache;
  late final FebboxCookieController febboxCookieController;

  Future<void> reloadExtensionsWithCookie(String? cookie) async {
    sourceCache.clearAll();
    await loadInstalledExtensions(
      registry,
      installedStore,
      extensionStorage,
      febboxCookie: cookie,
      cloudflareSolver: cloudflareKiller.solve,
      webViewResolver: webViewResolver.resolveMedia,
      networkLogger: kDebugMode ? _logJsFetch : null,
    );
  }

  febboxCookieController = FebboxCookieController(
    store: febboxCookieStore,
    initial: febboxCookie,
    onChanged: reloadExtensionsWithCookie,
  );
  await loadInstalledExtensions(
    registry,
    installedStore,
    extensionStorage,
    febboxCookie: febboxCookie,
    cloudflareSolver: cloudflareKiller.solve,
    webViewResolver: webViewResolver.resolveMedia,
    networkLogger: kDebugMode ? _logJsFetch : null,
  );

  final navigatorKey = GlobalKey<NavigatorState>();

  final installerController = InstallerController(
    registry: registry,
    installer: ExtensionInstaller(),
    installedStore: installedStore,
    repoStore: repoStore,
    repoUrl: await repoUrlFuture,
    loadExtension: (manifest, source) => JsExtension.load(
      manifest: manifest,
      source: source,
      storage: extensionStorage.forExtension(manifest.id),
      prelude: febboxExtensionPrelude(manifest, febboxCookieController.cookie),
      cloudflareSolver: cloudflareKiller.solve,
      webViewResolver: webViewResolver.resolveMedia,
      networkLogger: kDebugMode ? _logJsFetch : null,
    ),
    forgetStorage: extensionStorage.remove,
    requestConsent: (request) async {
      final context = navigatorKey.currentContext;
      if (context == null) return false;
      return showPermissionDialog(context, request);
    },
  );

  final libraryController = LibraryController(
    store: libraryStore,
    initial: await libraryFuture,
  );

  final pluginController = PluginController(
    store: pluginStore,
    initial: await pluginSelectionFuture,
  );

  final subtitlePreferenceController = SubtitlePreferenceController(
    store: subtitleStore,
    initial: await subtitleLanguageFuture,
    initialAppearance: await subtitleAppearanceFuture,
    initialExternalSelections: await subtitleSelectionsFuture,
  );

  final qualityPreferenceController = QualityPreferenceController(
    store: qualityStore,
    initial: await qualityFuture,
  );

  final pictureInPicturePreferenceController =
      PictureInPicturePreferenceController(
        store: pictureInPictureStore,
        initial: await pictureInPictureFuture,
      );
  final previewAutoplayPreferenceController =
      PreviewAutoplayPreferenceController(
        store: previewAutoplayStore,
        initial: await previewAutoplayFuture,
      );

  final sourcePriorityController = SourcePriorityController(
    registry: registry,
    store: sourcePriorityStore,
    initial: await sourcePriorityFuture,
    localeStore: sourceLocaleStore,
    sourceLocale: await sourceLocaleFuture,
  );

  sourceCache = SourceCache(
    sourceListStore: sourceListStore,
    initial: await sourceCacheFuture,
  );
  final catalogCache = await catalogCacheFuture;

  runApp(
    FvcksubsApp(
      registry: registry,
      deviceClass: deviceClass,
      addonsController: addonsController,
      installerController: installerController,
      libraryController: libraryController,
      pluginController: pluginController,
      catalogCache: catalogCache,
      qualityPreferenceController: qualityPreferenceController,
      subtitlePreferenceController: subtitlePreferenceController,
      sourcePriorityController: sourcePriorityController,
      sourceCache: sourceCache,
      pictureInPictureSession: PictureInPictureSession(),
      pictureInPicturePreferenceController:
          pictureInPicturePreferenceController,
      previewAutoplayPreferenceController: previewAutoplayPreferenceController,
      nsfwController: nsfwController,
      febboxCookieController: febboxCookieController,
      navigatorKey: navigatorKey,
    ),
  );

  // A saved repository is checked in the background so installed cards can
  // show update status without making the user open Addons first.
  unawaited(installerController.refresh(silent: true));
  unawaited(
    _restoreExternalSubtitleTracks(subtitleStore, subtitlePreferenceController),
  );
}

Future<void> _restoreExternalSubtitleTracks(
  SharedPreferencesSubtitlePreferenceStore store,
  SubtitlePreferenceController controller,
) async {
  final tracks = await store.loadExternalTracks();
  controller.restoreExternalTracks(tracks);
}

Future<T> _loadPersistedOrDefault<T>({
  required String name,
  required Future<T> Function() load,
  required T fallback,
}) async {
  try {
    return await load();
  } on Object catch (error, stack) {
    debugPrint('Could not read persisted $name: $error\n$stack');
    return fallback;
  }
}

Future<void> loadInstalledExtensions(
  ExtensionRegistry registry,
  InstalledExtensionStore store,
  ExtensionStorageHub storage, {
  String? febboxCookie,
  JsCloudflareSolver? cloudflareSolver,
  JsWebViewResolver? webViewResolver,
  JsRuntimeLogger? networkLogger,
}) async {
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
        JsExtension.load(
          manifest: manifest,
          source: record.bundleJs,
          storage: storage.forExtension(manifest.id),
          prelude: febboxExtensionPrelude(manifest, febboxCookie),
          cloudflareSolver: cloudflareSolver,
          webViewResolver: webViewResolver,
          networkLogger: networkLogger,
        ),
      );
      if (replaced is JsExtension) replaced.dispose();
    } catch (error, stack) {
      debugPrint('Skipping installed extension ${record.id}: $error\n$stack');
    }
  }
}

void _logJsFetch(String message) {
  debugPrint('[JsFetch] $message');
}

ExtensionRegistry buildRegistry({
  Set<String> disabledExtensionIds = const {},
  Set<String> disabledProviderIds = const {},
  bool showNsfw = false,
  ContentExtension? initialExtension,
}) => ExtensionRegistry(
  [?initialExtension],
  disabledExtensionIds: disabledExtensionIds,
  disabledProviderIds: disabledProviderIds,
  showNsfw: showNsfw,
);
