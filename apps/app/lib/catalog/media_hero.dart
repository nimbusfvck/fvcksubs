import 'package:fvcksubs_core/fvcksubs_core.dart';

/// Stable shared-element tag for an item's primary artwork.
String mediaArtworkHeroTag(MediaRef ref) =>
    'media-artwork:${ref.extensionId}:${ref.providerId}:${ref.id}';
