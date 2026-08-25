import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/widgets/media_kit_player.dart';
import 'package:fvcksubs_app/player/widgets/player_subtitle_style.dart';

void main() {
  test('deferred subtitle retries after a failed first attempt', () {
    expect(
      shouldApplyDeferredSubtitle(
        mounted: true,
        expectedRevision: 1,
        currentRevision: 1,
      ),
      isTrue,
    );
  });

  test('deferred subtitle does not overwrite a newer user selection', () {
    expect(
      shouldApplyDeferredSubtitle(
        mounted: true,
        expectedRevision: 1,
        currentRevision: 2,
      ),
      isFalse,
    );
    expect(
      shouldApplyDeferredSubtitle(
        mounted: false,
        expectedRevision: 1,
        currentRevision: 1,
      ),
      isFalse,
    );
  });

  test('subtitle appearance is shared by native backends', () {
    expect(playerSubtitleFontSize, 24);
    expect(playerSubtitleTextStyle.fontSize, playerSubtitleFontSize);
    expect(
      playerSubtitleTextStyle.backgroundColor,
      playerSubtitleBackgroundColor,
    );
  });
}
