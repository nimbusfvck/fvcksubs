/// A small key/value store an extension can keep its own data in.
///
/// The point is *surviving a restart*. A bundle's own globals already cache
/// within a session, and that covers a fan-out or a second visit to the same
/// item; what they cannot do is carry an expensive fetch across app launches.
/// A provider whose upstream is slow (or intermittently down) otherwise has
/// to redo that fetch on every cold start, inside a discovery budget that has
/// no room for it.
///
/// Deliberately synchronous: `__host_call` runs inline on the JS call stack,
/// so an implementation must answer from memory and persist in the
/// background. That shapes what belongs here — small, re-derivable data an
/// extension can do without. Nothing here is a database, and a `read` that
/// comes back null is a normal outcome, never an error.
///
/// Values are opaque strings; an extension that wants structure encodes its
/// own JSON. Each extension gets its own namespace, so keys never collide
/// across bundles and uninstalling one can drop its data wholesale.
abstract interface class ExtensionStorage {
  /// The value stored under [key], or `null` if absent or expired.
  String? read(String key);

  /// Stores [value] under [key].
  ///
  /// [ttl], when given, is how long the value stays readable; after that
  /// [read] reports it as absent. Throws [ExtensionStorageException] if the
  /// value or the store's key count is over the implementation's limits —
  /// callers should treat a failed write as a cache miss, not an error worth
  /// failing a role call over.
  void write(String key, String value, {Duration? ttl});

  /// Drops [key], if it is there.
  void delete(String key);
}

/// Thrown when a write is refused — see [ExtensionStorage.write].
class ExtensionStorageException implements Exception {
  /// Creates the exception.
  ExtensionStorageException(this.message);

  /// What was refused, and why.
  final String message;

  @override
  String toString() => 'ExtensionStorageException: $message';
}

/// An [ExtensionStorage] held entirely in memory.
///
/// Used on its own for tests and for hosts with nowhere to persist; also the
/// base a persistent store builds on, by overriding [persist] to write the
/// same entries out asynchronously and seeding them back with [restore].
///
/// [maxValueBytes] and [maxEntries] are what keep "a cache an extension may
/// use freely" from becoming "however much disk a bundle feels like taking".
/// A write over either limit is refused rather than silently evicting
/// something else: the caller asked to store more than the contract allows,
/// and quietly dropping another extension's — or its own — data to make room
/// would hide that.
class MemoryExtensionStorage implements ExtensionStorage {
  /// Creates the store.
  MemoryExtensionStorage({
    this.maxValueBytes = 512 * 1024,
    this.maxEntries = 32,
  });

  /// Largest single value, in UTF-16 code units.
  final int maxValueBytes;

  /// How many keys one extension may hold.
  final int maxEntries;

  final Map<String, _Entry> _entries = {};

  @override
  String? read(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _entries.remove(key);
      persist();
      return null;
    }
    return entry.value;
  }

  @override
  void write(String key, String value, {Duration? ttl}) {
    if (value.length > maxValueBytes) {
      throw ExtensionStorageException(
        'value for "$key" is ${value.length} bytes, over the '
        '$maxValueBytes-byte limit',
      );
    }
    if (!_entries.containsKey(key) && _entries.length >= maxEntries) {
      throw ExtensionStorageException(
        'storage already holds $maxEntries keys, the limit',
      );
    }
    _entries[key] = _Entry(
      value: value,
      expiresAt: ttl == null ? null : DateTime.now().add(ttl),
    );
    persist();
  }

  @override
  void delete(String key) {
    if (_entries.remove(key) != null) persist();
  }

  /// Every live entry, as JSON-ready maps — what a persistent subclass
  /// writes out.
  Map<String, Object?> snapshot() => {
    for (final entry in _entries.entries)
      if (!entry.value.isExpired) entry.key: entry.value.toJson(),
  };

  /// Loads entries produced by [snapshot], dropping any that expired while
  /// the app was closed. Replaces whatever is held.
  void restore(Map<String, Object?> snapshot) {
    _entries.clear();
    for (final entry in snapshot.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final restored = _Entry.fromJson(value.cast<String, Object?>());
      if (restored == null || restored.isExpired) continue;
      _entries[entry.key] = restored;
    }
  }

  /// Called after every change. The in-memory store has nothing to do;
  /// a persistent one saves [snapshot] here, without blocking the caller.
  void persist() {}
}

class _Entry {
  _Entry({required this.value, required this.expiresAt});

  static _Entry? fromJson(Map<String, Object?> json) {
    final value = json['value'];
    if (value is! String) return null;
    final expiresAt = json['expiresAt'];
    return _Entry(
      value: value,
      expiresAt: expiresAt is String ? DateTime.tryParse(expiresAt) : null,
    );
  }

  final String value;
  final DateTime? expiresAt;

  bool get isExpired {
    final at = expiresAt;
    return at != null && !DateTime.now().isBefore(at);
  }

  Map<String, Object?> toJson() => {
    'value': value,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
  };
}
