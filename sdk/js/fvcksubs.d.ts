type JsonPrimitive = string | number | boolean | null;
type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue | undefined };

interface MediaRef {
  extensionId: string;
  providerId: string;
  id: string;
}

type MediaKind = 'liveEvent' | 'channel' | 'movie' | 'series' | 'episode';
type LiveStatus = 'scheduled' | 'live' | 'ended' | 'unknown';
type StreamFormat = 'dash' | 'hls' | 'other';

interface ImageRef { url: string; }
interface Participant {
  name: string;
  shortName?: string;
  logo?: ImageRef;
  color?: string;
  score?: string;
}

interface MediaItem {
  ref: MediaRef;
  kind: MediaKind;
  title: string;
  subtitle?: string;
  poster?: ImageRef;
  thumbnail?: ImageRef;
  startsAt?: string;
  endsAt?: string;
  status?: LiveStatus;
  statusLabel?: string;
  participants?: Participant[];
  badges?: string[];
  group?: string;
  extra?: Record<string, JsonValue>;
}

interface CatalogQuery {
  providerId: string;
  catalogId: string;
  category?: string;
  page?: string;
  filters?: Record<string, JsonValue>;
  subCategory?: string;
}

interface SubCategory { id: string; name: string; }
interface CatalogPage {
  items: MediaItem[];
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

interface StreamSource { id: string; label: string; provider?: string; }
interface SubtitleTrack { language: string; url: string; label?: string; }
interface DrmConfig {
  scheme: 'clearKey' | 'widevine' | 'unsupported';
  clearKeyJson?: string;
  licenseUrl?: string;
}
interface PlayableStream {
  url: string;
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
  defineCatalog(definition: {
    providerId: string;
    catalogId: string;
    catalog(query: CatalogQuery): CatalogPage | Promise<CatalogPage>;
  }): void;
  defineMeta(definition: {
    providerId: string;
    meta(args: { ref: MediaRef }): MediaDetail | Promise<MediaDetail>;
  }): void;
  defineStream(definition: {
    providerId: string;
    providerKey: string;
    sources(args: SourcesArgs): SourcesResult | Promise<SourcesResult>;
    resolve(sourceId: string): PlayableStream | Promise<PlayableStream>;
  }): void;
  defineSearch(definition: {
    providerId: string;
    search(args: { query: string; page?: string }): CatalogPage | Promise<CatalogPage>;
  }): void;
  defineSubtitles(definition: {
    providerId: string;
    subtitles(args: { item: MediaItem }): SubtitlesResult | Promise<SubtitlesResult>;
  }): void;
  sourceId(providerKey: string, payload: JsonValue): string;
  sourcePayload<T extends JsonValue = JsonValue>(sourceId: string, expectedProviderKey?: string): T;
}

interface HostApi {
  codec: {
    base64ToText(value: string): string;
    textToBase64(value: string): string;
    hexToBase64(value: string): string;
    base64ToHex(value: string): string;
  };
  crypto: {
    sha256(value: string): string;
    hmacSha256(key: string, value: string): string;
    xor(a: string, b: string): string;
    aesCbcDecrypt(key: string, iv: string, data: string): string | null;
    aesGcmDecrypt(key: string, nonce: string, data: string): string | null;
  };
  match: {
    resolve(
      query: Record<string, JsonValue>,
      candidates: Record<string, JsonValue>[],
      options?: Record<string, JsonValue>,
    ): { index: number; confidence: number } | null;
  };
}

declare const fvcksubs: FvcksubsSdk;
declare const host: HostApi;
declare function fetch(
  url: string,
  options?: { method?: string; headers?: Record<string, string>; body?: string },
): Promise<{ status: number; headers: Record<string, string>; url: string; body: string }>;
