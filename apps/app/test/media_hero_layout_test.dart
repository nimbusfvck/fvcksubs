import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/widgets/media_hero_layout.dart';

void main() {
  test('uses the taller shared poster treatment on narrow screens', () {
    expect(
      MediaHeroLayout.heightForViewport(const Size(390, 844)),
      closeTo(546, 0.01),
    );
  });

  test('keeps wide-screen heroes within shared height bounds', () {
    expect(
      MediaHeroLayout.heightForViewport(const Size(1000, 800)),
      MediaHeroLayout.wideMinHeight,
    );
    expect(
      MediaHeroLayout.heightForViewport(const Size(1200, 1000)),
      MediaHeroLayout.wideMaxHeight,
    );
  });

  test('keeps Home overlays until the hero is nearly collapsed', () {
    expect(MediaHeroLayout.homeOverlayOpacity(0, maxCollapse: 442), 1);
    expect(MediaHeroLayout.homeOverlayOpacity(406, maxCollapse: 442), 0.5);
    expect(MediaHeroLayout.homeOverlayOpacity(442, maxCollapse: 442), 0);
    expect(MediaHeroLayout.homeOverlayOpacity(500, maxCollapse: 442), 0);
  });
}
