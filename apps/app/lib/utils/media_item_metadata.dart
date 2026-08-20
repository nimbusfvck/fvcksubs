import 'package:fvcksubs_core/fvcksubs_core.dart';

/// Builds compact, app-owned display metadata for cards and detail headers.
String? mediaItemSecondaryText(MediaItemV2 item) {
  final values = [
    if (item.subtitle != null) item.subtitle!,
    if (item.releaseYear != null) item.releaseYear!.toString(),
    if (item.rating != null) '★ ${item.rating}',
  ];
  return values.isEmpty ? null : values.join(' • ');
}
