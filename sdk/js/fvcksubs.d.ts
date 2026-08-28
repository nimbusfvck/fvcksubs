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

/** Selects the protocol shape and behavior of an item. */
type MediaKind = 'video' | 'series' | 'episode' | 'channel' | 'event';

/**
 * Current state of a scheduled event.
 *
 * - `scheduled`: has not started.
 * - `live`: currently in progress.
 * - `ended`: already finished.
 * - `unknown`: no reliable state is available.
 */
type ScheduleState = 'scheduled' | 'live' | 'ended' | 'unknown';

/**
 * Media format used to configure playback.
 * Use `hls` for M3U8, `dash` for MPD, and `other` when neither applies.
 */
type StreamFormat = 'dash' | 'hls' | 'other';

interface ImageRef {
  /** Absolute image URL. The URL and redirect hosts must be allowed by the manifest. */
  url: string;
}

interface Artwork {
  /** Portrait image used by narrow cards and portrait layouts. */
  portrait?: ImageRef;
  /** Landscape image used by wide cards and detail headers. */
  landscape?: ImageRef;
  /**
   * Transparent title or brand mark. Featured video and series heroes show
   * this instead of the text title. Live fallback artwork uses it as the
   * centered identity when no participant logo is available.
   */
  logo?: ImageRef;
}

interface Schedule {
  /** ISO-8601 UTC start time, for example `2026-08-19T12:30:00Z`. */
  startsAt: string;
  /** Machine-readable lifecycle state used for event indicators. */
  state?: ScheduleState;
  /** Optional short display text supplied verbatim by the extension. */
  label?: string;
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

interface MediaBase {
  /** Stable identity used for routing, history, and library records. */
  ref: MediaRef;
  kind: MediaKind;
  /** Primary text on cards, details, library entries, and the player. */
  title: string;
  /** Descriptive secondary text, such as a competition or episode name. */
  subtitle?: string;
  /** Calendar year in which this item was first released. */
  releaseYear?: number;
  /** Audience or editorial rating. The SDK does not impose a rating scale. */
  rating?: number;
  /** Shape-specific images used by cards and detail layouts. */
  artwork?: Artwork;
}

interface VideoItem extends MediaBase { kind: 'video'; }
interface SeriesItem extends MediaBase { kind: 'series'; }
interface ChannelItem extends MediaBase { kind: 'channel'; }

interface EpisodeIdentity {
  /** Stable reference of the series or collection containing this episode. */
  parentRef: MediaRef;
  /** Opaque group ID matching an `EpisodeGroup.id`. */
  groupId: string;
  /** One-based display position inside the group. */
  position: number;
}

interface EpisodeItem extends MediaBase {
  kind: 'episode';
  /** Typed navigation context. The item's own `ref` must identify the episode. */
  episode: EpisodeIdentity;
}

interface EventItem extends MediaBase {
  kind: 'event';
  /** Required timing and lifecycle data for the event. */
  schedule: Schedule;
  /** Optional participants in display order. */
  participants?: Participant[];
}

type MediaItem = VideoItem | SeriesItem | EpisodeItem | ChannelItem | EventItem;

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
  /** Explicit groups rendered in order. At least one section is expected. */
  sections: CatalogSection[];
  /** Opaque cursor for the next page. Omit when there is no next page. */
  nextPage?: string;
  /** Optional secondary category choices displayed by the catalog screen. */
  subCategories?: SubCategory[];
}

interface CatalogSection {
  /** Stable opaque ID used when paginated pages are merged. */
  id: string;
  /** Optional heading shown above the section. */
  title?: string;
  /** Entries rendered in order inside this section. */
  items: MediaItem[];
}

interface Fact {
  /** Short label shown beside the value. */
  label: string;
  /** Display-ready value; the app does not parse it. */
  value: string;
}

interface Credit {
  /** Person or entity name shown in the credits section. */
  name: string;
  /** Optional contribution or role shown below the name. */
  role?: string;
  /** Optional profile image. */
  image?: ImageRef;
}

interface Trailer {
  /** User-facing preview title, such as `Official Trailer`. */
  title: string;
  /** Absolute URL opened when the user selects the trailer. */
  url: string;
  /** Optional platform label, such as `YouTube`. */
  site?: string;
  /** Optional preview image shown beside the trailer action. */
  thumbnail?: ImageRef;
  /** Optional MIME type; `video/*` allows the app to autoplay `url` in the detail header. */
  mimeType?: string;
}

interface EpisodeSummary {
  /** Stable episode identity used by metadata, source, subtitle, and history calls. */
  ref: MediaRef;
  /** Primary episode row text. */
  title: string;
  /** One-based episode position displayed inside its group. */
  position: number;
  /** Optional synopsis shown in the episode list. */
  description?: string;
  /** Optional episode-specific artwork. */
  artwork?: Artwork;
  /** Optional positive runtime in seconds. */
  durationSeconds?: number;
  /** Optional ISO-8601 UTC release or availability time. */
  availableAt?: string;
}

interface EpisodeGroup {
  /** Stable opaque ID used by episode identities. */
  id: string;
  /** User-facing selector label. */
  title: string;
  /** Episodes in display order. */
  episodes: EpisodeSummary[];
}

interface EpisodeGuide {
  /** Extension-defined groups such as seasons, volumes, or years. */
  groups: EpisodeGroup[];
  /** Episode used by the primary Play action; must exist in `groups`. */
  defaultEpisodeRef?: MediaRef;
}

interface MediaDetail {
  /** Item displayed in the detail header. Keep the requested `ref` unchanged. */
  item: MediaItem;
  /** Full synopsis shown on the detail page. */
  description?: string;
  /** Short classification labels displayed in extension-provided order. */
  tags?: string[];
  /** Labelled display metadata such as runtime, year, or rating. */
  facts?: Fact[];
  /** Credited people or entities in display order. */
  credits?: Credit[];
  /** Preview videos shown in the detail page's trailer section. */
  trailers?: Trailer[];
  /** Related items shown in a recommendation shelf at the bottom of detail. */
  recommendations?: MediaItem[];
  /** Optional typed navigation data for episodic content. */
  episodeGuide?: EpisodeGuide;
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

interface EmbeddedPreviewSource {
  /** Opaque source ID. */
  id: string;
  type: 'embedded';
  /**
   * Embed provider (e.g. `'youtube'`). A provider the app doesn't have an
   * adapter for is still accepted here — the SDK does not validate this
   * against a known list — but the app will skip it at render time.
   */
  provider: string;
  /** Provider-scoped media ID (a YouTube video ID, for `'youtube'`). */
  mediaId: string;
}
interface DirectPreviewSource {
  /** Opaque source ID. */
  id: string;
  type: 'direct';
  /** Directly playable stream. */
  stream: PlayableStream;
}
/** One preview candidate, in the extension's preferred order. */
type PreviewSource = EmbeddedPreviewSource | DirectPreviewSource;
interface PreviewResult {
  /**
   * Candidate sources, in preferred order. Empty means no usable preview
   * was found for this item. Never persisted by the app — resolve every
   * time playback is about to start.
   */
  sources: PreviewSource[];
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
   *
   * `args.category` is the scope the user picked, when they picked one. It is
   * absent for an unscoped search — which is also what an older host sends, so
   * absence must mean "search everything", never "not selected".
   */
  defineSearch(definition: {
    providerId: string;
    search(args: {
      query: string;
      page?: string;
      category?: string;
    }): CatalogPage | Promise<CatalogPage>;
  }): void;
  /** Registers a fallback subtitle provider. Results are merged by the SDK. */
  defineSubtitles(definition: {
    providerId: string;
    subtitles(args: { item: MediaItem }): SubtitlesResult | Promise<SubtitlesResult>;
  }): void;
  /**
   * Registers a just-in-time preview provider (e.g. for a Shorts feed card).
   *
   * Entirely optional — call it only when this extension actually produces
   * previews. Preview and full playback are separate workflows: a returned
   * source is never a substitute for `defineStream`'s `sources`/`resolve`.
   */
  definePreview(definition: {
    providerId: string;
    preview(item: MediaItem): PreviewResult | Promise<PreviewResult>;
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
