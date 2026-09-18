import 'package:flutter/material.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;

import 'player_subtitle_style.dart';

/// Renders the safe inline HTML formatting commonly found in subtitle cues.
///
/// Captions are untrusted upstream text. This deliberately supports text
/// formatting only and does not create links, images, or other widgets that
/// could load content outside the subtitle file.
class SubtitleHtmlText extends StatelessWidget {
  const SubtitleHtmlText({super.key, required this.text, this.textStyle});

  final String? text;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final text = this.text;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final style =
        textStyle ??
        DefaultTextStyle.of(
          context,
        ).style.copyWith(fontSize: 36, color: Colors.white);
    final backgroundColor =
        style.backgroundColor ?? playerSubtitleBackgroundColor;
    // Paint the cue background once around the whole caption. A background
    // on TextStyle is painted per glyph/line and creates stacked bands for
    // multiline captions.
    final textOnlyStyle = style.copyWith(backgroundColor: Colors.transparent);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: textOnlyStyle,
                children: subtitleHtmlSpans(text, textOnlyStyle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Parses the inline subset of HTML used by WebVTT and SRT subtitle files.
@visibleForTesting
List<InlineSpan> subtitleHtmlSpans(String source, TextStyle baseStyle) {
  final normalized = normalizeSubtitleMarkup(source);
  try {
    return _spansForNodes(
      html_parser.parseFragment(normalized).nodes,
      baseStyle,
    );
  } catch (_) {
    return [TextSpan(text: normalized)];
  }
}

/// Removes ASS/SSA control blocks before the text is passed to the HTML
/// parser. Position and style overrides are intentionally ignored for now;
/// the player owns one fixed subtitle overlay, so rendering those controls as
/// text would be more confusing than keeping the current placement.
@visibleForTesting
String normalizeSubtitleMarkup(String source) => source
    .replaceAll(RegExp(r'\{\\[^{}\r\n]*\}'), '')
    .replaceAll(RegExp(r'\\[Nn]'), '\n')
    .replaceAll(r'\h', '\u00a0');

List<InlineSpan> _spansForNodes(List<html.Node> nodes, TextStyle style) => [
  for (final node in nodes) ..._spansForNode(node, style),
];

List<InlineSpan> _spansForNode(html.Node node, TextStyle style) {
  if (node is html.Text) return [TextSpan(text: node.data)];
  if (node is! html.Element) return const [];

  final tag = node.localName?.toLowerCase() ?? '';
  if (tag == 'script' || tag == 'style') return const [];
  if (tag == 'br') return const [TextSpan(text: '\n')];

  final elementStyle = _styleForElement(node, style);
  final children = _spansForNodes(node.nodes, elementStyle);
  if (tag == 'p' || tag == 'div' || tag == 'li') {
    return [
      TextSpan(
        style: elementStyle,
        children: [
          ...children,
          const TextSpan(text: '\n'),
        ],
      ),
    ];
  }
  return [TextSpan(style: elementStyle, children: children)];
}

TextStyle _styleForElement(html.Element element, TextStyle parent) {
  var style = parent;
  switch (element.localName?.toLowerCase()) {
    case 'b':
    case 'strong':
      style = style.copyWith(fontWeight: FontWeight.bold);
    case 'i':
    case 'em':
      style = style.copyWith(fontStyle: FontStyle.italic);
    case 'u':
      style = style.copyWith(decoration: TextDecoration.underline);
    case 's':
    case 'strike':
    case 'del':
      style = style.copyWith(decoration: TextDecoration.lineThrough);
    case 'font':
      final color = _htmlColor(element.attributes['color']);
      if (color != null) style = style.copyWith(color: color);
  }

  final inlineStyle = element.attributes['style'];
  if (inlineStyle == null) return style;
  for (final declaration in inlineStyle.split(';')) {
    final colon = declaration.indexOf(':');
    if (colon == -1) continue;
    final name = declaration.substring(0, colon).trim().toLowerCase();
    final value = declaration.substring(colon + 1).trim();
    switch (name) {
      case 'color':
        final color = _htmlColor(value);
        if (color != null) style = style.copyWith(color: color);
      case 'font-style':
        if (value.toLowerCase() == 'italic') {
          style = style.copyWith(fontStyle: FontStyle.italic);
        }
      case 'font-weight':
        if (value.toLowerCase() == 'bold' ||
            (int.tryParse(value) ?? 0) >= 600) {
          style = style.copyWith(fontWeight: FontWeight.bold);
        }
      case 'text-decoration':
        if (value.toLowerCase().contains('underline')) {
          style = style.copyWith(decoration: TextDecoration.underline);
        } else if (value.toLowerCase().contains('line-through')) {
          style = style.copyWith(decoration: TextDecoration.lineThrough);
        }
    }
  }
  return style;
}

Color? _htmlColor(String? value) {
  final color = value?.trim().toLowerCase();
  if (color == null || color.isEmpty) return null;
  final hex = color.startsWith('#') ? color.substring(1) : '';
  if (RegExp(r'^[0-9a-f]{3}$').hasMatch(hex)) {
    final expanded = hex.split('').map((value) => '$value$value').join();
    return Color(int.parse(expanded, radix: 16) | 0xff000000);
  }
  if (RegExp(r'^[0-9a-f]{6}$').hasMatch(hex)) {
    return Color(int.parse(hex, radix: 16) | 0xff000000);
  }
  final rgb = RegExp(
    r'^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$',
  ).firstMatch(color);
  if (rgb != null) {
    final channels = [
      int.parse(rgb.group(1)!),
      int.parse(rgb.group(2)!),
      int.parse(rgb.group(3)!),
    ];
    if (channels.every((channel) => channel <= 255)) {
      return Color.fromARGB(255, channels[0], channels[1], channels[2]);
    }
  }
  return switch (color) {
    'black' => Colors.black,
    'blue' => Colors.blue,
    'cyan' => Colors.cyan,
    'green' => Colors.green,
    'lime' => Colors.lime,
    'magenta' => const Color(0xffff00ff),
    'red' => Colors.red,
    'white' => Colors.white,
    'yellow' => Colors.yellow,
    _ => null,
  };
}
