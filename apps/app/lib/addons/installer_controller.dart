import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

class PermissionRequest {
  const PermissionRequest({
    required this.entry,
    required this.newHosts,
    required this.alreadyGrantedHosts,
    required this.isUpdate,
  });

  final ExtensionRepoEntry entry;

  final List<String> newHosts;

  final List<String> alreadyGrantedHosts;

  final bool isUpdate;

  List<String> get allHosts => [...alreadyGrantedHosts, ...newHosts];
}

class RepoListing {
  const RepoListing({required this.entry, required this.installedVersion});

  final ExtensionRepoEntry entry;

  final String? installedVersion;

  bool get isUpdate => installedVersion != null;
}

class InstallerController extends ChangeNotifier {
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
  }) : _repoUrl = repoUrl,
       _loadExtension = loadExtension,
       _requestConsent = requestConsent;

  static ContentExtension _loadJsExtension(Manifest manifest, String source) =>
      JsExtension.load(manifest: manifest, source: source);

  static Future<bool> _refuseByDefault(PermissionRequest _) async => false;

  final ContentExtension Function(Manifest, String) _loadExtension;
  final Future<bool> Function(PermissionRequest) _requestConsent;

  final ExtensionRegistry registry;

  final ExtensionInstaller installer;

  final InstalledExtensionStore installedStore;

  final RepoStore repoStore;

  String? _repoUrl;
  List<RepoListing> _listings = const [];
  bool _busy = false;
  String? _error;

  String? get repoUrl => _repoUrl;

  List<RepoListing> get listings => _listings;

  bool get busy => _busy;

  String? get error => _error;

  Future<void> setRepoUrl(String? url) async {
    final trimmed = (url == null || url.trim().isEmpty) ? null : url.trim();
    if (trimmed == _repoUrl) return;
    _repoUrl = trimmed;
    _listings = const [];
    _error = null;
    notifyListeners();
    await repoStore.save(trimmed);
  }

  Future<void> refresh() async {
    final url = _repoUrl;
    if (url == null) {
      _error = 'Set a repo URL first.';
      notifyListeners();
      return;
    }

    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final repo = await installer.fetchRepo(url);
      final installed = await installedStore.loadAll();
      _listings = [
        for (final entry in repo.extensions)
          RepoListing(
            entry: entry,
            installedVersion: installed[entry.id]?.version,
          ),
      ];
      if (_listings.isEmpty) _error = 'This repo lists no extensions.';
    } catch (e) {
      _listings = const [];
      _error = 'Could not read the repo: $e';
    } finally {
      _busy = false;
      notifyListeners();
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

    if (installed != null && newHosts.isEmpty) {
      return granted;
    }

    final accepted = await _requestConsent(
      PermissionRequest(
        entry: entry,
        newHosts: newHosts,
        alreadyGrantedHosts: installed == null
            ? const []
            : granted.where(wanted.contains).toList(),
        isUpdate: installed != null,
      ),
    );
    if (!accepted) return null;
    return {...granted, ...wanted}.toList();
  }

  Future<void> install(ExtensionRepoEntry entry) async {
    _busy = true;
    _error = null;
    notifyListeners();

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
      _error = 'Install failed: $e';
    } finally {
      if (loaded is JsExtension) loaded.dispose();
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> uninstall(String id) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final removed = registry.uninstall(id);
      if (removed is JsExtension) removed.dispose();
      await installedStore.remove(id);
      await refresh();
    } catch (e) {
      _error = 'Uninstall failed: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
