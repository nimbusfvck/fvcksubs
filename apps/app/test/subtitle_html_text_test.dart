import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
