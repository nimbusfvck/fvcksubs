// Kora as a stream provider, in JS on the host `fetch`/`codec`/`match` API.
//
// A JavaScript port of the Kora upstream protocol. Three
// hosts: cdn.kora-api.org (daily list, XOR+base64 encoded), kora-api.space
// (match detail, plain JSON), and — once a match is picked — a per-match
// edge node, `{edge}.{edgeDomain}`, that mints the actual signed stream URL.
//
// Loaded alongside fixtures.js (see manifest.json's single `entry` and the
// app's loader, which concatenates them — there is no real bundler yet).
// Adds to the `globalThis.__extension` object fixtures.js already created,
// rather than replacing it.

// Overridable purely for tests — see fixtures.js's identical pattern.
const KORA_LIST_BASE =
  globalThis.__koraListBaseUrl || 'https://cdn.kora-api.org/api/';
const KORA_DETAIL_BASE =
  globalThis.__koraDetailBaseUrl || 'https://kora-api.space/api/';

const KORA_KEY = 'K0r@Api$3cr3tK3y';
const KORA_DEFAULT_UA = 'okhttp/4.12.0';
const KORA_BROWSER_UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36';
const KORA_PLAYER_VALUE = 12;

const KORA_PROVIDER_KEY = 'kora';
const KORA_PROVIDER_ID = 'nimora.kora';

// Football's own knowledge for the matcher — mirrors
// football_normalization_profile.dart exactly; see PLAN.md §12/M18 for why
// this is data the extension carries, not something the host knows.
const FOOTBALL_PROFILE = {
  aliases: {
    'man utd': 'manchester united',
    'man united': 'manchester united',
    'man city': 'manchester city',
    spurs: 'tottenham hotspur',
    psg: 'paris saint germain',
    barca: 'barcelona',
    inter: 'internazionale',
    juve: 'juventus',
    atleti: 'atletico madrid',
    // Cricfy shortens Atlético Madrid to "Atl. Madrid" after punctuation
    // normalization turns it into "atl madrid".
    'atl madrid': 'atletico madrid',
    // Athletic Bilbao's official name is "Athletic Club" — the "club" stop
    // token would otherwise strip it down to the bare "athletic", which is
    // an ambiguousAlone token and can never clear minTeamScore on its own.
    'athletic club': 'athletic bilbao',
    wolves: 'wolverhampton wanderers',
    'west brom': 'west bromwich albion',
    'west bromwich': 'west bromwich albion',
    // FotMob uses "A Coruña" while Spanish broadcast feeds often use the
    // club's traditional "La Coruña" spelling.
    'deportivo a coruna': 'deportivo la coruna',
  },
  stopTokens: ['fc', 'afc', 'cf', 'sc', 'ac', 'cd', 'club'],
  ambiguousAlone: [
    'united', 'city', 'town', 'rovers', 'wanderers', 'albion', 'athletic',
    'county', 'real', 'atletico', 'sporting', 'dynamo', 'racing', 'olympique',
  ],
};
globalThis.__nimoraFootballProfile = FOOTBALL_PROFILE;

// ---- KoraJson-equivalent tolerant readers ----
//
// Kora sends most scalars as strings; these coerce across string/number/bool
// and accept a list of alias keys, trying each in order — same contract as
// Dart's KoraJson.

function koraClean(value) {
  if (value === null || value === undefined) return '';
  const text = String(value).trim();
  return text.toLowerCase() === 'null' ? '' : text;
}

function koraStr(json, keys) {
  for (const key of keys) {
    const v = koraClean(json[key]);
    if (v.length > 0) return v;
  }
  return '';
}

function koraInt(json, keys) {
  for (const key of keys) {
    const v = json[key];
    if (typeof v === 'number') return Math.trunc(v);
    const cleaned = koraClean(v);
    if (cleaned.length === 0) continue;
    const parsed = parseInt(cleaned, 10);
    if (!isNaN(parsed)) return parsed;
  }
  return null;
}

function koraBool(json, keys) {
  for (const key of keys) {
    const value = json[key];
    if (value === null || value === undefined) continue;
    if (typeof value === 'boolean') return value;
    if (typeof value === 'number') return value !== 0;
    const text = String(value).trim().toLowerCase();
    if (text.length === 0 || text === 'null') continue;
    return text !== 'false' && text !== '0' && text !== 'no';
  }
  return false;
}

function koraStrList(json, keys) {
  for (const key of keys) {
    const v = json[key];
    if (Array.isArray(v)) return v.map(koraClean).filter((s) => s.length > 0);
  }
  return [];
}

// ---- codec (port of KoraCodec) ----
//
// One stage: base64 -> XOR with a fixed repeating 16-byte key -> JSON. The
// repeating XOR needs no new host primitive: base64<->hex is enough to do it
// as plain byte arithmetic in JS, which is what this does.

function isPlainJson(text) {
  const t = text.replace(/^\s+/, '');
  return t.startsWith('{') || t.startsWith('[');
}

function unwrapJsonString(text) {
  // The list endpoint wraps the base64 in a JSON string literal (and stray
  // leading newlines), e.g. `\n\n"EEtQ…"`; the detail endpoint sends bare
  // JSON. A payload that isn't a quoted string passes through unchanged.
  if (text.length < 2 || text[0] !== '"') return text;
  try {
    const decoded = JSON.parse(text);
    if (typeof decoded === 'string') return decoded.trim();
  } catch (_) {
    // Not valid JSON — leave it be.
  }
  return text;
}

function asciiToHex(text) {
  let hex = '';
  for (let i = 0; i < text.length; i++) {
    hex += text.charCodeAt(i).toString(16).padStart(2, '0');
  }
  return hex;
}

function xorHexRepeating(dataHex, keyHex) {
  const keyByteLen = keyHex.length / 2;
  let out = '';
  for (let i = 0; i < dataHex.length; i += 2) {
    const dByte = parseInt(dataHex.substr(i, 2), 16);
    const kByteIndex = ((i / 2) % keyByteLen) * 2;
    const kByte = parseInt(keyHex.substr(kByteIndex, 2), 16);
    out += (dByte ^ kByte).toString(16).padStart(2, '0');
  }
  return out;
}

function tryDecodeKora(text) {
  let dataHex;
  try {
    dataHex = host.codec.base64ToHex(text);
  } catch (_) {
    return null;
  }
  const plainHex = xorHexRepeating(dataHex, asciiToHex(KORA_KEY));
  const plain = host.codec.base64ToText(host.codec.hexToBase64(plainHex));
  // base64ToText never fails (malformed bytes become U+FFFD) — reject those
  // explicitly, to match Dart's strict utf8.decode, which throws (and so
  // returns null) on an invalid byte sequence. Without this, a wrong key
  // could still "succeed" into replacement-character garbage.
  if (plain.indexOf('�') !== -1) return null;
  if (!isPlainJson(plain)) return null;
  try {
    JSON.parse(plain);
  } catch (_) {
    return null;
  }
  return plain;
}

// Opens a Kora response into JSON text. Payloads that are already plain JSON
// pass through untouched, so this is safe to call whether or not a given
// response happens to be encoded.
function decodeKora(raw) {
  const text = unwrapJsonString(raw.trim());
  if (text.length === 0 || isPlainJson(text)) return text;
  const decoded = tryDecodeKora(text);
  if (decoded === null) throw new Error('Response could not be decoded');
  return decoded;
}

// ---- base64url ----

function base64UrlToBase64(token) {
  let normalized = token.replace(/-/g, '+').replace(/_/g, '/');
  const remainder = normalized.length % 4;
  if (remainder !== 0) normalized += '='.repeat(4 - remainder);
  return normalized;
}

// Padding kept, not stripped: Dart's `base64Url.encode` (what
// `KoraSourceId.encode` uses) pads by default, and matching that byte-for-
// byte is what lets `js_kora_conformance_test.dart` compare a JS-produced
// source id against the Dart original directly, not just structurally.
function base64ToBase64Url(b64) {
  return b64.replace(/\+/g, '-').replace(/\//g, '_');
}

// ---- source id (port of KoraSourceId) ----
//
// `resolve` is handed only a source id — the protocol is stateless — so
// everything a resolve needs (edges, edge domain, channel key) is packed
// into the id as base64url JSON. No crypto: this only has to round-trip.

function encodeKoraSourceId(payload) {
  const json = JSON.stringify({
    m: payload.matchId,
    e: payload.edges,
    d: payload.edgeDomain,
    k: payload.key,
    c: payload.ch,
    l: payload.label,
  });
  return base64ToBase64Url(host.codec.textToBase64(json));
}

function decodeKoraSourceId(encoded) {
  const json = host.codec.base64ToText(base64UrlToBase64(encoded));
  const obj = JSON.parse(json);
  return {
    matchId: obj.m,
    edges: obj.e,
    edgeDomain: obj.d,
    key: obj.k,
    ch: obj.c,
    label: obj.l,
  };
}

// ---- frame.php parsing (port of KoraFrameParser) ----
//
// The edge player mints the signed URL server-side and exposes it two ways:
// JSON `{url, exp}` (the token-renewal shape), or embedded in the page as
// `CONFIG.token` — a base64url of the full m3u8 URL. Both are handled; JSON
// is tried first, then scraping. `exp` isn't carried through: PlayableStream
// has no expiry field, it's Kora-internal.

function decodeKoraUrlToken(token) {
  return host.codec.base64ToText(base64UrlToBase64(token));
}

const KORA_TOKEN_PATTERN = /token\s*:\s*"([A-Za-z0-9_\-=]+)"/;
const KORA_CHANNEL_PATTERN = /channel\s*:\s*"([^"]*)"/;

function parseKoraFrame(body, headers) {
  const trimmed = body.trim();
  if (trimmed.startsWith('{')) {
    try {
      const obj = JSON.parse(trimmed);
      const url = koraStr(obj, ['url']);
      if (url.length > 0) {
        return { url, headers, channel: koraStr(obj, ['channel', 'ch']) };
      }
    } catch (_) {
      // Fall through to the scrape path.
    }
  }

  const token = KORA_TOKEN_PATTERN.exec(body);
  if (token) {
    const url = decodeKoraUrlToken(token[1]);
    const channel = KORA_CHANNEL_PATTERN.exec(body);
    return { url, headers, channel: channel ? channel[1] : '' };
  }

  throw new Error('frame.php response carries no stream token');
}

// ---- status mapping + candidates (port of KoraBroadcastSource) ----

function koraStatusOf(statusCode) {
  switch (statusCode) {
    case 0:
      return 'upcoming';
    case 1:
      return 'live';
    case 2:
      return 'ended';
    default:
      return 'unknown';
  }
}

// Kora publishes kick-off in GMT with no zone marker (the player labels it
// "GMT") — appending Z directly is the correct read, not device-local.
function koraKickoffUtc(dateStr, timeStr) {
  if (!dateStr) return null;
  const iso = timeStr ? `${dateStr}T${timeStr}:00Z` : `${dateStr}T00:00:00Z`;
  const parsed = new Date(iso);
  return isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

// Football candidates, live or upcoming with channels — matches
// KoraBroadcastSource.candidatesFrom. Keeps the raw match object alongside
// so the matched candidate's id can be read back out by index (see M18: the
// matcher returns an index, never a payload).
function koraCandidatesFrom(matches) {
  const out = [];
  for (const m of matches) {
    if (!koraBool(m, ['has_channels'])) continue;
    const status = koraStatusOf(koraInt(m, ['status']));
    if (status !== 'live' && status !== 'upcoming') continue;
    out.push({
      teamA: koraStr(m, ['home_en', 'home']),
      teamB: koraStr(m, ['away_en', 'away']),
      startsAt: koraKickoffUtc(koraStr(m, ['date']), koraStr(m, ['time'])),
      match: m,
    });
  }
  return out;
}

// Edge channels only, encoded into resolvable source ids — matches
// KoraBroadcastSource.sourcesFromDetail.
function koraSourcesFromDetail(detail) {
  const edges = koraStrList(detail, ['edges']);
  const edgeDomain = koraStr(detail, ['edge_domain']);
  const channels = Array.isArray(detail.channels) ? detail.channels : [];
  const matchId = koraStr(detail, ['id']);

  const sources = [];
  for (const channel of channels) {
    if (!koraBool(channel, ['edge'])) continue;
    const key = koraStr(channel, ['key', 'ch']);
    if (key.length === 0 || edges.length === 0 || edgeDomain.length === 0) {
      continue;
    }
    const label = koraStr(channel, ['name', 'label', 'server_name', 'quality']) || 'Kora';
    const sourceId = `${KORA_PROVIDER_KEY}:${key}`;
    const id = encodeKoraSourceId({
      matchId,
      edges,
      edgeDomain,
      key,
      ch: koraStr(channel, ['ch']),
      label,
    });
    sources.push({ id: `${KORA_PROVIDER_KEY}:${id}`, label, provider: 'Nimora', providerId: 'nimora.kora' });
  }
  return sources;
}

// ---- network ----

function withQuery(url, query) {
  const parts = Object.entries(query).map(
    ([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`,
  );
  return parts.length ? `${url}?${parts.join('&')}` : url;
}

function koraCacheBuster(date) {
  const p2 = (n) => String(n).padStart(2, '0');
  return (
    `${date.getUTCFullYear()}${p2(date.getUTCMonth() + 1)}` +
    `${p2(date.getUTCDate())}${p2(date.getUTCHours())}${p2(date.getUTCMinutes())}`
  );
}

async function koraGetText(url, headers) {
  const response = await fetch(url, { headers });
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Request to ${url} failed: ${response.status}`);
  }
  return response.body;
}

async function fetchKoraMatches() {
  const now = new Date();
  const date =
    `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}` +
    `-${String(now.getUTCDate()).padStart(2, '0')}`;
  const url = withQuery(`${KORA_LIST_BASE}matches/${date}`, {
    t: koraCacheBuster(now),
  });
  const body = await koraGetText(url, {
    'User-Agent': KORA_DEFAULT_UA,
    Accept: 'application/json, text/plain, */*',
  });
  if (body.trim().length === 0) return [];
  const data = JSON.parse(decodeKora(body));
  if (!Array.isArray(data)) {
    throw new Error('Kora matches response is not a JSON array');
  }
  return data;
}

async function fetchKoraDetail(matchId) {
  const url = withQuery(`${KORA_DETAIL_BASE}matche/${matchId}/ar`, {
    t: Date.now(),
  });
  const body = await koraGetText(url, {
    'User-Agent': KORA_DEFAULT_UA,
    Accept: 'application/json, text/plain, */*',
  });
  const data = JSON.parse(decodeKora(body));
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw new Error(`Detail for match ${matchId} is not a JSON object`);
  }
  return data;
}

function koraUuidV4() {
  const bytes = [];
  for (let i = 0; i < 16; i++) bytes.push(Math.floor(Math.random() * 256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = (a, b) =>
    bytes.slice(a, b).map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}`;
}

// Frame headers a browser sends loading frame.php as a cross-site iframe.
// The edge hosts 302 away anything that looks automated, so the request has
// to look like the real player's — no Referer needed, it sends none either.
function koraFrameHeaders() {
  return {
    'User-Agent': KORA_BROWSER_UA,
    Accept:
      'text/html,application/xhtml+xml,application/xml;q=0.9,' +
      'image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.8',
    'sec-ch-ua': '"Chromium";v="149", "Not)A;Brand";v="24"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"macOS"',
    'Sec-Fetch-Dest': 'iframe',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'cross-site',
    'Upgrade-Insecure-Requests': '1',
  };
}

function koraFrameUrl(edge, edgeDomain, query) {
  const configuredBase = globalThis.__koraEdgeBaseUrl;
  const base = typeof configuredBase === 'string' && configuredBase.length > 0
    ? `${configuredBase.replace(/\/$/, '')}/${edge}/frame.php`
    : `https://${edge}.${edgeDomain}/frame.php`;
  return withQuery(base, query);
}

// A frame.php response only proves that an edge can mint an HLS URL. It does
// not prove the edge will keep serving a moving live playlist. Keep a small,
// in-memory cursor per stable source id so a player re-resolve after a live
// stall starts at a different edge instead of pinning itself to edges[0].
// The cursor deliberately never enters the source id: it is a session-local
// transport choice, not a new user-visible source.
const koraLastResolvedEdgeBySource =
  globalThis.__koraLastResolvedEdgeBySource ||
  (globalThis.__koraLastResolvedEdgeBySource = Object.create(null));

function koraEdgesForResolve(sourceKey, edges) {
  const uniqueEdges = [];
  for (const edge of edges) {
    if (typeof edge === 'string' && edge.length > 0 && uniqueEdges.indexOf(edge) === -1) {
      uniqueEdges.push(edge);
    }
  }
  if (uniqueEdges.length === 0) return uniqueEdges;

  const previousEdge = koraLastResolvedEdgeBySource[sourceKey];
  const previousIndex = uniqueEdges.indexOf(previousEdge);
  // A fresh extension session must not always prefer the first published
  // edge. Once an edge has been used, every subsequent resolve is strictly
  // round-robin so stall recovery gets a different route.
  const start = previousIndex >= 0
    ? (previousIndex + 1) % uniqueEdges.length
    : Math.floor(Math.random() * uniqueEdges.length);
  return [
    ...uniqueEdges.slice(start),
    ...uniqueEdges.slice(0, start),
  ];
}

async function resolveKoraSource(sourceId) {
  const prefix = `${KORA_PROVIDER_KEY}:`;
  const inner = sourceId.startsWith(prefix)
    ? sourceId.slice(prefix.length)
    : sourceId;
  const decoded = decodeKoraSourceId(inner);
  if (!decoded.edges || decoded.edges.length === 0 || !decoded.edgeDomain) {
    throw new Error('Kora source has no edge nodes to resolve from');
  }
  const chParam = decoded.ch || decoded.key;
  if (!chParam) throw new Error('Kora source has no stream key');

  let lastError = null;
  for (const edge of koraEdgesForResolve(inner, decoded.edges)) {
    const requestUrl = koraFrameUrl(edge, decoded.edgeDomain, {
      ch: chParam,
      p: String(KORA_PLAYER_VALUE),
      token: koraUuidV4(),
      kt: String(Math.floor(Date.now() / 1000)),
    });
    try {
      const body = await koraGetText(requestUrl, koraFrameHeaders());
      // The player carries a browser User-Agent into the m3u8/segment requests.
      const stream = parseKoraFrame(body, { 'User-Agent': KORA_BROWSER_UA });
      if (!/^https?:\/\//i.test(stream.url)) throw new Error('Kora frame returned an invalid stream URL');
      koraLastResolvedEdgeBySource[inner] = edge;
      return { url: stream.url, headers: stream.headers, format: 'hls', label: decoded.label };
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error('Kora edge resolution failed');
}

async function koraSources(args) {
  const item = args.item;
  if (!item.participants || item.participants.length !== 2) {
    return { sources: [] };
  }
  const enabled = args.enabledProviders;
  if (enabled != null && enabled.indexOf(KORA_PROVIDER_ID) === -1) {
    return { sources: [] };
  }

  // Tolerant of this source failing — one broadcast source being down
  // shouldn't block whatever else is looking for sources on this item.
  let matches;
  try {
    matches = await fetchKoraMatches();
  } catch (_) {
    return { sources: [] };
  }
  const candidates = koraCandidatesFrom(matches);
  if (candidates.length === 0) return { sources: [] };

  const result = host.match.resolve(
    {
      teamA: item.participants[0].name,
      teamB: item.participants[1].name,
      teamAShort: item.participants[0].shortName || null,
      teamBShort: item.participants[1].shortName || null,
      kickoff: item.schedule ? item.schedule.startsAt : null,
    },
    candidates.map((c) => ({ teamA: c.teamA, teamB: c.teamB, startsAt: c.startsAt })),
    { profile: FOOTBALL_PROFILE },
  );
  if (!result) return { sources: [] };

  const matchId = koraStr(candidates[result.index].match, ['id']);
  let detail;
  try {
    detail = await fetchKoraDetail(matchId);
  } catch (_) {
    return { sources: [] };
  }
  return { sources: koraSourcesFromDetail(detail) };
}

// ---- stream provider registry ----
//
// Kora is the first stream provider registered here; Cricfy (cricfy.js) is
// the second. Both push themselves onto this array instead of assigning
// `__extension.sources`/`.resolve` directly, so loading one after the other
// doesn't stomp whichever loaded first. The aggregator below — installed once,
// idempotently, by whichever provider file happens to load first — fans a
// `sources()` call out to every registered provider (tolerant of one
// provider failing, same as Dart's `FvckExtension._sourcesFrom`) and unions
// the results, then routes `resolve()` by the `providerKey:` prefix each
// provider's own source ids carry, mirroring `FvckExtension.resolve` exactly.
globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: KORA_PROVIDER_KEY,
  sources: koraSources,
  resolve: (sourceId) => resolveKoraSource(sourceId),
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
