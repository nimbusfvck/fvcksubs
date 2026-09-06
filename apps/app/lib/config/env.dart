import 'package:envied/envied.dart';

part 'env.g.dart';

/// Build-time secrets loaded from apps/app/.env by Envied.
@Envied(allowOptionalFields: true)
abstract class AppEnv {
  @EnviedField(varName: 'OPENSUBTITLES_API_KEY', optional: true)
  static const String? openSubtitlesApiKey = _AppEnv.openSubtitlesApiKey;
}
