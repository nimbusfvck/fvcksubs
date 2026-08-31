/// Reading HLS playlists, so a seek can be expressed as "start here" instead
/// of "find this timestamp".
///
/// The FFmpeg libmpv is built against — 6.0, and frozen there across every
/// prebuilt Darwin bundle — cannot seek FlyStream's fMP4 renditions. It jumps
/// approximately, then discards packets waiting for a timestamp that never
/// arrives, pulling segment after segment with no picture to show for it.
/// Measured against the same stream: FFmpeg 6.1.6 given a seek produced
/// nothing in 150 seconds, while FFmpeg 9.0.1 finished in five.
///
/// A browser never asks that question. hls.js counts `#EXTINF` durations,
/// fetches the segment covering the moment wanted, re-applies the
/// initialisation segment, and places it on the timeline itself. This is that
/// arithmetic: name the segment, and write a playlist that begins there.
/// Opening *that* asks FFmpeg for nothing but playback from a first fragment,
/// which is the one thing it has always done here — the same 6.1.6 played a
/// cut starting ten minutes in within 1.5 seconds.
library;

/// One `#EXT-X-STREAM-INF` entry and the URI beneath it.
class HlsVariant {
  const HlsVariant({
    required this.url,
    this.height,
    this.width,
    this.audioGroup,
  });

  final Uri url;

  /// From `RESOLUTION`, when the playlist declares one.
  final int? height;

  /// The other half of `RESOLUTION`. It is what names the rendition, since a
  /// wide release letterboxes its height — see `qualityRungLabel`.
  final int? width;

  /// The `AUDIO` group this rendition takes its audio from. A variant without
  /// one carries its audio in its own segments.
  final String? audioGroup;
}

/// One `#EXT-X-MEDIA:TYPE=AUDIO` entry that names a playlist of its own.
class HlsAudioRendition {
  const HlsAudioRendition({
    required this.url,
    required this.groupId,
    this.name,
    this.language,
    this.isDefault = false,
  });

  final Uri url;
  final String groupId;
  final String? name;
  final String? language;
  final bool isDefault;
}

/// What a master playlist offers.
class HlsMaster {
  const HlsMaster({required this.variants, required this.audio});

  static const HlsMaster none = HlsMaster(variants: [], audio: []);

  final List<HlsVariant> variants;
  final List<HlsAudioRendition> audio;

  bool get isMaster => variants.isNotEmpty;

  /// The rendition to cut, under [maxHeight] where one is asked for.
  ///
  /// Mirrors the ceiling the app already applies to libmpv's own track list:
  /// the tallest inside it, and where every rendition is above it, the
  /// smallest rather than silently going over.
  HlsVariant? variantFor(int? maxHeight) {
    if (variants.isEmpty) return null;
    final sorted = [...variants]
      ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    if (maxHeight == null) return sorted.first;
    for (final variant in sorted) {
      final height = variant.height;
      if (height != null && height <= maxHeight) return variant;
    }
    return sorted.last;
  }

  /// The audio rendition belonging to [group], preferring the default one.
  HlsAudioRendition? audioFor(String? group) {
    if (group == null) return null;
    final candidates = audio.where((a) => a.groupId == group).toList();
    if (candidates.isEmpty) return null;
    for (final rendition in candidates) {
      if (rendition.isDefault) return rendition;
    }
    return candidates.first;
  }
}

/// One `#EXTINF` and the URI beneath it.
class HlsSegment {
  const HlsSegment({required this.url, required this.duration});

  final Uri url;
  final Duration duration;
}

/// A media playlist, enough of it to cut one.
class HlsMediaPlaylist {
  const HlsMediaPlaylist({
    required this.segments,
    this.initSegment,
    this.targetDurationSeconds,
    this.version,
  });

  static const HlsMediaPlaylist none = HlsMediaPlaylist(segments: []);

  final List<HlsSegment> segments;

  /// The `#EXT-X-MAP` URI. Every fMP4 segment is undecodable without it, so a
  /// cut that drops it plays nothing at all.
  final Uri? initSegment;

  final int? targetDurationSeconds;
  final int? version;

  bool get isMediaPlaylist => segments.isNotEmpty;

  /// Whether the segments are fMP4 — the packaging this whole path exists
  /// for. Anything else keeps libmpv's own seek, which works.
  bool get isFragmentedMp4 => initSegment != null;

  Duration get totalDuration =>
      segments.fold(Duration.zero, (total, s) => total + s.duration);

  /// The index of the segment covering [position].
  int segmentIndexAt(Duration position) {
    if (position <= Duration.zero || segments.isEmpty) return 0;
    var elapsed = Duration.zero;
    for (var index = 0; index < segments.length; index++) {
      final next = elapsed + segments[index].duration;
      if (next > position) return index;
      elapsed = next;
    }
    return segments.length - 1;
  }

  /// Where the segment at [index] begins, by the playlist's own reckoning.
  Duration startOf(int index) {
    var elapsed = Duration.zero;
    for (var i = 0; i < index && i < segments.length; i++) {
      elapsed += segments[i].duration;
    }
    return elapsed;
  }

  /// Writes a playlist that begins at [index] and runs to the end.
  ///
  /// URIs are written absolute: the cut is opened from a local file, where
  /// anything relative would resolve against that file's own directory.
  String sliceFrom(int index) {
    final start = index.clamp(0, segments.length);
    final buffer = StringBuffer()..writeln('#EXTM3U');
    if (version != null) buffer.writeln('#EXT-X-VERSION:$version');
    if (targetDurationSeconds != null) {
      buffer.writeln('#EXT-X-TARGETDURATION:$targetDurationSeconds');
    }
    buffer.writeln('#EXT-X-MEDIA-SEQUENCE:$start');
    buffer.writeln('#EXT-X-PLAYLIST-TYPE:VOD');
    if (initSegment != null) buffer.writeln('#EXT-X-MAP:URI="$initSegment"');
    for (final segment in segments.skip(start)) {
      final seconds = segment.duration.inMicroseconds / 1000000;
      buffer
        ..writeln('#EXTINF:${seconds.toStringAsFixed(6)},')
        ..writeln(segment.url);
    }
    buffer.writeln('#EXT-X-ENDLIST');
    return buffer.toString();
  }
}

/// Reads [body] as a master playlist, resolving URIs against [base].
HlsMaster parseHlsMaster(String body, {required Uri base}) {
  if (!body.trimLeft().startsWith('#EXTM3U')) return HlsMaster.none;
  final variants = <HlsVariant>[];
  final audio = <HlsAudioRendition>[];
  Map<String, String>? pending;

  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      pending = _attributes(line.substring('#EXT-X-STREAM-INF:'.length));
      continue;
    }
    if (line.startsWith('#EXT-X-MEDIA:')) {
      final attributes = _attributes(line.substring('#EXT-X-MEDIA:'.length));
      final uri = attributes['URI'];
      final group = attributes['GROUP-ID'];
      // A rendition with no playlist of its own lives in the variant's
      // segments; there is nothing separate to cut.
      if (attributes['TYPE'] != 'AUDIO' ||
          uri == null ||
          uri.isEmpty ||
          group == null) {
        continue;
      }
      audio.add(
        HlsAudioRendition(
          url: base.resolve(uri),
          groupId: group,
          name: attributes['NAME'],
          language: attributes['LANGUAGE'],
          isDefault: attributes['DEFAULT']?.toUpperCase() == 'YES',
        ),
      );
      continue;
    }
    if (line.startsWith('#')) continue;
    final attributes = pending;
    pending = null;
    if (attributes == null) continue;
    variants.add(
      HlsVariant(
        url: base.resolve(line),
        height: _dimensionOf(attributes['RESOLUTION'], 1),
        width: _dimensionOf(attributes['RESOLUTION'], 0),
        audioGroup: attributes['AUDIO'],
      ),
    );
  }

  return HlsMaster(variants: variants, audio: audio);
}

/// Reads [body] as a media playlist, resolving URIs against [base].
HlsMediaPlaylist parseHlsMediaPlaylist(String body, {required Uri base}) {
  if (!body.trimLeft().startsWith('#EXTM3U')) return HlsMediaPlaylist.none;
  final segments = <HlsSegment>[];
  Uri? initSegment;
  int? targetDuration;
  int? version;
  Duration? pending;

  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF:')) {
      final value = line.substring('#EXTINF:'.length).split(',').first.trim();
      final seconds = double.tryParse(value);
      pending = seconds == null
          ? null
          : Duration(microseconds: (seconds * 1000000).round());
      continue;
    }
    if (line.startsWith('#EXT-X-MAP:')) {
      final uri = _attributes(line.substring('#EXT-X-MAP:'.length))['URI'];
      if (uri != null && uri.isNotEmpty) initSegment = base.resolve(uri);
      continue;
    }
    if (line.startsWith('#EXT-X-TARGETDURATION:')) {
      targetDuration = int.tryParse(
        line.substring('#EXT-X-TARGETDURATION:'.length).trim(),
      );
      continue;
    }
    if (line.startsWith('#EXT-X-VERSION:')) {
      version = int.tryParse(line.substring('#EXT-X-VERSION:'.length).trim());
      continue;
    }
    if (line.startsWith('#')) continue;
    // A segment with no duration in front of it cannot be placed on the
    // timeline, and a cut computed from a wrong timeline is worse than none.
    if (pending == null) return HlsMediaPlaylist.none;
    segments.add(HlsSegment(url: base.resolve(line), duration: pending));
    pending = null;
  }

  return HlsMediaPlaylist(
    segments: segments,
    initSegment: initSegment,
    targetDurationSeconds: targetDuration,
    version: version,
  );
}

/// Writes a master that plays [videoPlaylist] with [audioPlaylist] beside it.
///
/// Both are named as written, so a caller keeps them in one directory and
/// passes bare file names. Handing FFmpeg a master is what keeps the two in
/// one demuxer, where it aligns them by the timestamps inside the segments —
/// the same way the provider's own master plays in sync today. Attaching the
/// audio from outside instead makes libmpv treat it as a separate stream
/// starting at zero, and two cuts that begin at their own segment boundaries
/// are then seconds apart.
String hlsSliceMaster({
  required String videoPlaylist,
  String? audioPlaylist,
  int? height,
}) {
  final buffer = StringBuffer()
    ..writeln('#EXTM3U')
    ..writeln('#EXT-X-VERSION:7')
    ..writeln('#EXT-X-INDEPENDENT-SEGMENTS');
  if (audioPlaylist != null) {
    buffer.writeln(
      '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Audio",'
      'DEFAULT=YES,AUTOSELECT=YES,URI="$audioPlaylist"',
    );
  }
  // BANDWIDTH is required by the format and read by nothing here: there is
  // only one rendition to choose from.
  buffer
    ..writeln(
      '#EXT-X-STREAM-INF:BANDWIDTH=1'
      // The width is nominal: nothing chooses between renditions here, and a
      // RESOLUTION without one is malformed.
      '${height == null ? '' : ',RESOLUTION=${(height * 16 / 9).round()}x$height'}'
      '${audioPlaylist == null ? '' : ',AUDIO="audio"'}',
    )
    ..writeln(videoPlaylist);
  return buffer.toString();
}

int? _dimensionOf(String? resolution, int index) {
  final parts = resolution?.toLowerCase().split('x');
  return parts == null || parts.length != 2
      ? null
      : int.tryParse(parts[index]);
}

/// Splits an HLS attribute list, keeping commas that sit inside quotes.
Map<String, String> _attributes(String source) {
  final attributes = <String, String>{};
  final buffer = StringBuffer();
  var quoted = false;

  void take() {
    final entry = buffer.toString();
    buffer.clear();
    final split = entry.indexOf('=');
    if (split <= 0) return;
    var value = entry.substring(split + 1).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    attributes[entry.substring(0, split).trim().toUpperCase()] = value;
  }

  for (final rune in source.runes) {
    final character = String.fromCharCode(rune);
    if (character == '"') quoted = !quoted;
    if (character == ',' && !quoted) {
      take();
      continue;
    }
    buffer.write(character);
  }
  take();
  return attributes;
}
