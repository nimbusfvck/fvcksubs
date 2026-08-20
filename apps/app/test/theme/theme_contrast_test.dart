import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/theme/tokens.dart';

void main() {
  group('WCAG AA color contrast', () {
    const darkSurfaces = <Color>[
      AppColors.surfaceDark,
      AppColors.surfaceDarkElevated,
      AppColors.surfaceDarkContainer,
      AppColors.surfaceDarkHighest,
    ];

    test('primary and secondary text pass on every dark surface', () {
      for (final surface in darkSurfaces) {
        expect(_contrast(AppColors.onDark, surface), greaterThanOrEqualTo(4.5));
        expect(
          _contrast(AppColors.onDarkSoft, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('button labels and status text pass on their backgrounds', () {
      expect(
        _contrast(AppColors.onPrimaryAction, AppColors.primaryAction),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(AppColors.primary, AppColors.liveAccent),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('feedback text passes on elevated surfaces', () {
      expect(
        _contrast(AppColors.error, AppColors.surfaceDarkElevated),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(AppColors.success, AppColors.surfaceDarkElevated),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('interactive outlines pass non-text contrast', () {
      for (final surface in darkSurfaces) {
        expect(
          _contrast(AppColors.outlineDark, surface),
          greaterThanOrEqualTo(3),
        );
      }
      expect(
        _contrast(AppColors.brandAccent, AppColors.surfaceDarkElevated),
        greaterThanOrEqualTo(3),
      );
    });
  });
}

double _contrast(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final darker = identical(lighter, first) ? second : first;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
