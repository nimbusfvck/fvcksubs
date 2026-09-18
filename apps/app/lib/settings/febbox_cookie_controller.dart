import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

abstract interface class FebboxCookieStore {
  Future<String?> read();

  Future<void> write(String? value);
}

class SecureFebboxCookieStore implements FebboxCookieStore {
  SecureFebboxCookieStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'showbox.febbox.ui';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: _key);
      return;
    }
    await _storage.write(key: _key, value: value);
  }
}

String? normalizeFebboxCookie(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  if (value.contains('\r') || value.contains('\n')) {
    throw const FormatException('Cookie must be a single line.');
  }

  final withoutName = value.startsWith('ui=') ? value.substring(3) : value;
  final cookieValue = withoutName.split(';').first.trim();
  return cookieValue.isEmpty ? null : cookieValue;
}

class FebboxCookieController extends ChangeNotifier {
  FebboxCookieController({
    required FebboxCookieStore store,
    String? initial,
    Future<void> Function(String? cookie)? onChanged,
  }) : _store = store,
       _cookie = initial,
       _onChanged = onChanged;

  final FebboxCookieStore _store;
  final Future<void> Function(String? cookie)? _onChanged;
  String? _cookie;
  bool _saving = false;
  String? _error;

  String? get cookie => _cookie;

  bool get hasCookie => _cookie != null;

  bool get saving => _saving;

  String? get error => _error;

  Future<bool> save(String raw) async {
    try {
      return await _set(normalizeFebboxCookie(raw));
    } on FormatException catch (error) {
      _error = error.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> clear() => _set(null);

  Future<bool> _set(String? value) async {
    if (_saving) return false;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await _store.write(value);
      _cookie = value;
      notifyListeners();
      await _onChanged?.call(value);
      return true;
    } on Object catch (error) {
      // Do not include the cookie in an error surfaced to the UI or logs.
      _error = 'Could not save the Febbox cookie: $error';
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}

String febboxExtensionPrelude(Manifest manifest, String? cookie) {
  if (manifest.id != 'nimora' && manifest.id != 'nimora.compact') {
    return '';
  }
  return 'globalThis.__showboxUiCookie = ${jsonEncode(cookie)};';
}
