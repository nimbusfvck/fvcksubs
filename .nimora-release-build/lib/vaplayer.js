// VaPlayer as a stream provider, over the host `fetch` API.
//
// Ported from CineStream's `invokeVaPlayer` (CineStreamExtractors.kt). The
// one upstream in this family that hands back playable URLs in the clear:
// `api.php` answers with `data.stream_urls`, a plain list of HLS playlists,
// plus a large `default_subs` list. No cipher, no key exchange, nothing to
// decrypt.
//
// That is worth stating because its sibling is not. `data.vidsrcme.ru` serves
// the same `api.php` shape, but its `stream_urls` is a single encrypted blob
// with a `vs.wasm_url` beside it — a per-response WebAssembly module that
// decrypts it, whose id rotates on every request. This sandbox has no
// `WebAssembly` at all, so that host cannot be integrated without widening
// the runtime; this one needs nothing new.
//
// Keyed by tmdbId, which the `movie:<tmdbId>` / `series:<tmdbId>` references
// already carry, so no id translation is needed
// (the upstream accepts `imdb=` too — verified — but nothing here has an
// IMDB id to give it).
//
// Both movies and series. A series item must carry `extra.season` and
// `extra.episode`; without them there is no episode to ask for, and the call
// is declined with an empty list rather than guessed at.

const VAPLAYER_BASE =
  globalThis.__vaplayerBaseUrl || 'https://streamdata.vaplayer.ru';

const VAPLAYER_PROVIDER_KEY = 'vaplayer';

// The upstream serves these only to its own embed host.
const VAPLAYER_REFERER = 'https://nextgencloudfabric.com/';
const VAPLAYER_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

function vaplayerHeaders() {
  return {
    Accept: '*/*',
    Referer: VAPLAYER_REFERER,
    'User-Agent': VAPLAYER_UA,
  };
}

// Reads `movie:<tmdbId>` / `series:<tmdbId>` references.
function parseVaplayerRef(refId) {
  if (typeof refId !== 'string') return null;
  const episode = /^series:([^:]+):season:([^:]+):episode:([^:]+)$/.exec(refId);
  if (episode != null) {
    return {
      kind: 'series',
      tmdbId: episode[1],
      season: episode[2],
      episode: episode[3],
    };
  }
  const separator = refId.indexOf(':');
  if (separator < 0) return null;
  const kind = refId.slice(0, separator);
  const tmdbId = refId.slice(separator + 1);
  if ((kind !== 'movie' && kind !== 'series') || tmdbId.length === 0) {
    return null;
  }
  return { kind, tmdbId, season: null, episode: null };
}

function vaplayerApiUrl(tmdbId, kind, season, episode) {
  const base = `${VAPLAYER_BASE}/api.php?tmdb=${encodeURIComponent(tmdbId)}`;
  if (kind === 'movie') return `${base}&type=movie`;
  return (
    `${base}&type=tv&season=${encodeURIComponent(season)}` +
    `&episode=${encodeURIComponent(episode)}`
  );
}

async function fetchVaplayer(url) {
  let response;
  try {
    response = await fetch(url, { headers: vaplayerHeaders() });
  } catch (_) {
    return null;
  }
  if (response.status < 200 || response.status >= 300) return null;
  try {
    return JSON.parse(response.body);
  } catch (_) {
    return null;
  }
}

function vaplayerStreamUrls(payload) {
  const urls = payload && payload.data && payload.data.stream_urls;
  if (!Array.isArray(urls)) return [];
  return urls.filter((u) => typeof u === 'string' && u.length > 0);
}

// `default_subs` entries are `{lang, code, url}`. `lang` is the human label
// ("Portuguese - Brazilian"); `code` is the two-letter tag the app groups by.
function vaplayerSubtitles(payload) {
  const subs = payload && payload.default_subs;
  if (!Array.isArray(subs)) return [];
  return subs
    .filter((s) => s && typeof s.url === 'string' && s.url.length > 0)
    .map((s) => ({
      language: s.code || s.lang || '',
      url: s.url,
      label: s.lang || s.code || '',
    }));
}

// Source ids carry everything resolve() needs to ask again, plus which of the
// returned URLs this source stands for. The URL itself is deliberately *not*
// baked in: resolve() has to re-fetch anyway to get the subtitles, which are
// far too many to carry in an id.
function encodeVaplayerSourceId(payload) {
  const json = JSON.stringify({
    m: payload.tmdbId,
    k: payload.kind,
    i: payload.index,
    ...(payload.season != null
      ? { s: payload.season, e: payload.episode }
      : {}),
  });
  return base64ToBase64Url(host.codec.textToBase64(json));
}

function decodeVaplayerSourceId(encoded) {
  const json = host.codec.base64ToText(base64UrlToBase64(encoded));
  return JSON.parse(json);
}

// sources() — one entry per stream URL the upstream offers.
//
// This does fetch, unlike videasy.js's server list: how many URLs there are
// is only known from the response, and offering a fixed number would mean
// either inventing sources that don't resolve or hiding ones that do.
async function vaplayerListSources(args) {
  const item = args.item || {};
  const refId = (item.ref && item.ref.id) || item.id || '';
  const parsed = parseVaplayerRef(refId);
  if (!parsed) return { sources: [] };

  const isSeries = parsed.kind === 'series';
  if (isSeries && (parsed.season == null || parsed.episode == null)) {
    return { sources: [] };
  }

  const payload = await fetchVaplayer(
    vaplayerApiUrl(parsed.tmdbId, parsed.kind, parsed.season, parsed.episode),
  );
  const urls = vaplayerStreamUrls(payload);

  return {
    sources: urls.map((_, index) => {
      const id = `${VAPLAYER_PROVIDER_KEY}:${encodeVaplayerSourceId({
        tmdbId: parsed.tmdbId,
        kind: parsed.kind,
        index,
        season: isSeries ? parsed.season : null,
        episode: isSeries ? parsed.episode : null,
      })}`;
      // The upstream distinguishes them in no way at all — they are
      // The upstream gives these playlists no distinct names.
      return {
        id,
        label: `VaPlayer ${index + 1}`,
        provider: 'Nimora',
        providerId: 'nimora.vaplayer',
      };
    }),
  };
}

async function vaplayerResolveSource(sourceId) {
  const prefix = `${VAPLAYER_PROVIDER_KEY}:`;
  if (!sourceId.startsWith(prefix)) {
    throw new Error(`Invalid VaPlayer sourceId: ${sourceId}`);
  }
  const payloadId = decodeVaplayerSourceId(sourceId.slice(prefix.length));
  const { m: tmdbId, k: kind, i: index, s: season, e: episode } = payloadId;

  const payload = await fetchVaplayer(
    vaplayerApiUrl(tmdbId, kind, season, episode),
  );
  if (!payload) throw new Error('VaPlayer: failed to fetch sources');

  const urls = vaplayerStreamUrls(payload);
  // Re-fetched, so the list can be shorter than when the id was minted.
  if (index >= urls.length) {
    throw new Error('VaPlayer: stream no longer offered');
  }

  return {
    url: urls[index],
    format: 'hls',
    headers: {
      Referer: VAPLAYER_REFERER,
      'User-Agent': VAPLAYER_UA,
    },
    subtitles: vaplayerSubtitles(payload),
  };
}

// ---- registration — see kora.js's tail for the shared aggregator ----

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: VAPLAYER_PROVIDER_KEY,
  sources: vaplayerListSources,
  resolve: (sourceId) => vaplayerResolveSource(sourceId),
});
