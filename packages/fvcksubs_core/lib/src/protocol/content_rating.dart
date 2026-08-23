/// Audience classification declared by an extension or one of its catalogs.
///
/// The declaration is a user-facing filter hint, not a security guarantee.
enum ContentRating {
  /// Suitable for the general audience.
  general,

  /// Mature or NSFW content.
  mature,

  /// The extension did not provide a classification.
  unknown,
}

/// Shared policy helpers for audience ratings.
extension ContentRatingPolicy on ContentRating {
  /// Whether this rating is hidden when NSFW content is disabled.
  bool isHiddenWhenNsfwDisabled(bool showNsfw) =>
      !showNsfw && this == ContentRating.mature;
}
