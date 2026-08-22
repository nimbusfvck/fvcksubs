import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

const int _maximumClassLines = 500;
const List<String> _sourceRoots = ['apps', 'packages'];

void main() {
  final violations = <String>[];
  for (final file in _dartSourceFiles()) {
    final result = parseFile(
      path: file.path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    final lineInfo = result.lineInfo;
    for (final declaration in result.unit.declarations) {
      if (declaration is! ClassDeclaration) continue;
      final start = lineInfo.getLocation(declaration.offset).lineNumber;
      final end = lineInfo.getLocation(declaration.end).lineNumber;
      final length = end - start + 1;
      if (length <= _maximumClassLines) continue;
      violations.add(
        '${file.path}:$start ${declaration.namePart.typeName.lexeme} '
        'is $length lines (maximum $_maximumClassLines).',
      );
    }
  }

  if (violations.isEmpty) return;
  stderr.writeln('Class-size limit exceeded:');
  for (final violation in violations) {
    stderr.writeln('- $violation');
  }
  exitCode = 1;
}

Iterable<File> _dartSourceFiles() sync* {
  for (final root in _sourceRoots) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (!entity.path.contains(
        '${Platform.pathSeparator}lib${Platform.pathSeparator}',
      )) {
        continue;
      }
      yield entity;
    }
  }
}
