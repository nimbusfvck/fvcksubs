import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../models/resolved_source.dart';

/// The one last-used resolved VOD source retained for a warm resume.
class ResolvedPlaybackCacheRecord {
  const ResolvedPlaybackCacheRecord({
    required this.ref,
    required this.resolved,
  });

  factory ResolvedPlaybackCacheRecord.fromJson(Map<String, Object?> json) {
    final resolved = json['resolved']! as Map<String, Object?>;
    return ResolvedPlaybackCacheRecord(
      ref: MediaRef.fromJson(json['ref']! as Map<String, Object?>),
      resolved: ResolvedSource(
        source: StreamSource.fromJson(
          resolved['source']! as Map<String, Object?>,
        ),
        stream: PlayableStream.fromJson(
          resolved['stream']! as Map<String, Object?>,
        ),
      ),
    );
  }

  final MediaRef ref;
  final ResolvedSource resolved;
  Map<String, Object?> toJson() => {
    'ref': ref.toJson(),
    'resolved': {
      'source': resolved.source.toJson(),
      'stream': resolved.stream.toJson(),
    },
  };
}

abstract interface class ResolvedPlaybackCacheStore {
  Future<ResolvedPlaybackCacheRecord?> load();

  Future<void> save(ResolvedPlaybackCacheRecord? record);
}

/// Stores only the single last-used resolved VOD source in secure storage.
///
/// Stream URLs and request headers can contain short-lived credentials, so
/// this cache must not use the plain-text source-list preferences store.
class SecureResolvedPlaybackCacheStore implements ResolvedPlaybackCacheStore {
  SecureResolvedPlaybackCacheStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'player.lastResolvedPlayback.v1';
  static const int _maxEncodedBytes = 512 * 1024;

  final FlutterSecureStorage _storage;

  @override
  Future<ResolvedPlaybackCacheRecord?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final record = ResolvedPlaybackCacheRecord.fromJson(
        decoded.cast<String, Object?>(),
      );
      return record.resolved.hasAbsoluteHttpUrl ? record : null;
    } on Object {
      // Corrupt or outdated cache data is only a missed optimization.
      return null;
    }
  }

  @override
  Future<void> save(ResolvedPlaybackCacheRecord? record) async {
    if (record == null || !record.resolved.hasAbsoluteHttpUrl) {
      await _storage.delete(key: _key);
      return;
    }
    final encoded = jsonEncode(record.toJson());
    if (utf8.encode(encoded).length > _maxEncodedBytes) {
      await _storage.delete(key: _key);
      return;
    }
    await _storage.write(key: _key, value: encoded);
  }
}

class NoopResolvedPlaybackCacheStore implements ResolvedPlaybackCacheStore {
  const NoopResolvedPlaybackCacheStore();

  @override
  Future<ResolvedPlaybackCacheRecord?> load() async => null;

  @override
  Future<void> save(ResolvedPlaybackCacheRecord? record) async {}
}
