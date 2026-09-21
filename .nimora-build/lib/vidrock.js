// Vidrock as a stream provider, in JS on the host `fetch`/`codec`/`crypto` API.
//
// A port of CineStream's `invokeVidrock` (CineStreamExtractors.kt) and
// `decryptVidrockUrl` (CineStreamUtils.kt) — CineStream
// (github.com/SaurabhKaperwan/CineStream) is a CloudStream-style Kotlin
// aggregator with ~60 upstream integrations, most of them HTML-scrape-heavy
// in a way this sandbox has no primitive for yet (no `host.html`, per
// PLAN.md §18). Vidrock is the one ported here: one JSON GET, one field to
// decrypt per server — the same shape kora.js/cricfy.js already handle, and
// the only new capability it needs is `host.crypto.aesGcmDecrypt`, added
// alongside this file.
//
// Movies only. Vidrock's TV endpoint is keyed by tmdbId+season+episode, and
// nothing in the app yet lets a user choose either — PLAN.md flags
// "children (series)" as an acknowledged, not-yet-built capability — so a
// series item's `sources()` call is declined with an empty list, exactly how
// kora.js declines an item without two participants.
//
// Matches TMDB-backed items through their `movie:<tmdbId>` reference.
//
// Vidrock only returns subtitles that belong to its resolved stream. Shegu is
// a separate external-subtitles provider and is intentionally not consulted
// from this resolver.

const VIDROCK_BASE = globalThis.__vidrockBaseUrl || 'https://vidrock.ru';

// Static across the whole upstream (verified against the live API, not just
// the Kotlin source): AES-256-GCM, no AAD, 12-byte nonce prepended to the
// ciphertext+tag, the base64url-of-hex-key form CineStream hardcodes.
const VIDROCK_KEY_HEX =
  '7f3e9c2a8b5d1f4e6a9c3b7d2e5f8a1c4b6d9e2f5a8c1b4d7e9f2a5c8b1d4e7f';
const VIDROCK_UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36';

const VIDROCK_PROVIDER_KEY = 'vidrock';
const VIDROCK_PROVIDER_ID = 'nimora.vidrock';

function vidrockHeaders() {
  return {
    Origin: VIDROCK_BASE,
    Referer: `${VIDROCK_BASE}/`,
    'User-Agent': VIDROCK_UA,
  };
}

// Reads a `movie:<tmdbId>` reference.
function parseTmdbMovieRef(refId) {
  if (typeof refId !== 'string') return null;
  const prefix = 'movie:';
  if (!refId.startsWith(prefix)) return null;
  const tmdbId = refId.slice(prefix.length);
  return tmdbId.length > 0 ? tmdbId : null;
}

// Reads a `series:<tmdbId>` reference.
function parseTmdbSeriesRef(refId) {
  if (typeof refId !== 'string') return null;
  const prefix = 'series:';
  if (!refId.startsWith(prefix)) return null;
  const tmdbId = refId.slice(prefix.length);
  return tmdbId.length > 0 ? tmdbId : null;
}

function parseVidrockEpisodeRef(refId) {
  if (typeof refId !== 'string') return null;
  const match = /^series:([^:]+):season:([^:]+):episode:([^:]+)$/.exec(refId);
  return match == null
    ? null
    : { tmdbId: match[1], season: match[2], episode: match[3] };
}

// ---- base64url (same pair kora.js defines; kept local — see this
// extension's no-shared-helpers convention, one file per provider) ----

function base64UrlToBase64(token) {
  let normalized = token.replace(/-/g, '+').replace(/_/g, '/');
  const remainder = normalized.length % 4;
  if (remainder !== 0) normalized += '='.repeat(4 - remainder);
  return normalized;
}

function base64ToBase64Url(b64) {
  return b64.replace(/\+/g, '-').replace(/\//g, '_');
}

// ---- source id ----
//
// Bakes the still-encrypted url straight in, so `resolve()` needs no second
// fetch for the stream itself — same shape as kora.js's `encodeKoraSourceId`.
// The tmdbId rides along because the upstream API response and source label
// are TMDB-keyed; `resolve(sourceId)` receives only this opaque id.

function encodeVidrockSourceId(payload) {
  const json = JSON.stringify({
    u: payload.encryptedUrl,
    type: payload.type,
    m: payload.tmdbId,
    // season/episode are present only for TV; omit for movies.
    ...(payload.season != null ? { s: payload.season, e: payload.episode } : {}),
  });
  return base64ToBase64Url(host.codec.textToBase64(json));
}

function decodeVidrockSourceId(encoded) {
  const json = host.codec.base64ToText(base64UrlToBase64(encoded));
  return JSON.parse(json);
}

// ---- decrypt (port of decryptVidrockUrl) ----

function decryptVidrockUrl(encryptedPayload) {
  const dataHex = host.codec.base64ToHex(base64UrlToBase64(encryptedPayload));
  const nonceHex = dataHex.slice(0, 24); // 12 bytes
  const cipherHex = dataHex.slice(24); // ciphertext + 16-byte tag
  if (nonceHex.length !== 24 || cipherHex.length === 0) return null;

  const keyB64 = host.codec.hexToBase64(VIDROCK_KEY_HEX);
  const nonceB64 = host.codec.hexToBase64(nonceHex);
  const cipherB64 = host.codec.hexToBase64(cipherHex);

  const plainB64 = host.crypto.aesGcmDecrypt(keyB64, nonceB64, cipherB64);
  return plainB64 === null ? null : host.codec.base64ToText(plainB64);
}

// ---- network ----

async function vidrockSources(args) {
  const item = args.item;
  const enabled = args.enabledProviders;
  if (enabled != null && enabled.indexOf(VIDROCK_PROVIDER_ID) === -1) {
    return { sources: [] };
  }

  const refId = item.ref && item.ref.id;

  // ---- TV series episode path ----
  const episodeRef = parseVidrockEpisodeRef(refId);
  if (episodeRef !== null) {
    const seriesTmdbId = episodeRef.tmdbId;
    const season = episodeRef.season;
    const episode = episodeRef.episode;

    let response;
    try {
      response = await fetch(
        `${VIDROCK_BASE}/api/tv/${seriesTmdbId}/${season}/${episode}`,
        { headers: vidrockHeaders() },
      );
    } catch (_) {
      return { sources: [] };
    }
    if (response.status < 200 || response.status >= 300) return { sources: [] };

    let servers;
    try {
      servers = JSON.parse(response.body);
    } catch (_) {
      return { sources: [] };
    }

    const sources = [];
    for (const name of Object.keys(servers)) {
      const server = servers[name];
      const encryptedUrl = server && server.url;
      if (!encryptedUrl || encryptedUrl === 'error' || encryptedUrl === 'null') {
        continue;
      }
      const id = encodeVidrockSourceId({
        encryptedUrl,
        type: server.type || 'hls',
        tmdbId: seriesTmdbId,
        season,
        episode,
      });
      const lang = server.language ? ` (${server.language})` : '';
      const realName = [
        name,
        server.name,
        server.quality,
        server.resolution,
      ]
        .filter((value) => value != null && String(value).trim().length > 0)
        .join(' ');
      const sourceId = `${VIDROCK_PROVIDER_KEY}:${id}`;
      sources.push({
        id: sourceId,
        // Keep the provider's original server name and the dub language.
        label: `${sourceAliasWithQuality(sourceId, name, realName)}${lang}`,
        provider: 'Nimora',
        providerId: 'nimora.vidrock',
      });
    }
    return { sources };
  }

  // ---- Movie path (unchanged) ----
  const tmdbId = parseTmdbMovieRef(refId);
  if (tmdbId === null) return { sources: [] };

  let response;
  try {
    response = await fetch(`${VIDROCK_BASE}/api/movie/${tmdbId}/`, {
      headers: vidrockHeaders(),
    });
  } catch (_) {
    return { sources: [] };
  }
  if (response.status < 200 || response.status >= 300) return { sources: [] };

  let servers;
  try {
    servers = JSON.parse(response.body);
  } catch (_) {
    return { sources: [] };
  }

  const sources = [];
  for (const name of Object.keys(servers)) {
    const server = servers[name];
    const encryptedUrl = server && server.url;
    if (!encryptedUrl || encryptedUrl === 'error' || encryptedUrl === 'null') {
      continue;
    }
    const id = encodeVidrockSourceId({
      encryptedUrl,
      type: server.type || 'hls',
      tmdbId,
    });
    const lang = server.language ? ` (${server.language})` : '';
    const realName = [
      name,
      server.name,
      server.quality,
      server.resolution,
    ]
      .filter((value) => value != null && String(value).trim().length > 0)
      .join(' ');
    const sourceId = `${VIDROCK_PROVIDER_KEY}:${id}`;
    sources.push({
      id: sourceId,
      // Keep the provider's original server name and the dub language.
      label: `${sourceAliasWithQuality(sourceId, name, realName)}${lang}`,
      provider: 'Nimora',
      providerId: 'nimora.vidrock',
    });
  }
  return { sources };
}

async function resolveVidrockSource(sourceId) {
  const prefix = `${VIDROCK_PROVIDER_KEY}:`;
  const inner = sourceId.startsWith(prefix) ? sourceId.slice(prefix.length) : sourceId;
  const decoded = decodeVidrockSourceId(inner);

  const url = decryptVidrockUrl(decoded.u);
  if (url === null) throw new Error('Vidrock source failed to decrypt');

  const format = decoded.type === 'hls' || url.indexOf('.m3u8') !== -1 ? 'hls' : 'other';
  const result = { url, headers: vidrockHeaders(), format };

  return result;
}

// ---- registration — see kora.js's tail for the shared aggregator ----

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: VIDROCK_PROVIDER_KEY,
  sources: vidrockSources,
  resolve: (sourceId) => resolveVidrockSource(sourceId),
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
    if (separator < 0) throw new Error(`Malformed source id: ${sourceId}`);
    const providerKey = sourceId.slice(0, separator);
    const provider = globalThis.__streamProviders.find((p) => p.providerKey === providerKey);
    if (!provider) throw new Error(`No stream provider registered for "${providerKey}"`);
    return provider.resolve(sourceId);
  };
}
