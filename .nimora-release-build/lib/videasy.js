// VidEasy stream provider, in JS on the host `fetch`/`codec` API.
//
// VidEasy (player.videasy.to) sources streams from api.speedracelight.com,
// which returns seed-encrypted JSON. We decrypt via enc-dec.app/api/dec-videasy.
//
// Servers available (language info from EncDecEndpoints README):
//   cdn        -> Original (may have 4K)
//   m4uhd      -> Original
//   vsrc       -> Original
//   hdmovie    -> Original (EN quality) / Hindi (quality == "Hindi")
//   meine      -> German
//   lamovie    -> Spanish
//   superflix  -> Portuguese
//
// Matches TMDB-backed items through their movie/series reference prefix.

const VIDEASY_SPEEDRACE_BASE =
  globalThis.__videasySpeedraceBaseUrl || 'https://api.speedracelight.com';
const VIDEASY_ENCDEC_BASE =
  globalThis.__videasyEncDecBaseUrl || 'https://enc-dec.app/api';

const VIDEASY_PROVIDER_KEY = 'videasy';
const VIDEASY_PROVIDER_ID = 'nimora.videasy';

const VIDEASY_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

// Servers exposed as stream sources. The key is the speedracelight.com path
// segment (e.g. /cdn/sources-with-title).
//
// Several, because which ones answer changes per *title*, not just per day:
// checked live, a film resolved only on `downloader2` while an episode of a
// series resolved only on `m4uhd`, `cdn` and `lamovie` — every other server
// returned 500 for that same request. Listing one server, or a short list
// that happens to miss the right one, reads to the viewer as "VidEasy has
// nothing" when it simply wasn't asked in the right place.
//
// Listing costs nothing: `videasyListSources` doesn't call these, it only
// names them. The requests happen when a source is resolved.
//
// Servers that answered 404 for every request (`myflixerzupcloud`, `jett`,
// `tejo`, `ym`) are left out — a 404 here is the path segment not existing,
// so those are wasted round trips rather than a server being down.
const VIDEASY_SERVERS = [
  { key: 'cdn', label: 'VidEasy Yoru', quality: '' },
  { key: 'downloader2', label: 'VidEasy Kite', quality: '' },
  { key: 'm4uhd', label: 'VidEasy Breach', quality: '' },
  { key: 'hdmovie', label: 'VidEasy Vyse', quality: '' },
  { key: 'lamovie', label: 'VidEasy Aura', quality: '' },
  { key: 'superflix', label: 'VidEasy Solstice', quality: '' },
  { key: 'neon2', label: 'VidEasy Neon', quality: '' },
];

function videasyHeaders() {
  return {
    Accept: '*/*',
    Origin: 'https://player.videasy.to',
    Referer: 'https://player.videasy.to/',
    'User-Agent': VIDEASY_UA,
  };
}

// Reads a `movie:<tmdbId>` reference.
function parseMovieRef(refId) {
  if (typeof refId !== 'string') return null;
  const prefix = 'movie:';
  if (!refId.startsWith(prefix)) return null;
  const id = refId.slice(prefix.length);
  return id.length > 0 ? id : null;
}

// Reads a `series:<tmdbId>` reference.
function parseSeriesRef(refId) {
  if (typeof refId !== 'string') return null;
  const prefix = 'series:';
  if (!refId.startsWith(prefix)) return null;
  const id = refId.slice(prefix.length);
  return id.length > 0 ? id : null;
}

function parseVideasyEpisodeRef(refId) {
  if (typeof refId !== 'string') return null;
  const match = /^series:([^:]+):season:([^:]+):episode:([^:]+)$/.exec(refId);
  return match == null
    ? null
    : { tmdbId: match[1], season: match[2], episode: match[3] };
}

// Source id encodes everything resolve() needs in base64url.
function encodeVideasySourceId(payload) {
  const json = JSON.stringify({
    s: payload.server,
    m: payload.tmdbId,
    t: payload.type,         // 'movie' or 'tv'
    se: payload.seed,
    // season/episode only for TV
    ...(payload.season != null ? { sn: payload.season, ep: payload.episode } : {}),
  });
  return host.codec.textToBase64(json).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function decodeVideasySourceId(sourceId) {
  // Restore standard base64 padding
  let b64 = sourceId.replace(/-/g, '+').replace(/_/g, '/');
  const rem = b64.length % 4;
  if (rem !== 0) b64 += '='.repeat(4 - rem);
  try {
    return JSON.parse(host.codec.base64ToText(b64));
  } catch (_) {
    return null;
  }
}

// Fetch the seed for a given tmdbId. Required to decrypt the response.
async function fetchSeed(tmdbId) {
  let response;
  try {
    response = await fetch(
      `${VIDEASY_SPEEDRACE_BASE}/seed?mediaId=${encodeURIComponent(tmdbId)}`,
      { headers: videasyHeaders() },
    );
  } catch (_) {
    return null;
  }
  if (response.status < 200 || response.status >= 300) return null;
  try {
    const data = JSON.parse(response.body);
    return data.seed != null ? String(data.seed) : null;
  } catch (_) {
    return null;
  }
}

// Double-encodes the title per VidEasy convention.
function doubleEncodeTitle(title) {
  return encodeURIComponent(encodeURIComponent(title));
}

// Returns the raw encrypted text from speedracelight.
async function fetchEncryptedSources(serverKey, query) {
  const params = Object.entries(query)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
  const url = `${VIDEASY_SPEEDRACE_BASE}/${serverKey}/sources-with-title?${params}`;
  let response;
  try {
    response = await fetch(url, { headers: videasyHeaders() });
  } catch (_) {
    return null;
  }
  if (response.status < 200 || response.status >= 300) return null;
  return response.body;
}

// Decrypts the encrypted text via enc-dec.app.
async function decryptVideasy(encryptedText, tmdbId, seed) {
  let response;
  try {
    response = await fetch(`${VIDEASY_ENCDEC_BASE}/dec-videasy`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: encryptedText, id: tmdbId, seed }),
    });
  } catch (_) {
    return null;
  }
  if (response.status < 200 || response.status >= 300) return null;
  try {
    const data = JSON.parse(response.body);
    if (data.status !== 200) return null;
    return data.result;
  } catch (_) {
    return null;
  }
}

// sources() — lists one source entry per server for a given movie/series item.
// We list them by server without fetching (that happens on resolve()), so this
// is fast and doesn't hit the network per-server.
async function videasyListSources(args) {
  const item = args.item || {};
  const refId = (item.ref && item.ref.id) || item.id || '';

  const isMovie = parseMovieRef(refId) !== null;
  const episodeRef = parseVideasyEpisodeRef(refId);
  const isSeries = episodeRef !== null;
  if (!isMovie && !isSeries) return { sources: [] };

  const tmdbId = isMovie ? parseMovieRef(refId) : episodeRef.tmdbId;

  // For series, require season + episode in item.extra.
  // Fetch the seed now (one request) so resolve() can use it without a
  // redundant trip.
  const seed = await fetchSeed(tmdbId);
  if (!seed) return { sources: [] };

  const sources = VIDEASY_SERVERS.map((srv) => {
    const id = `${VIDEASY_PROVIDER_KEY}:${encodeVideasySourceId({
      server: srv.key,
      tmdbId,
      type: isMovie ? 'movie' : 'tv',
      seed,
      season: isSeries ? episodeRef.season : null,
      episode: isSeries ? episodeRef.episode : null,
    })}`;
    return { id, label: srv.label, provider: 'Nimora', providerId: 'nimora.videasy' };
  });

  return { sources };
}

// resolve() — fetches and decrypts the actual stream URL for the chosen server.
async function videasyResolveSource(sourceId) {
  const prefix = `${VIDEASY_PROVIDER_KEY}:`;
  if (!sourceId.startsWith(prefix)) {
    throw new Error(`Invalid VidEasy sourceId: ${sourceId}`);
  }
  const payload = decodeVideasySourceId(sourceId.slice(prefix.length));
  if (!payload) throw new Error('Malformed VidEasy source id');

  const { s: server, m: tmdbId, t: type, se: seed, sn: season, ep: episode } = payload;

  // Build the speedracelight query.
  const query = {
    tmdbId,
    mediaType: type,
    enc: '2',
    seed,
    // title is not needed when we have tmdbId; use a placeholder to satisfy
    // the endpoint signature.
    title: encodeURIComponent(String(tmdbId)),
  };
  if (type === 'tv') {
    query.seasonId = season;
    query.episodeId = episode;
  }

  const encrypted = await fetchEncryptedSources(server, query);
  if (!encrypted) throw new Error('VidEasy: failed to fetch encrypted sources');

  const decrypted = await decryptVideasy(encrypted, tmdbId, seed);
  if (!decrypted) throw new Error('VidEasy: decryption failed');

  // Decrypted is `{ sources: [{url, quality}], subtitles: [...] }`.
  //
  // Not `{file, type}` / `tracks`, which is what this read for until it was
  // checked against a live response — so even a server that answered fell
  // over here with "no stream URL". `quality` is a server nickname
  // ("playhq", "bk"), not a resolution, so it isn't treated as one.
  let parsed;
  try {
    parsed = typeof decrypted === 'string' ? JSON.parse(decrypted) : decrypted;
  } catch (_) {
    throw new Error('VidEasy: invalid decrypted JSON');
  }

  const sourcesArr = Array.isArray(parsed.sources) ? parsed.sources : [];
  const entry = sourcesArr.find((s) => s && typeof s.url === 'string' && s.url);
  if (!entry) throw new Error('VidEasy: no stream URL in decrypted payload');

  const rawSubs = Array.isArray(parsed.subtitles) ? parsed.subtitles : [];
  const subtitles = rawSubs
    .filter((t) => t && (t.url || t.file))
    .map((t) => ({
      language: t.language || t.label || t.lang || '',
      url: t.url || t.file,
      label: t.label || t.language || t.lang || '',
    }));

  return {
    url: entry.url,
    // These come back as both .m3u8 and .mp4 depending on the server.
    format: entry.url.includes('.m3u8') ? 'hls' : 'other',
    headers: {
      Origin: 'https://player.videasy.to',
      Referer: 'https://player.videasy.to/',
      'User-Agent': VIDEASY_UA,
    },
    subtitles,
  };
}

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: VIDEASY_PROVIDER_KEY,
  sources: videasyListSources,
  resolve: videasyResolveSource,
});
