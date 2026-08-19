type JsonPrimitive = string | number | boolean | null;
type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue | undefined };

interface MediaRef {
  /** ID declared by the extension manifest. */
  extensionId: string;
  /** Provider that owns this item and handles its metadata. */
  providerId: string;
  /** Provider-defined stable identifier. */
  id: string;
}

type MediaKind = 'liveEvent' | 'channel' | 'movie' | 'series' | 'episode';
type LiveStatus = 'scheduled' | 'live' | 'ended' | 'unknown';
type StreamFormat = 'dash' | 'hls' | 'other';

interface ImageRef {
  /** Absolute image URL on a host allowed by the manifest. */
  url: string;
}
interface Participant {
  /** Full display name. */
  name: string;
  /** Optional compact name for constrained layouts. */
  shortName?: string;
  logo?: ImageRef;
  /** Optional CSS-style color used to generate fallback artwork. */
  color?: string;
  score?: string;
}

interface MediaItem {
  /** Stable identity used for routing, history, and library records. */
  ref: MediaRef;
  kind: MediaKind;
  title: string;
  subtitle?: string;
  poster?: ImageRef;
  thumbnail?: ImageRef;
  /** ISO 8601 timestamp. */
  startsAt?: string;
  /** ISO 8601 timestamp. */
  endsAt?: string;
  status?: LiveStatus;
  statusLabel?: string;
  participants?: Participant[];
  badges?: string[];
  group?: string;
  /** Provider-owned JSON data forwarded to source discovery. */
  extra?: Record<string, JsonValue>;
}

interface CatalogQuery {
  /** Provider selected by the host. */
  providerId: string;
  /** Catalog ID declared in the manifest. */
  catalogId: string;
  category?: string;
  /** Opaque cursor previously returned as `CatalogPage.nextPage`. */
  page?: string;
  filters?: Record<string, JsonValue>;
  subCategory?: string;
}

interface SubCategory { id: string; name: string; }
interface CatalogPage {
  items: MediaItem[];
  /** Opaque cursor for the next page. Omit when there is no next page. */
  nextPage?: string;
  subCategories?: SubCategory[];
}

interface CastMember { name: string; character?: string; photoUrl?: string; }
interface SeriesEpisode {
  title: string;
  description?: string;
  thumbnailUrl?: string;
  duration?: string;
  releaseDate?: string;
}
interface SeriesSeason { number: number; name: string; episodes?: SeriesEpisode[]; }
interface MediaDetail {
  item: MediaItem;
  description?: string;
  tagline?: string;
  genres?: string[];
  runtimeMinutes?: number;
  certification?: string;
  networks?: string[];
  cast?: CastMember[];
  seasons?: SeriesSeason[];
  lastAiredSeason?: number;
  lastAiredEpisode?: number;
}

interface StreamSource {
  /** Opaque ID routed back to the registered stream resolver. */
  id: string;
  /** User-facing source name. Do not expose private upstream identifiers. */
  label: string;
  /** Optional user-facing provider name. */
  provider?: string;
}
interface SubtitleTrack {
  /** Language name or code shown by the player. */
  language: string;
  /** Absolute subtitle URL. */
  url: string;
  label?: string;
}
interface DrmConfig {
  scheme: 'clearKey' | 'widevine' | 'unsupported';
  /** ClearKey JSON object encoded as a string. */
  clearKeyJson?: string;
  licenseUrl?: string;
}
interface PlayableStream {
  /** Absolute media URL. */
  url: string;
  /** Headers applied to media requests. */
  headers?: Record<string, string>;
  format?: StreamFormat;
  drm?: DrmConfig;
  audioUrl?: string;
  label?: string;
  subtitles?: SubtitleTrack[];
}

interface SourcesArgs { item: MediaItem; enabledProviders?: string[]; }
interface SourcesResult { sources: StreamSource[]; }
interface SubtitlesResult { subtitles: SubtitleTrack[]; }

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
