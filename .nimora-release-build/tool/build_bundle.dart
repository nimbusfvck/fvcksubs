import 'dart:io';

const fullSources = [
  'fixtures.js',
  'alias.js',
  // Stream providers lead, in the order the app should try them: the
  // aggregator concatenates each provider's list in registration order and
  // nothing downstream re-sorts.
  //
  // VaPlayer and vidrock first because their streams seek and switch tracks
  // through libmpv's own path. FlyStream's renditions are fMP4, which the
  // bundled FFmpeg cannot seek without the player's cut-playlist workaround
  // — worth reaching for its 4K ladder, not worth defaulting to. VidEasy
  // last of the four: most of its sources fail to resolve, and two of them
  // spend ten seconds doing it.
  'vaplayer.js',
  'vidrock.js',
  'flystream.js',
  'videasy.js',
  'kora.js',
  'moviebox.js',
  'idlix.js',
  'cricfy_cipher.js',
  'cricfy.js',
  'metegol.js',
  'tmdb.js',
  'uefa_shorts.js',
  'clipro_shorts.js',
  'shegu.js',
  'sokuja.js',
  'indomax.js',
  'dramadev.js',
  'shorts_feed.js',
  'savefilm.js',
  'layarkaca.js',
  'anilist.js',
  'skip_intro.js',
  'timesoccer.js',
  'playz.js',
  'roxie.js',
  'cdnlivetv.js',
  'league_channels.js',
];

const compactSources = [
  'fixtures.js',
  'alias.js',
  'vaplayer.js',
  'vidrock.js',
  'videasy.js',
  'moviebox.js',
  'idlix.js',
  'cricfy_cipher.js',
  'cricfy.js',
  'tmdb.js',
  'uefa_shorts.js',
  'clipro_shorts.js',
  'shegu.js',
  'sokuja.js',
  'dramadev.js',
  'layarkaca.js',
  'anilist.js',
  'skip_intro.js',
  'shorts_feed.js',
  'playz.js',
  'roxie.js',
  'cdnlivetv.js',
  'league_channels.js',
];

List<String> sourcesForProfile(String profile) => switch (profile) {
  'full' => fullSources,
  'compact' => compactSources,
  _ => throw ArgumentError('Unknown bundle profile: $profile'),
};

String buildBundle({
  String profile = 'full',
  String? outputPath,
  String? rootPath,
}) {
  final root = rootPath == null
      ? Directory.fromUri(Platform.script.resolve('../'))
      : Directory(rootPath);
  final libDir = Directory('${root.path}/lib');
  final extensionPrefix = profile == 'compact'
      ? "globalThis.__nimoraExtensionId = 'nimora.compact';\n"
      : '';
  final sources = sourcesForProfile(profile);
  final bundle =
      extensionPrefix +
      sources
          .map((name) => File('${libDir.path}/$name').readAsStringSync())
          .join('\n');
  File(outputPath ?? '${libDir.path}/bundle.js').writeAsStringSync(bundle);
  return bundle;
}

void main(List<String> arguments) {
  final profile = _option(arguments, '--profile') ?? 'full';
  final bundle = buildBundle(profile: profile);
  stdout.writeln(
    'Built lib/bundle.js profile=$profile from '
    '${sourcesForProfile(profile).length} sources '
    '(${bundle.length} bytes).',
  );
}

String? _option(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1) return null;
  if (index + 1 >= arguments.length) {
    throw ArgumentError('Missing value for $name');
  }
  return arguments[index + 1];
}
