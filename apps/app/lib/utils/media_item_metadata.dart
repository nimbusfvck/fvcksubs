import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:flutter/widgets.dart';

/// Builds compact, app-owned display metadata for cards and detail headers.
String? mediaItemSecondaryText(MediaItemV2 item) {
  final values = [
    if (item.subtitle != null) item.subtitle!,
    if (item.releaseYear != null) item.releaseYear!.toString(),
    if (item.rating != null) '★ ${item.rating!.toStringAsFixed(1)}',
  ];
  return values.isEmpty ? null : values.join(' • ');
}

/// Builds the inline card metadata while keeping the rating star separately
/// styled from the rest of the text.
TextSpan mediaItemSecondarySpan(
  MediaItemV2 item, {
  required TextStyle style,
  required Color ratingColor,
}) {
  final spans = <InlineSpan>[];

  void addSeparator() {
    if (spans.isNotEmpty) spans.add(TextSpan(text: ' • ', style: style));
  }

  if (item.subtitle != null) {
    spans.add(TextSpan(text: item.subtitle, style: style));
  }
  if (item.releaseYear != null) {
    addSeparator();
    spans.add(TextSpan(text: item.releaseYear.toString(), style: style));
  }
  if (item.rating != null) {
    addSeparator();
    spans.add(
      TextSpan(
        text: '★',
        style: style.copyWith(color: ratingColor),
      ),
    );
    spans.add(
      TextSpan(text: ' ${item.rating!.toStringAsFixed(1)}', style: style),
    );
  }

  return TextSpan(children: spans);
}
