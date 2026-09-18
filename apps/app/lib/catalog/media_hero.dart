import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

/// Stable shared-element tag for an item's primary artwork.
String mediaArtworkHeroTag(MediaRef ref) =>
    'media-artwork:${ref.extensionId}:${ref.providerId}:${ref.id}';

Widget mediaArtworkFlightShuttleBuilder(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) => (fromHeroContext.widget as Hero).child;
