import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: '${packageName}_bindings_generated.dart',
      sources: [
        'src/$packageName.c',
        // quickjs-ng core library — see src/quickjs/README (vendoring notes).
        'src/quickjs/quickjs.c',
        'src/quickjs/libregexp.c',
        'src/quickjs/libunicode.c',
        'src/quickjs/dtoa.c',
      ],
      includes: ['src/quickjs'],
      defines: {'_GNU_SOURCE': null},
      flags: ['-lm'],
      std: 'c11',
    );
    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = .ALL
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
