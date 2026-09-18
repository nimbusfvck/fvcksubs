import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/player/state/subtitle_preference_controller.dart';
import 'package:fvcksubs_app/player/widgets/subtitle_html_text.dart';

void main() {
  test('preserves text and renders inline HTML tags as spans', () {
    final spans = subtitleHtmlSpans(
      '<i>Hello</i> <b>world</b><br><font color="#ff0000">red</font>',
      const TextStyle(color: Colors.white),
    );

    expect(TextSpan(children: spans).toPlainText(), 'Hello world\nred');
    expect((spans[0] as TextSpan).style?.fontStyle, FontStyle.italic);
    expect((spans[2] as TextSpan).style?.fontWeight, FontWeight.bold);
    expect((spans[4] as TextSpan).style?.color, const Color(0xffff0000));
  });

  test('decodes HTML entities and does not render script contents', () {
    final spans = subtitleHtmlSpans(
      'Rock &amp; roll<script>ignored()</script>',
      const TextStyle(),
    );

    expect(TextSpan(children: spans).toPlainText(), 'Rock & roll');
  });

  test('cleans ASS override tags and escaped line breaks', () {
    final spans = subtitleHtmlSpans(
      r'{\an8}<i>Top</i>\N{\pos(10,20)}Bottom\hline',
      const TextStyle(),
    );

    expect(TextSpan(children: spans).toPlainText(), 'Top\nBottom\u00a0line');
  });

  test('keeps ordinary braces that are part of subtitle text', () {
    final spans = subtitleHtmlSpans('Use {this} exactly', const TextStyle());

    expect(TextSpan(children: spans).toPlainText(), 'Use {this} exactly');
  });

  testWidgets('multiline captions use one shared background', (tester) async {
    const background = Color(0xbb10243d);
    await tester.pumpWidget(
      const MaterialApp(
        home: SubtitleHtmlText(
          text: 'First line\nSecond line',
          textStyle: TextStyle(
            color: Colors.white,
            backgroundColor: background,
          ),
        ),
      ),
    );

    expect(find.byType(DecoratedBox), findsOneWidget);
    final richText = tester.widget<RichText>(find.byType(RichText));
    final text = richText.text as TextSpan;
    expect(text.style?.backgroundColor, Colors.transparent);
    expect(
      text.children!.every(
        (span) => (span as TextSpan).style?.backgroundColor != background,
      ),
      isTrue,
    );
  });

  test('normalizes legacy dark subtitle backgrounds', () {
    expect(
      normalizedSubtitleBackgroundColor(const Color(0xaa000000)),
      const Color(0x88000000),
    );
    expect(
      normalizedSubtitleBackgroundColor(const Color(0xdd151515)),
      const Color(0xbb151515),
    );
    expect(
      normalizedSubtitleBackgroundColor(const Color(0xdd10243d)),
      const Color(0xbb10243d),
    );
  });
}
