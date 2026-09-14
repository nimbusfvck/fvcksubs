// FlyStream as a stream provider, over the host `fetch` API.
//
// flystream.net serves one or more adaptive HLS playlists per title from
// `/api/streams`, keyed by TMDB id. AniList episode refs use the site's
// `/api/anilist/identity` mapping first, then enter the same TMDB-keyed flow.
// It is worth the file because of what is
// behind that playlist: a real 4K ladder (hvc1 2160p / avc1 1080p / 720p /
// 360p, fMP4 segments) rather than the single re-encode most of the other
// upstreams here hand back — verified by summing `#EXTINF` durations against
// the known runtime for Inception (148.1 vs ~148 min), Breaking Bad S01E01
// (58.0 vs ~58), Severance S02E01 (48.9 vs ~49) and Toy Story (81.1 vs ~81).
// A tmdbId with no match answers `{"streams":[]}`, so a wrong id is a miss
// rather than someone else's film.
//
// Two things gate the API, and missing either one answers
// `403 {"error":"Playback unavailable"}`:
//
//   1. an `fs_seen2` cookie, which `GET /` hands out to anyone who asks, and
//   2. `Sec-Fetch-Site: same-origin` on the API request itself.
//
// Referer, Origin, sec-ch-ua and Accept-Language are all checked and none of
// them matter.
//
// What does matter, and is the reason nothing here sends a User-Agent:
// **do not claim to be a browser.** Cloudflare holds a request that says it
// is Chrome to a Chrome-shaped TLS and HTTP fingerprint, and refuses it with
// a `403` when the shape doesn't match — the plain homepage included. An
// honest one is not held to that and is simply let through. Measured from
// one `dart:io` client, same second, same IP:
//
//   (nothing set, so `Dart/3.12 (dart:io)`)  -> 200
//   ExoPlayer/okhttp                          -> 200
//   Mozilla/5.0 ... Chrome/131.0.0.0          -> 403
//
// This is also why the pure-Dart port this was written from (PlayTorrioV3's
// `flystream.dart`) finds nothing and reports it as an empty result: it
// sends a Chrome User-Agent, and no cookie or `Sec-Fetch-Site` besides.
// Leaving the header off entirely lets the host and the player each send
// their own, which is the truthful thing for either to say.
//
// `title` is a required query parameter but is *not* used for matching — a
// deliberately wrong title with a right tmdbId still resolves the right
// film — so nothing here depends on title spelling. `viewerId` is required
// too, and is the rate-limit key: omit it and the API answers
// `429 {"error":"Too many requests","retryAfterSec":600}`. The site itself
// keeps one per browsing session in `sessionStorage.fs_viewer_id`, which is
// what `flystreamViewerId` mirrors.
//
// Both movies and series. A series item must carry season and episode in its
// reference; a bare `series:<tmdbId>` is declined rather than guessed at,
// the same way vidrock.js and vaplayer.js decline it.

const FLYSTREAM_BASE = globalThis.__flystreamBaseUrl || 'https://flystream.net';
// Playlists and segments come off a separate host, and a relative `url` in
// the API response is relative to *that* host, not to the API's own — the
// Dart port resolves those against the API base and 403s on every one.
const FLYSTREAM_MEDIA_BASE =
  globalThis.__flystreamMediaBaseUrl || 'https://media.flystream.net';

const FLYSTREAM_PROVIDER_KEY = 'flystream';
const FLYSTREAM_PROVIDER_ID = 'nimora.flystream';

const FLYSTREAM_COOKIE_NAME = 'fs_seen2';
const FLYSTREAM_COOKIE_CACHE_KEY = 'flystream:seen2';
// Stands in for the cookie when the handshake succeeded but the platform's
// HTTP client kept `Set-Cookie` to itself. NSURLSession does exactly that —
// it moves the cookie into its own `HTTPCookieStorage` and replays it on the
// next request to the same host, so the header never reaches this code and
// none has to be sent by hand. Cronet and `dart:io` both expose it instead.
// Chosen so it can never collide with a real value, which is always
// `fs_seen2=…`.
const FLYSTREAM_COOKIE_IN_JAR = 'jar';
// The upstream sets Max-Age=2592000 (30 days). Cached for a week instead:
// a stale cookie costs one wasted request and a re-handshake (below), and
// there is nothing to gain from holding one for a month.
const FLYSTREAM_COOKIE_CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

const FLYSTREAM_VIEWER_CACHE_KEY = 'flystream:viewer';
const FLYSTREAM_VIEWER_CACHE_TTL_MS = 24 * 60 * 60 * 1000;

// ---- base64url ----
//
// Local, deliberately: this file loads before kora.js/vidrock.js in the
// bundle (it has to, to list first), so it cannot borrow theirs, and the
// bundle is one scope so the names have to differ from theirs.

function flystreamBase64ToUrl(b64) {
  return b64.replace(/\+/g, '-').replace(/\//g, '_');
}

function flystreamUrlToBase64(token) {
  let normalized = token.replace(/-/g, '+').replace(/_/g, '/');
  const remainder = normalized.length % 4;
  if (remainder !== 0) normalized += '='.repeat(4 - remainder);
  return normalized;
}

// ---- storage ----
//
// Same contract cricfy.js states: a cache an extension may use, never one it
// may rely on. Every read treats a miss as ordinary.

function flystreamStorage() {
  return typeof host === 'object' && host !== null && host.storage
    ? host.storage
    : null;
}

function flystreamCacheRead(key) {
  const storage = flystreamStorage();
  if (storage === null) return null;
  let raw;
  try {
    raw = storage.read(key);
  } catch (_) {
    return null;
  }
  return typeof raw === 'string' && raw.length > 0 ? raw : null;
}

function flystreamCacheWrite(key, value, ttlMs) {
  const storage = flystreamStorage();
  if (storage === null) return;
  try {
    storage.write(key, value, ttlMs);
  } catch (_) {
    // A cache that won't take the value changes nothing about this session.
  }
}

function flystreamCacheDelete(key) {
  const storage = flystreamStorage();
  if (storage === null) return;
  try {
    storage.delete(key);
  } catch (_) {
    // Nothing to do; the stale value simply expires on its own.
  }
}

// ---- viewer id ----

function flystreamRandomHex(length) {
  let out = '';
  while (out.length < length) {
    out += Math.floor(Math.random() * 0x100000000)
      .toString(16)
      .padStart(8, '0');
  }
  return out.slice(0, length);
}

let flystreamViewerMemo = null;

function flystreamViewerId() {
  if (flystreamViewerMemo !== null) return flystreamViewerMemo;
  const cached = flystreamCacheRead(FLYSTREAM_VIEWER_CACHE_KEY);
  if (cached !== null && /^[0-9a-f]{32}$/.test(cached)) {
    flystreamViewerMemo = cached;
    return cached;
  }
  const generated = flystreamRandomHex(32);
  flystreamCacheWrite(
    FLYSTREAM_VIEWER_CACHE_KEY,
    generated,
    FLYSTREAM_VIEWER_CACHE_TTL_MS,
  );
  flystreamViewerMemo = generated;
  return generated;
}

// ---- session cookie ----

function flystreamResponseHeader(response, name) {
  const headers = response && response.headers;
  if (headers == null || typeof headers !== 'object') return '';
  const wanted = String(name).toLowerCase();
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === wanted) return String(headers[key] || '');
  }
  return '';
}

// The host joins repeated response headers with ", ", so a Set-Cookie value
// can arrive alongside others in one string. Match the named pair wherever it
// sits rather than assuming it is first.
function flystreamParseCookie(setCookie) {
  const match = new RegExp(
    `(?:^|[,;\\s])${FLYSTREAM_COOKIE_NAME}=([^;,\\s]+)`,
  ).exec(setCookie);
  return match == null ? null : `${FLYSTREAM_COOKIE_NAME}=${match[1]}`;
}

let flystreamCookieMemo = null;

async function flystreamFetchCookie() {
  let response;
  try {
    response = await fetch(`${FLYSTREAM_BASE}/`, {
      headers: { Accept: 'text/html' },
    });
  } catch (_) {
    return null;
  }
  if (response.status < 200 || response.status >= 400) return null;
  const cookie = flystreamParseCookie(
    flystreamResponseHeader(response, 'set-cookie'),
  );
  // A 2xx means the handshake was accepted, and that is what the API checks
  // for. Whether the cookie is visible here is the platform's business.
  return cookie === null ? FLYSTREAM_COOKIE_IN_JAR : cookie;
}

// Returns the session cookie, minting one if there isn't a usable one.
// In-process the promise itself is memoized, so several items opened at once
// share a single handshake instead of racing one each.
function flystreamCookie() {
  if (flystreamCookieMemo !== null) return flystreamCookieMemo;

  const cached = flystreamCacheRead(FLYSTREAM_COOKIE_CACHE_KEY);
  if (cached !== null) {
    flystreamCookieMemo = Promise.resolve(cached);
    return flystreamCookieMemo;
  }

  flystreamCookieMemo = flystreamFetchCookie().then((cookie) => {
    if (cookie === null) {
      // Don't hold a failed handshake: the next item should try again.
      flystreamCookieMemo = null;
      return null;
    }
    flystreamCacheWrite(
      FLYSTREAM_COOKIE_CACHE_KEY,
      cookie,
      FLYSTREAM_COOKIE_CACHE_TTL_MS,
    );
    return cookie;
  });
  return flystreamCookieMemo;
}

function flystreamForgetCookie() {
  flystreamCookieMemo = null;
  flystreamCacheDelete(FLYSTREAM_COOKIE_CACHE_KEY);
}

// ---- the API ----

function flystreamApiHeaders(cookie) {
  return {
    Accept: 'application/json',
    // The gate. Without it the API answers 403 no matter what else is sent.
    'Sec-Fetch-Site': 'same-origin',
    ...(cookie === FLYSTREAM_COOKIE_IN_JAR ? {} : { Cookie: cookie }),
  };
}

function flystreamStreamsUrl(query) {
  const parts = [];
  for (const key of Object.keys(query)) {
    const value = query[key];
    if (value == null || String(value).length === 0) continue;
    parts.push(`${key}=${encodeURIComponent(String(value))}`);
  }
  return `${FLYSTREAM_BASE}/api/streams?${parts.join('&')}`;
}

// A 429 carries `retryAfterSec` and the upstream means it — asking again
// inside the window just extends it. Held in memory only: it describes this
// process's standing with the API, not anything worth surviving a restart.
let flystreamCooldownUntilMs = 0;

// One request, with a single retry reserved for the one failure a retry can
// fix: a cookie the upstream no longer accepts.
async function flystreamRequestStreams(query, { allowRetry = true } = {}) {
  return flystreamRequestJson(flystreamStreamsUrl(query), { allowRetry });
}

async function flystreamRequestJson(url, { allowRetry = true } = {}) {
  if (Date.now() < flystreamCooldownUntilMs) return null;

  const cookie = await flystreamCookie();
  if (cookie === null) return null;

  let response;
  try {
    response = await fetch(url, {
      headers: flystreamApiHeaders(cookie),
    });
  } catch (_) {
    return null;
  }

  if (response.status === 429) {
    let retryAfterSec = 600;
    try {
      const parsed = JSON.parse(response.body);
      if (parsed && typeof parsed.retryAfterSec === 'number') {
        retryAfterSec = parsed.retryAfterSec;
      }
    } catch (_) {
      // Keep the upstream's own default window.
    }
    flystreamCooldownUntilMs = Date.now() + retryAfterSec * 1000;
    return null;
  }

  if (response.status === 403 && allowRetry) {
    // The cookie is the only thing a 403 here is ever about; mint a new one
    // and give the request exactly one more go.
    flystreamForgetCookie();
    return flystreamRequestJson(url, { allowRetry: false });
  }

  if (response.status < 200 || response.status >= 300) return null;

  try {
    return JSON.parse(response.body);
  } catch (_) {
    return null;
  }
}

function flystreamPlaybackUrl(rawUrl) {
  if (typeof rawUrl !== 'string' || rawUrl.length === 0) return null;
  if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
    return rawUrl;
  }
  if (rawUrl.startsWith('/')) return `${FLYSTREAM_MEDIA_BASE}${rawUrl}`;
  return null;
}

// The media host wants the Referer and refuses the request without it. It
// wants no User-Agent from us: the player sends its own, which is honest and
// accepted, and overriding it with a browser's would get the playlist
// refused for the same reason the API would be.
function flystreamPlaybackHeaders() {
  return { Referer: `${FLYSTREAM_BASE}/` };
}

function flystreamFormat(stream) {
  if (stream && stream.isDash === true) return 'dash';
  if (stream && stream.isHls === true) return 'hls';
  const url = stream && typeof stream.url === 'string' ? stream.url : '';
  if (url.indexOf('.m3u8') !== -1) return 'hls';
  if (url.indexOf('.mpd') !== -1) return 'dash';
  return 'other';
}

// `quality` is the top rung of the ladder inside the playlist, not the only
// one on offer — the URL is a master playlist and the player picks from
// `resolutions`. Labelling it as the quality is still the honest summary:
// it is the best this source can give.
//
// `videoCodec` is deliberately ignored. The API reports "h264" for playlists
// whose 2160p variant is plainly `hvc1`, so surfacing it would be stating
// something wrong with more confidence than the API has earned.
function flystreamQualityScore(stream) {
  const explicit = stream && stream.quality;
  const values = typeof explicit === 'string' && explicit.trim() !== ''
    ? [explicit]
    : Array.isArray(stream && stream.resolutions)
      ? stream.resolutions
      : [];
  let score = 0;
  for (const value of values) {
    if (typeof value !== 'string') continue;
    const match = /(?:^|[^0-9])(\d{3,4})\s*p?(?=$|[^a-z0-9])/i.exec(value);
    if (match != null) {
      score = Math.max(score, Number(match[1]));
      continue;
    }
    if (/^4k$/i.test(value.trim())) score = Math.max(score, 2160);
    if (/^2k$/i.test(value.trim())) score = Math.max(score, 1440);
  }
  return score;
}

function flystreamBestStream(streams) {
  const candidates = [];
  const seenUrls = new Set();
  for (const [index, stream] of streams.entries()) {
    if (stream == null || typeof stream !== 'object') continue;
    const url = flystreamPlaybackUrl(stream.url);
    if (url === null || seenUrls.has(url)) continue;
    seenUrls.add(url);
    candidates.push({ stream, url, index, quality: flystreamQualityScore(stream) });
  }
  candidates.sort((a, b) => b.quality - a.quality || a.index - b.index);
  return candidates[0] || null;
}

// ---- source ids ----
//
// The playlist URL is baked straight in, so resolve() needs no second
// request — the same shape kora.js's `encodeKoraSourceId` uses, and here it
// also keeps a rate-limited endpoint to exactly one call per item opened.

function encodeFlystreamSourceId(payload) {
  return flystreamBase64ToUrl(
    host.codec.textToBase64(
      JSON.stringify({ u: payload.url, f: payload.format }),
    ),
  );
}

function decodeFlystreamSourceId(encoded) {
  return JSON.parse(host.codec.base64ToText(flystreamUrlToBase64(encoded)));
}

// ---- references ----

function flystreamEpisodeSeason(item) {
  const episode = item && item.episode;
  const groupId = episode && typeof episode.groupId === 'string'
    ? episode.groupId
    : '';
  const match = /(?:^|:)season:(\d+)/i.exec(groupId);
  return match == null ? '1' : match[1];
}

function flystreamSeriesTitle(item) {
  const subtitle = item && typeof item.subtitle === 'string'
    ? item.subtitle.trim()
    : '';
  if (subtitle) return subtitle;
  return item && typeof item.title === 'string' ? item.title : '';
}

// Reads `movie:<tmdbId>`, `series:<tmdbId>:season:<s>:episode:<e>`, and
// AniList's `anilist:episode:<id>:<episode>` protocol-v2 refs.
function parseFlystreamRef(refId, item) {
  if (typeof refId !== 'string') return null;
  const episode = /^series:([^:]+):season:([^:]+):episode:([^:]+)$/.exec(refId);
  if (episode != null) {
    return {
      type: 'tv',
      tmdbId: episode[1],
      season: episode[2],
      episode: episode[3],
    };
  }
  const anilistEpisode = /^anilist:episode:(\d+):(\d+)$/.exec(refId);
  if (anilistEpisode != null) {
    return {
      type: 'tv',
      tmdbId: null,
      anilistId: anilistEpisode[1],
      season: flystreamEpisodeSeason(item),
      episode: anilistEpisode[2],
    };
  }
  const prefix = 'movie:';
  if (!refId.startsWith(prefix)) return null;
  const tmdbId = refId.slice(prefix.length);
  return tmdbId.length > 0
    ? { type: 'movie', tmdbId, season: null, episode: null }
    : null;
}

function flystreamAnilistIdentityUrl(parsed, item) {
  const parts = [
    `anilistId=${encodeURIComponent(parsed.anilistId)}`,
    `title=${encodeURIComponent(flystreamSeriesTitle(item) || parsed.anilistId)}`,
  ];
  if (Number.isInteger(item && item.releaseYear)) {
    parts.push(`year=${encodeURIComponent(String(item.releaseYear))}`);
  }
  return `${FLYSTREAM_BASE}/api/anilist/identity?${parts.join('&')}`;
}

function flystreamIdentity(payload) {
  const candidates = [
    payload,
    payload && payload.data,
    payload && payload.identity,
    payload && payload.result,
  ];
  for (const candidate of candidates) {
    if (candidate == null || typeof candidate !== 'object') continue;
    for (const key of ['tmdbId', 'tmdb_id', 'tmdb']) {
      const value = candidate[key];
      let tmdbId = null;
      if (Number.isInteger(value) && value > 0) tmdbId = String(value);
      if (typeof value === 'string' && /^\d+$/.test(value)) tmdbId = value;
      if (tmdbId == null) continue;

      const season = candidate.season;
      const mappedSeason = Number.isInteger(season) && season > 0
        ? String(season)
        : typeof season === 'string' && /^\d+$/.test(season)
          ? season
          : null;
      return { tmdbId, season: mappedSeason };
    }
  }
  return null;
}

async function flystreamResolveAnilistIdentity(parsed, item) {
  const payload = await flystreamRequestJson(
    flystreamAnilistIdentityUrl(parsed, item),
  );
  return flystreamIdentity(payload);
}

// ---- provider ----

async function flystreamListSources(args) {
  const enabled = args.enabledProviders;
  if (enabled != null && enabled.indexOf(FLYSTREAM_PROVIDER_ID) === -1) {
    return { sources: [] };
  }

  const item = args.item || {};
  const refId = (item.ref && item.ref.id) || item.id || '';
  const parsed = parseFlystreamRef(refId, item);
  if (parsed === null) return { sources: [] };

  let tmdbId = parsed.tmdbId;
  let season = parsed.season;
  if (tmdbId == null) {
    const identity = await flystreamResolveAnilistIdentity(parsed, item);
    if (identity == null) return { sources: [] };
    tmdbId = identity.tmdbId;
    if (identity.season != null) season = identity.season;
  }

  const payload = await flystreamRequestStreams({
    type: parsed.type,
    viewerId: flystreamViewerId(),
    // Required by the endpoint, unused for matching. The tmdbId stands in
    // when an item has no title rather than leaving the parameter empty,
    // which the API rejects as a missing lookup id.
    title:
      typeof item.title === 'string' && item.title.length > 0
        ? item.title
        : tmdbId,
    tmdbId,
    year: Number.isInteger(item.releaseYear) ? item.releaseYear : null,
    season,
    episode: parsed.episode,
  });

  const streams =
    payload && Array.isArray(payload.streams) ? payload.streams : [];

  const selected = flystreamBestStream(streams);
  if (selected === null) return { sources: [] };

  const format = flystreamFormat(selected.stream);
  const sourceId = `${FLYSTREAM_PROVIDER_KEY}:${encodeFlystreamSourceId({
    url: selected.url,
    format,
  })}`;
  return {
    sources: [{
      id: sourceId,
      label: sourceAliasWithQuality(sourceId, 'FlyStream', 'FlyStream'),
      provider: 'Nimora',
      providerId: FLYSTREAM_PROVIDER_ID,
    }],
  };
}

async function flystreamResolveSource(sourceId) {
  const prefix = `${FLYSTREAM_PROVIDER_KEY}:`;
  if (!sourceId.startsWith(prefix)) {
    throw new Error(`Invalid FlyStream sourceId: ${sourceId}`);
  }
  const decoded = decodeFlystreamSourceId(sourceId.slice(prefix.length));
  if (!decoded || typeof decoded.u !== 'string' || decoded.u.length === 0) {
    throw new Error('Malformed FlyStream source id');
  }
  return {
    url: decoded.u,
    format: decoded.f || 'hls',
    headers: flystreamPlaybackHeaders(),
  };
}

// ---- registration — see kora.js's tail for the shared aggregator ----
//
// The aggregator concatenates each provider's list in registration order and
// nothing downstream re-sorts, so the bundle's file order decides where this
// one sits. It no longer leads: these renditions are fMP4, which the FFmpeg
// libmpv is built against cannot seek without the player's cut-playlist
// path, while VaPlayer and vidrock seek through libmpv's own. FlyStream
// stays for the 4K ladder nothing else here offers.

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: FLYSTREAM_PROVIDER_KEY,
  sources: flystreamListSources,
  resolve: (sourceId) => flystreamResolveSource(sourceId),
});

globalThis.__extension = globalThis.__extension || {};
if (!globalThis.__extension.sources) {
  globalThis.__extension.sources = async (args) => {
    const calls = globalThis.__streamProviders.map((p) =>
      Promise.resolve()
        .then(() => p.sources(args))
        .catch(() => ({ sources: [] })),
    );
    if (args.fast !== true) {
      const perProvider = await Promise.all(calls);
      return { sources: perProvider.flatMap((r) => r.sources) };
    }
    return new Promise((resolve) => {
      let remaining = calls.length;
      let returned = false;
      for (const call of calls) {
        call.then((result) => {
          if (returned) return;
          const sources = Array.isArray(result.sources) ? result.sources : [];
          if (sources.length > 0) {
            returned = true;
            resolve({ sources });
            return;
          }
          remaining -= 1;
          if (remaining === 0) resolve({ sources: [] });
        });
      }
    });
  };
  globalThis.__extension.resolve = async (args) => {
    const sourceId = args.sourceId;
    const separator = sourceId.indexOf(':');
    if (separator < 0) {
      throw new Error(`Malformed source id: ${sourceId}`);
    }
    const providerKey = sourceId.slice(0, separator);
    const provider = globalThis.__streamProviders.find(
      (p) => p.providerKey === providerKey,
    );
    if (!provider) {
      throw new Error(`No stream provider registered for "${providerKey}"`);
    }
    return provider.resolve(sourceId);
  };
}
