import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class PermissionRequest {
  const PermissionRequest({
    required this.entry,
    required this.newHosts,
    required this.alreadyGrantedHosts,
    required this.isUpdate,
    this.installedVersion,
  });

  final ExtensionRepoEntry entry;

  final List<String> newHosts;

  final List<String> alreadyGrantedHosts;

  final bool isUpdate;

  final String? installedVersion;

  List<String> get allHosts => [...alreadyGrantedHosts, ...newHosts];
}

class RepoListing {
  const RepoListing({required this.entry, required this.installedVersion});

  final ExtensionRepoEntry entry;

  final String? installedVersion;

  bool get isInstalled => installedVersion != null;

  bool get isUpdate =>
      installedVersion != null &&
      ExtensionInstaller.isVersionNewer(entry.version, installedVersion!);

  bool get isUpToDate => isInstalled && !isUpdate;
}

class InstallerState {
  const InstallerState({
    this.repoUrl,
    this.listings = const [],
    this.busy = false,
    this.error,
  });

  final String? repoUrl;
  final List<RepoListing> listings;
  final bool busy;
  final String? error;

  InstallerState copyWith({
    String? repoUrl,
    bool clearRepoUrl = false,
    List<RepoListing>? listings,
    bool? busy,
    String? error,
    bool clearError = false,
  }) => InstallerState(
    repoUrl: clearRepoUrl ? null : repoUrl ?? this.repoUrl,
    listings: listings ?? this.listings,
    busy: busy ?? this.busy,
    error: clearError ? null : error ?? this.error,
  );
}

class InstallerController extends Cubit<InstallerState> {
  InstallerController({
    required this.registry,
    required this.installer,
    required this.installedStore,
    required this.repoStore,
    String? repoUrl,
    ContentExtension Function(Manifest manifest, String source) loadExtension =
        _loadJsExtension,
    Future<bool> Function(PermissionRequest request) requestConsent =
        _refuseByDefault,
  }) : _loadExtension = loadExtension,
       _requestConsent = requestConsent,
       super(InstallerState(repoUrl: repoUrl));

  static ContentExtension _loadJsExtension(Manifest manifest, String source) =>
      JsExtension.load(manifest: manifest, source: source);

  static Future<bool> _refuseByDefault(PermissionRequest _) async => false;

  final ContentExtension Function(Manifest, String) _loadExtension;
  final Future<bool> Function(PermissionRequest) _requestConsent;

  final ExtensionRegistry registry;

  final ExtensionInstaller installer;

  final InstalledExtensionStore installedStore;

  final RepoStore repoStore;

  String? get repoUrl => state.repoUrl;
  List<RepoListing> get listings => state.listings;
  bool get busy => state.busy;
  String? get error => state.error;

  RepoListing? listingFor(String extensionId) {
    for (final listing in state.listings) {
      if (listing.entry.id == extensionId) return listing;
    }
    return null;
  }

  Future<void> setRepoUrl(String? url) async {
    final trimmed = (url == null || url.trim().isEmpty) ? null : url.trim();
    if (trimmed == state.repoUrl) return;
    emit(
      state.copyWith(
        repoUrl: trimmed,
        clearRepoUrl: trimmed == null,
        listings: const [],
        clearError: true,
      ),
    );
    await repoStore.save(trimmed);
  }

  Future<void> refresh({bool silent = false}) async {
    final url = state.repoUrl;
    if (url == null) {
      if (!silent) emit(state.copyWith(error: 'Set a repo URL first.'));
      return;
    }

    emit(state.copyWith(busy: true, clearError: true));

    try {
      final repo = await installer.fetchRepo(url);
      final installed = await installedStore.loadAll();
      final listings = [
        for (final entry in repo.extensions)
          RepoListing(
            entry: entry,
            installedVersion: installed[entry.id]?.version,
          ),
      ];
      emit(
        state.copyWith(
          listings: listings,
          error: listings.isEmpty ? 'This repo lists no extensions.' : null,
          clearError: listings.isNotEmpty,
        ),
      );
    } catch (e) {
      if (silent) {
        emit(state.copyWith(clearError: true));
      } else {
        emit(
          state.copyWith(
            listings: const [],
            error: 'Could not read the repo: $e',
          ),
        );
      }
    } finally {
      emit(state.copyWith(busy: false));
    }
  }

  Future<List<String>?> _consentFor(ExtensionRepoEntry entry) async {
    final installed = (await installedStore.loadAll())[entry.id];
    final granted = <String>[];
    if (installed != null) {
      try {
        granted.addAll(
          Manifest.parse(
            jsonDecode(installed.manifestJson) as Map<String, Object?>,
          ).permissions.hosts,
        );
      } catch (_) {}
    }

    final wanted = entry.hosts;
    final newHosts = [
      for (final host in wanted)
        if (!granted.contains(host)) host,
    ];

    final accepted = await _requestConsent(
      PermissionRequest(
        entry: entry,
        newHosts: newHosts,
        alreadyGrantedHosts: installed == null
            ? const []
            : granted.where(wanted.contains).toList(),
        isUpdate: installed != null,
        installedVersion: installed?.version,
      ),
    );
    if (!accepted) return null;
    return {...granted, ...wanted}.toList();
  }

  Future<void> install(ExtensionRepoEntry entry) async {
    emit(state.copyWith(busy: true, clearError: true));

    ContentExtension? loaded;
    try {
      final consented = await _consentFor(entry);
      if (consented == null) return;

      final downloaded = await installer.download(entry);
      final manifest = Manifest.parse(
        jsonDecode(downloaded.manifestJson) as Map<String, Object?>,
      );

      final undeclared = [
        for (final host in manifest.permissions.hosts)
          if (!consented.contains(host)) host,
      ];
      if (undeclared.isNotEmpty) {
        throw StateError(
          'manifest wants hosts the repo did not list: ${undeclared.join(', ')}',
        );
      }

      loaded = _loadExtension(manifest, downloaded.bundleJs);

      await installedStore.save(downloaded);
      final replaced = registry.install(loaded);
      loaded = null; // handed to the registry; no longer ours to dispose
      if (replaced is JsExtension) replaced.dispose();

      await refresh();
    } catch (e) {
      emit(state.copyWith(error: 'Install failed: $e'));
    } finally {
      if (loaded is JsExtension) loaded.dispose();
      emit(state.copyWith(busy: false));
    }
  }

  Future<void> uninstall(String id) async {
    emit(state.copyWith(busy: true, clearError: true));

    try {
      final removed = registry.uninstall(id);
      if (removed is JsExtension) removed.dispose();
      await installedStore.remove(id);
      if (state.repoUrl == null) {
        emit(
          state.copyWith(
            listings: [
              for (final listing in state.listings)
                if (listing.entry.id == id)
                  RepoListing(entry: listing.entry, installedVersion: null)
                else
                  listing,
            ],
          ),
        );
      } else {
        await refresh();
      }
    } catch (e) {
      emit(state.copyWith(error: 'Uninstall failed: $e'));
    } finally {
      emit(state.copyWith(busy: false));
    }
  }
}
