/// Content model, extension protocol, and matcher for fvcksubs.
///
/// Everything that crosses the extension boundary is JSON. These types define
/// the Dart representation shared by the application and extension host.
library;

export 'src/content/image_ref.dart';
export 'src/content/media_detail_v2.dart';
export 'src/content/media_item_v2.dart';
export 'src/content/media_item_version_adapter.dart';
export 'src/content/media_ref.dart';
export 'src/content/participant.dart';
export 'src/content/preview_source.dart';
export 'src/content/stream.dart';
export 'src/matcher/event_match_resolver.dart';
export 'src/matcher/jaro_winkler.dart';
export 'src/matcher/normalization_profile.dart';
export 'src/matcher/team_name_normalizer.dart';
export 'src/protocol/catalog.dart';
export 'src/protocol/catalog_v2.dart';
export 'src/protocol/content_extension.dart';
export 'src/protocol/content_rating.dart';
export 'src/protocol/extension_repo.dart';
export 'src/protocol/installed_extension.dart';
export 'src/protocol/manifest.dart';
