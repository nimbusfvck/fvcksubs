import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'build_bundle.dart';

void main(List<String> arguments) {
  final profile = _option(arguments, '--profile') ?? 'full';
  final defaultBaseUrl = profile == 'full'
      ? 'http://127.0.0.1:8080'
      : 'http://127.0.0.1:8080/$profile';
  final baseUrl = _option(arguments, '--base-url') ?? defaultBaseUrl;
  final root = Directory.fromUri(Platform.script.resolve('..'));
  final lib = Directory('${root.path}/lib');
  final dist = Directory(
    profile == 'full' ? '${root.path}/dist' : '${root.path}/dist/$profile',
  )..createSync(recursive: true);

  final manifestFile = profile == 'full'
      ? 'manifest.json'
      : 'manifest_$profile.json';
  final releaseFile = profile == 'full'
      ? 'release.json'
      : 'release_$profile.json';
  final bundle = buildBundle(
    profile: profile,
    outputPath: '${dist.path}/bundle.js',
  );
  final manifestText = File('${lib.path}/$manifestFile').readAsStringSync();
  final manifest = jsonDecode(manifestText) as Map<String, Object?>;
  final release =
      jsonDecode(File('${root.path}/$releaseFile').readAsStringSync())
          as Map<String, Object?>;
  final releaseNotes =
      (release['releaseNotes'] as List<Object?>?)
          ?.whereType<String>()
          .where((note) => note.trim().isNotEmpty)
          .toList() ??
      const <String>[];
  final bundleBytes = utf8.encode(bundle);

  File('${dist.path}/manifest.json').writeAsStringSync(manifestText);
  File('${dist.path}/bundle.js').writeAsBytesSync(bundleBytes);
  File('${dist.path}/repo.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'extensions': [
        {'id': manifest['id'], 'name': manifest['name'], 'version': manifest['version'], 'description': manifest['description'], 'author': manifest['author'], 'hosts': (manifest['permissions'] as Map)['hosts'], 'releaseNotes': releaseNotes, 'manifestUrl': '$baseUrl/manifest.json', 'bundleUrl': '$baseUrl/bundle.js', 'bundleSha256': sha256.convert(bundleBytes).toString()},
      ],
    })}\n',
  );

  stdout.writeln('Release written to ${dist.path}');
}

String? _option(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1) return null;
  if (index + 1 >= arguments.length) {
    throw ArgumentError('Missing value for $name');
  }
  return arguments[index + 1].replaceAll(RegExp(r'/+$'), '');
}
