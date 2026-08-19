type JsonPrimitive = string | number | boolean | null;
type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue | undefined };

interface MediaRef {
  /** Extension ID from `manifest.json`. Used for routing and saved records; not displayed. */
  extensionId: string;
  /** Manifest provider that owns the item and handles its metadata; not displayed. */
  providerId: string;
  /** Provider-owned stable ID. The host stores and returns it without parsing it. */
  id: string;
}

/**
 * Type of content returned by an extension.
 *
 * - `liveEvent`: scheduled or live event; may show participants, scores, and status.
 * - `channel`: continuously available channel without an episode structure.
 * - `movie`: standalone video displayed with portrait artwork.
 * - `series`: series container whose episodes are supplied by `MediaDetail.seasons`.
 * - `episode`: individual episode when an extension exposes episodes as catalog items.
 */
type MediaKind = 'liveEvent' | 'channel' | 'movie' | 'series' | 'episode';

/**
 * Current state of a scheduled event.
 *
 * - `scheduled`: has not started.
 * - `live`: currently in progress.
 * - `ended`: already finished.
 * - `unknown`: no reliable state is available.
 */
type LiveStatus = 'scheduled' | 'live' | 'ended' | 'unknown';

/**
 * Media format used to configure playback.
 * Use `hls` for M3U8, `dash` for MPD, and `other` when neither applies.
 */
type StreamFormat = 'dash' | 'hls' | 'other';

interface ImageRef {
  /** Absolute image URL. The URL and redirect hosts must be allowed by the manifest. */
  url: string;
}
interface Participant {
  /** Full name shown on event cards and used for source matching. */
  name: string;
  /** Compact card label and alternative matching input. */
  shortName?: string;
  /** Logo shown beside the participant on event cards. */
  logo?: ImageRef;
  /** CSS color used when the app generates fallback event artwork. */
  color?: string;
  /** Display-only score. Use a string to preserve values such as `145/4`. */
  score?: string;
}

interface MediaItem {
  /** Stable identity used for routing, history, and library records. */
  ref: MediaRef;
  /**
   * Content type used by the app to choose its presentation and behavior.
   * For example, `liveEvent` enables event status and participant presentation,
   * while `movie` uses the poster-oriented movie layout.
   */
  kind: MediaKind;
  /** Primary text on cards, details, library entries, and the player. */
  title: string;
  /** Secondary card text, such as a year, competition, or episode name. */
  subtitle?: string;
  /** Portrait artwork used by movie and series cards and the detail header. */
  poster?: ImageRef;
  /** Landscape artwork used by event/channel cards and the detail header. */
  thumbnail?: ImageRef;
  /** ISO-8601 UTC start time used for schedule labels and time-aware matching. */
  startsAt?: string;
  /**
   * Current event state. It controls scheduled/live/ended indicators.
   * Omit it or use `unknown` when the upstream has no reliable state.
   */
  status?: LiveStatus;
  /** Short status text shown verbatim, such as `HT` or `Lap 12/20`. */
  statusLabel?: string;
  /**
   * People or teams taking part in an event.
   * Exactly two entries enable the two-sided event card and name matcher.
   * Omit this field for content that has no participants.
   */
  participants?: Participant[];
  /**
   * Heading used to divide a catalog into sections, such as a competition,
   * genre, or year. Keep items with the same group next to each other because
   * the app preserves the order returned by the extension.
   */
  group?: string;
  /**
   * JSON carried into later extension calls. It is not displayed.
   * Series episode items use `season`, `episode`, and `seriesTitle` keys.
   */
  extra?: Record<string, JsonValue>;
}

interface CatalogQuery {
  /** Provider selected by the host. Matches a provider ID in the manifest. */
  providerId: string;
  /** Catalog selected by the host. Matches a catalog ID in the manifest. */
  catalogId: string;
  /** Selected top-level category ID, or omitted for an unfiltered request. */
  category?: string;
  /** Opaque cursor previously returned as `CatalogPage.nextPage`. */
  page?: string;
  /** Provider-defined filters selected by the user. */
  filters?: Record<string, JsonValue>;
  /** Selected secondary category ID from a previous `subCategories` response. */
  subCategory?: string;
}

interface SubCategory {
  /** Stable value returned in the next `CatalogQuery.subCategory`. */
  id: string;
  /** User-facing selector label. */
  name: string;
}
interface CatalogPage {
  /** Catalog entries in display order. */
  items: MediaItem[];
  /** Opaque cursor for the next page. Omit when there is no next page. */
  nextPage?: string;
  /** Optional secondary category choices displayed by the catalog screen. */
  subCategories?: SubCategory[];
}

interface CastMember {
  /** Person name shown in the detail cast section. */
  name: string;
  /** Role shown below the person's name. */
  character?: string;
  /** Absolute headshot URL shown in the cast section. */
  photoUrl?: string;
}
interface SeriesEpisode {
  /** Primary episode row text. */
  title: string;
  /** Episode synopsis shown in the episode list. */
  description?: string;
  /** Absolute landscape still URL shown in the episode row. */
  thumbnailUrl?: string;
  /** Display-ready duration, such as `57m`. */
  duration?: string;
  /** ISO-8601 air date used to determine whether the episode is available. */
  releaseDate?: string;
}
interface SeriesSeason {
  /** Season number. Use `0` for specials when applicable. */
  number: number;
  /** User-facing season selector label. */
  name: string;
  /** Episodes in display order. */
  episodes?: SeriesEpisode[];
}
interface MediaDetail {
  /** Item displayed in the detail header. Keep the requested `ref` unchanged. */
  item: MediaItem;
  /** Full synopsis shown on the detail page. */
  description?: string;
  /** Genre labels shown in the detail metadata row. */
  genres?: string[];
  /** Runtime shown on movie details, as a whole number of minutes. */
  runtimeMinutes?: number;
  /** Content rating shown in detail metadata, such as `PG-13`. */
  certification?: string;
  /** People shown in the detail cast section, in display order. */
  cast?: CastMember[];
  /**
   * Seasons and episodes displayed on a series detail page.
   * This is normally omitted for movies, channels, and live events.
   */
  seasons?: SeriesSeason[];
  /** Most recently aired season, used as the initial series playback target. */
  lastAiredSeason?: number;
  /** Most recently aired episode. Supply it together with `lastAiredSeason`. */
  lastAiredEpisode?: number;
}

interface StreamSource {
  /**
   * Stable opaque ID passed back to `resolve` when this source is selected.
   * Prefer `fvcksubs.sourceId(providerKey, payload)` instead of a temporary
   * in-memory ID so resolution still works after an app restart.
   */
  id: string;
  /** User-facing source name. Do not expose private upstream identifiers. */
  label: string;
  /** Optional user-facing grouping label in the source picker. */
  provider?: string;
  /**
   * Stable stream provider ID used for enable/disable state and source order.
   * `defineStream` adds it automatically from its registered `providerId`.
   */
  providerId?: string;
}
interface SubtitleTrack {
  /** Language name or code used for display and preferred-subtitle matching. */
  language: string;
  /** Absolute SRT or VTT URL loaded by the player. */
  url: string;
  /** Optional extra display text, such as `Forced` or `SDH`. */
  label?: string;
}
interface DrmConfig {
  /** DRM mode used by the native player. */
  scheme: 'clearKey' | 'widevine' | 'unsupported';
  /** ClearKey JSON object encoded as a string. */
  clearKeyJson?: string;
  /** Widevine licence endpoint. Its host must be allowed by the manifest. */
  licenseUrl?: string;
}
interface PlayableStream {
  /** Final media URL loaded by the player. Resolve expiring URLs as late as possible. */
  url: string;
  /** Headers applied to media requests, including `Referer` when required. */
  headers?: Record<string, string>;
  /** Container/manifest hint used to configure the player. */
  format?: StreamFormat;
  /** Optional ClearKey or Widevine playback configuration. */
  drm?: DrmConfig;
  /** Absolute URL for audio delivered separately from the video. */
  audioUrl?: string;
  /** Resolved quality or rendition text shown by the player. */
  label?: string;
  /** Subtitle tracks offered by this stream. */
  subtitles?: SubtitleTrack[];
}

interface SourcesArgs {
  /** Item for which the app needs playable source choices. */
  item: MediaItem;
  /** Stream provider IDs currently enabled by the user. */
  enabledProviders?: string[];
}
interface SourcesResult {
  /** Cheap, stable source choices. Final URLs belong in `resolve`. */
  sources: StreamSource[];
}
interface SubtitlesResult {
  /** Fallback subtitle tracks merged with subtitles returned by the stream. */
  subtitles: SubtitleTrack[];
}

interface FvcksubsSdk {
  /**
   * Registers one catalog route.
   *
   * Registration fails when the same `providerId` and `catalogId` pair was
   * already registered.
   */
  defineCatalog(definition: {
    providerId: string;
    catalogId: string;
    catalog(query: CatalogQuery): CatalogPage | Promise<CatalogPage>;
  }): void;
  /** Registers the metadata/detail route for a provider. */
  defineMeta(definition: {
    providerId: string;
    meta(args: { ref: MediaRef }): MediaDetail | Promise<MediaDetail>;
  }): void;
  /**
   * Registers source discovery and resolution for a provider.
   *
   * `providerKey` must be unique and must match the key passed to `sourceId`.
   * Discovery failures are isolated so another stream provider can still work.
   * Every returned source receives this registration's `providerId`.
   */
  defineStream(definition: {
    providerId: string;
    providerKey: string;
    sources(args: SourcesArgs): SourcesResult | Promise<SourcesResult>;
    resolve(sourceId: string): PlayableStream | Promise<PlayableStream>;
  }): void;
  /**
   * Registers a search provider. Pages from all search providers are merged,
   * and their cursors are preserved by the SDK.
   */
  defineSearch(definition: {
    providerId: string;
    search(args: { query: string; page?: string }): CatalogPage | Promise<CatalogPage>;
  }): void;
  /** Registers a fallback subtitle provider. Results are merged by the SDK. */
  defineSubtitles(definition: {
    providerId: string;
    subtitles(args: { item: MediaItem }): SubtitlesResult | Promise<SubtitlesResult>;
  }): void;
  /**
   * Creates an opaque, restart-safe source ID containing a JSON payload.
   *
   * @example
   * const id = fvcksubs.sourceId('demo', { contentId: '42' });
   */
  sourceId(providerKey: string, payload: JsonValue): string;
  /**
   * Decodes an ID created by `sourceId`. Supplying the expected key prevents
   * a resolver from accidentally accepting another provider's source.
   */
  sourcePayload<T extends JsonValue = JsonValue>(sourceId: string, expectedProviderKey?: string): T;
}

interface HostApi {
  /** Encoding helpers supplied by the sandbox host. */
  codec: {
    base64ToText(value: string): string;
    textToBase64(value: string): string;
    hexToBase64(value: string): string;
    base64ToHex(value: string): string;
  };
  /** Cryptographic helpers. Binary inputs and outputs use base64 unless noted otherwise. */
  crypto: {
    sha256(value: string): string;
    hmacSha256(key: string, value: string): string;
    xor(a: string, b: string): string;
    aesCbcDecrypt(key: string, iv: string, data: string): string | null;
    aesGcmDecrypt(key: string, nonce: string, data: string): string | null;
  };
  /** Candidate matching supplied by the host. */
  match: {
    resolve(
      query: Record<string, JsonValue>,
      candidates: Record<string, JsonValue>[],
      options?: Record<string, JsonValue>,
    ): { index: number; confidence: number } | null;
  };
}

declare const fvcksubs: FvcksubsSdk;
/** Capabilities exposed by the fvcksubs sandbox. */
declare const host: HostApi;
/**
 * Performs an allowlisted HTTP request. Redirect targets must also appear in
 * `manifest.json.permissions.hosts`.
 */
declare function fetch(
  url: string,
  options?: { method?: string; headers?: Record<string, string>; body?: string },
): Promise<{ status: number; headers: Record<string, string>; url: string; body: string }>;
