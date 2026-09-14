// Cricfy as a stream provider, in JS on the host `fetch`/`crypto`/`codec`/
// `match` API — the harder of the two providers ported so far (see
// cricfy_cipher.js, M14): not just a decode, but the full config → signed
// URL → event list → link list → exchange/token resolution pipeline.
//
// A JavaScript port of the Cricfy upstream protocol.
// Loaded alongside fixtures.js, kora.js, and cricfy_cipher.js (see
// manifest.json and the app's loader, which concatenates them all — there is
// no real bundler yet). Registers itself into `globalThis.__streamProviders`, the
// same registry kora.js's tail installs the aggregator for; adds a second
// entry rather than a second `__extension.sources` assignment.
//
// Full bundles share this profile with Kora through the global bridge below.
// Compact intentionally omits kora.js, so keep an identical fallback here;
// Cricfy must still match football items when it is the only football source.
const CRICFY_FOOTBALL_PROFILE = globalThis.__nimoraFootballProfile || {
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
    'atl madrid': 'atletico madrid',
    'athletic club': 'athletic bilbao',
    wolves: 'wolverhampton wanderers',
    'west brom': 'west bromwich albion',
    'west bromwich': 'west bromwich albion',
    'deportivo a coruna': 'deportivo la coruna',
  },
  stopTokens: ['fc', 'afc', 'cf', 'sc', 'ac', 'cd', 'club'],
  ambiguousAlone: [
    'united', 'city', 'town', 'rovers', 'wanderers', 'albion', 'athletic',
    'county', 'real', 'atletico', 'sporting', 'dynamo', 'racing', 'olympique',
  ],
};

// Overridable purely for tests — see fixtures.js/kora.js's identical pattern.
// `configMirrors: []` here matches `CricfyClient(configMirrors: [])` in
// the fixture tests: an empty list forces the fallback-config path
// immediately, no network round trip.
const CRICFY_CONFIG_MIRRORS =
  globalThis.__cricfyConfigMirrors === undefined
    ? ['https://p.genzdev.xyz/1-xnavxf.json', 'https://c.playtek.xyz/1-xnavxf.json']
    : globalThis.__cricfyConfigMirrors;
const CRICFY_API_BASE_URL =
  globalThis.__cricfyApiBaseUrl || 'https://cricyplayers.com/data/';

const CRICFY_GETDATA_ENDPOINT = 'getData.php';
const CRICFY_GETDATA_PATH_PREFIX = 'v2/';
const CRICFY_GETDATA_TOKEN =
  '8f4gha9affeegg7cigafdgc7hegfkefaicigdgg1haffhekgeeigcfgahedfhef';
const CRICFY_EVENTS_PATH = 'events.txt';
const CRICFY_EVENT_LINKS_PREFIX = 'pro/';
const CRICFY_DEFAULT_UA =
  'Mozilla/5.0 (Linux; Android 10; Pixel 3 XL) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';
const CRICFY_CONFIG_UA = 'Mozilla/5.0 Cricfy2/1.0';

const CRICFY_PROVIDER_KEY = 'cricfy';
const CRICFY_PROVIDER_ID = 'nimora.cricfy';

// Catalog data is optional. Keep both the configured API and the fallback
// attempt inside the app's discovery budget; a slow Cricfy endpoint must not
// hide sources from Roxie or the other providers.
const CRICFY_CONTENT_TIMEOUT_MS = 8 * 1000;

// The event list, kept across app launches (see `host.storage`). A cold
// start would otherwise have to wait out that same slow call before it could
// offer a single source, inside a discovery budget that has no room for it.
// Held longer than the in-session memo because its job is different: not
// "is this fresh?" but "is there anything at all to work from while the
// fresh copy is on its way?".
const CRICFY_EVENTS_CACHE_KEY = 'cricfy.events.v1';
const CRICFY_EVENTS_CACHE_TTL_MS = 6 * 60 * 60 * 1000;

// ---- codec (port of CricfyCodec, minus CricfyContentCipher — see
// cricfy_cipher.js, M14) ----

const CRICFY_CONFIG_PREFIX = 'cfj1:';
const CRICFY_A0 = [0x1d, 0x58, 0x11, 0x68, 0x42, 0x07, 0x5b, 0x22, 0x71, 0x05, 0x2f, 0x60];
const CRICFY_A1 = [0x47, 0x0c, 0x53, 0x2c, 0x09, 0x79, 0x24, 0x3a, 0x65, 0x16, 0x3f];
const CRICFY_A2 = [
  0x06, 0x27, 0x5f, 0x0e, 0x4a, 0x34, 0x75, 0x1b, 0x44, 0x03, 0x56, 0x29, 0x6d,
];
const CRICFY_PLAIN_ALPHABET =
  'aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ';
const CRICFY_CIPHER_ALPHABET =
  'fFgGjJkKaApPbBmMoOzZeEnNcCdDrRqQtTvVuUxXhHiIwWyYlLsS';

function cricfyConfigMaterial() {
  const out = new Array(32).fill(0);
  for (let i = 0; i < out.length; i++) {
    const rotation = i & 7;
    const source = CRICFY_A1[(3 * i + 1) % CRICFY_A1.length];
    const rotated = ((source << rotation) | (source >>> (8 - rotation))) & 0xff;
    out[i] =
      (CRICFY_A0[i % CRICFY_A0.length] ^
        rotated ^
        CRICFY_A2[(5 * i + 2) % CRICFY_A2.length] ^
        0x5a ^
        i) &
      0xff;
  }
  return out;
}

function decodeCricfyConfigPayload(raw) {
  let text = raw.trim();
  if (text.startsWith('{') || text.startsWith('[')) return text;
  if (text.startsWith(CRICFY_CONFIG_PREFIX)) {
    text = text.slice(CRICFY_CONFIG_PREFIX.length);
  }
  text = text.replace(/[\r\n\t ]/g, '');

  const dataHex = host.codec.base64ToHex(text);
  const material = cricfyConfigMaterial();
  const len = dataHex.length / 2;
  const outBytes = new Array(len);
  for (let i = 0; i < len; i++) {
    const dByte = parseInt(dataHex.substr(i * 2, 2), 16);
    const value =
      (material[i % material.length] ^ dByte ^ ((0x1d * i + 0x47) & 0xff)) & 0xff;
    outBytes[len - 1 - i] = value;
  }
  const outHex = outBytes.map((b) => b.toString(16).padStart(2, '0')).join('');
  return host.codec.base64ToText(host.codec.hexToBase64(outHex)).trim();
}

// Opens a `getData.php` response, whatever shape it's in: an already-plain
// response passes through, content lists go through `cricfyCipher` (the AES
// path, cricfy_cipher.js), everything else through the substituted-alphabet
// `decodeCricfyPayload`.
function decodeCricfyResponse(raw) {
  const text = raw.trim();
  if (text.length === 0 || text.startsWith('[') || text.startsWith('{')) {
    return text;
  }
  const viaCipher = cricfyCipher.decode(text);
  if (viaCipher !== null && viaCipher.length > 0) return viaCipher;
  return decodeCricfyPayload(text);
}

function decodeCricfyPayload(raw) {
  const text = raw.trim();
  if (text.length === 0 || text.startsWith('[') || text.startsWith('{')) {
    return text;
  }
  let out = '';
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    const idx = CRICFY_CIPHER_ALPHABET.indexOf(ch);
    out += idx < 0 ? ch : CRICFY_PLAIN_ALPHABET[idx];
  }
  return host.codec.base64ToText(out);
}

// XORs every UTF-8 byte with 0x5a then hex-encodes — the `key`/`hmac` on a
// signed URL. `base64ToHex` does the byte extraction; the XOR itself is
// plain hex-pair arithmetic in JS, the same approach kora.js's repeating XOR
// uses, and (again) needs no new host primitive.
function cricfyXorHex(value) {
  const hex = host.codec.base64ToHex(host.codec.textToBase64(value));
  let out = '';
  for (let i = 0; i < hex.length; i += 2) {
    const byte = parseInt(hex.substr(i, 2), 16);
    out += (byte ^ 0x5a).toString(16).padStart(2, '0');
  }
  return out;
}

// ---- urls (port of CricfyUrls) ----

function cricfyIsFullUrl(value) {
  const lower = value.trim().toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

function cricfyTrimLeadingSlash(value) {
  let i = 0;
  while (i < value.length && value[i] === '/') i++;
  return value.slice(i);
}

function cricfyLastPartLooksLikeFile(value) {
  const slash = value.lastIndexOf('/');
  const last = slash < 0 ? value : value.slice(slash + 1);
  return last.indexOf('.') !== -1;
}

function cricfyJoinUrl(base, path) {
  if (base.length === 0) return path;
  if (path.length === 0) return base;
  const left = base.endsWith('/') ? base.slice(0, -1) : base;
  return `${left}/${cricfyTrimLeadingSlash(path)}`;
}

function cricfyNormalizeHost(value) {
  const trimmed = value.trim();
  if (trimmed.length === 0 || !cricfyIsFullUrl(trimmed)) return '';
  if (trimmed.endsWith('/')) return trimmed;
  if (cricfyLastPartLooksLikeFile(trimmed)) {
    const slash = trimmed.lastIndexOf('/');
    return slash < 0 ? `${trimmed}/` : trimmed.slice(0, slash + 1);
  }
  return `${trimmed}/`;
}

function cricfyStripV2Host(value) {
  return value.toLowerCase().endsWith('/v2/') ? value.slice(0, -3) : value;
}

function cricfyApplyPathPrefix(path, prefix) {
  const cleanPath = cricfyTrimLeadingSlash(path);
  let cleanPrefix = cricfyTrimLeadingSlash(prefix);
  if (cleanPrefix.length === 0) return cleanPath;
  if (!cleanPrefix.endsWith('/')) cleanPrefix += '/';
  if (cleanPath.startsWith(cleanPrefix)) return cleanPath;
  return `${cleanPrefix}${cleanPath}`;
}

function cricfyBuildSignedUrl({ base, endpoint, path, prefix, token, nowMillis }) {
  const host_ = cricfyNormalizeHost(cricfyStripV2Host(base));
  const fullPath = cricfyApplyPathPrefix(path, prefix);
  const millis = nowMillis != null ? nowMillis : Date.now();
  const key = cricfyXorHex(fullPath);
  const hmac = cricfyXorHex(`${millis}|${token}`);
  return `${cricfyJoinUrl(host_, endpoint)}?key=${key}&hmac=${hmac}`;
}

// Minimal `http(s)://host[:port]/path` parser — QuickJS has no `URL` global,
// and this client only ever needs host+path out of an absolute URL.
function cricfyParseUrl(value) {
  const m = /^https?:\/\/([^/?#]+)(\/[^?#]*)?/i.exec(value);
  if (!m) return null;
  return { host: m[1], path: m[2] || '/' };
}

function cricfyRelativeToBase(url, base) {
  const host_ = cricfyNormalizeHost(cricfyStripV2Host(base));
  if (host_.length > 0 && url.startsWith(host_)) {
    return cricfyTrimLeadingSlash(url.slice(host_.length));
  }
  const parsed = cricfyParseUrl(url);
  const baseParsed = cricfyParseUrl(host_);
  if (!parsed || !baseParsed) return '';
  if (parsed.host !== baseParsed.host) return '';
  let path = cricfyTrimLeadingSlash(parsed.path);
  const basePath = cricfyTrimLeadingSlash(baseParsed.path);
  if (basePath.length > 0 && path.startsWith(basePath)) {
    path = cricfyTrimLeadingSlash(path.slice(basePath.length));
  }
  return path;
}

// Some links arrive with the `url|Header=value` separator percent-encoded as
// `%7C`. Splitting on the literal pipe alone leaves `%7CReferer=...` glued to
// the query string *and* drops the header the origin requires, so the fetch
// comes back 403 on a link that is otherwise fine. Only an encoded pipe that
// introduces a header assignment is treated as a separator — an encoded pipe
// inside an ordinary query value stays part of the URL.
const CRICFY_ENCODED_PIPE = /%7c(?=[A-Za-z][A-Za-z0-9-]*=)/gi;

function cricfySplitLinkAndHeaders(value) {
  value = value.replace(CRICFY_ENCODED_PIPE, '|');
  if (value.indexOf('|') === -1) return { url: value.trim(), headers: {} };
  const parts = value.split('|');
  const headers = {};
  for (let i = 1; i < parts.length; i++) {
    Object.assign(headers, cricfyParseHeaderQuery(parts[i]));
  }
  return { url: parts[0].trim(), headers };
}

function cricfyParseHeaderQuery(value) {
  const headers = {};
  if (value.trim().length === 0) return headers;
  for (const pair of value.split('&')) {
    if (pair.trim().length === 0) continue;
    const sep = pair.indexOf('=');
    if (sep <= 0) continue;
    const name = pair.slice(0, sep).trim();
    const val = pair.slice(sep + 1).trim();
    if (name.length === 0 || val.length === 0 || val === 'null') continue;
    headers[name] = val;
  }
  return headers;
}

// Later layer wins, case-insensitively by name — same rationale as Dart's:
// HTTP header names are case-insensitive, but a plain JS object compares keys
// verbatim, so a naive merge would send both `User-Agent` and `user-agent`.
function cricfyMergeHeaders(layers) {
  const result = {};
  const keyByLower = {};
  for (const layer of layers) {
    for (const name of Object.keys(layer)) {
      const lower = name.toLowerCase();
      const previousKey = keyByLower[lower];
      if (previousKey !== undefined) delete result[previousKey];
      result[name] = layer[name];
      keyByLower[lower] = name;
    }
  }
  return result;
}

// Hex -> base64url, no padding — matches `CricfyUrls.hexToBase64Url`. Tolerant
// of invalid hex (returns null), unlike the host primitive it's built on.
function cricfyHexToBase64Url(hex) {
  if (hex.length === 0 || hex.length % 2 !== 0 || !/^[0-9a-fA-F]+$/.test(hex)) {
    return null;
  }
  const b64 = host.codec.hexToBase64(hex);
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function cricfyToClearKeyJson(api) {
  const value = api.trim();
  if (value.length === 0 || cricfyIsFullUrl(value)) return null;
  const entries = [];

  if (value.startsWith('{')) {
    let decoded;
    try {
      decoded = JSON.parse(value);
    } catch (_) {
      return null;
    }
    if (typeof decoded !== 'object' || decoded === null || Array.isArray(decoded)) {
      return null;
    }
    const keys = decoded.keys;
    if (!Array.isArray(keys)) return null;
    for (const item of keys) {
      if (typeof item !== 'object' || item === null) continue;
      const kid = String(item.kid ?? '').replace(/\n/g, '');
      const key = String(item.k ?? '').replace(/\n/g, '');
      if (kid.length === 0 || key.length === 0) continue;
      entries.push(`{"kty":"oct","k":"${key}","kid":"${kid}"}`);
    }
  } else if (value.indexOf(':') !== -1) {
    for (const pair of value.split(',')) {
      const parts = pair.split(':');
      if (parts.length !== 2) continue;
      const kid = cricfyHexToBase64Url(parts[0].trim());
      const key = cricfyHexToBase64Url(parts[1].trim());
      if (kid === null || key === null) continue;
      entries.push(`{"kty":"oct","k":"${key}","kid":"${kid}"}`);
    }
  }

  if (entries.length === 0) return null;
  return `{"keys":[${entries.join(',')}],"type":"temporary"}`;
}

// ---- models ----

// CricfyJson equivalent: reads a field at the top level, falling back to a
// nested container for the server's newer nested shape.
const CRICFY_JSON_FALLBACKS = {
  teamAName: ['teamA', 'name'],
  teamBName: ['teamB', 'name'],
  teamALogo: ['teamA', 'logo'],
  teamBLogo: ['teamB', 'logo'],
  category: ['eventDetails', 'category'],
  eventName: ['eventDetails', 'eventName'],
  eventLogo: ['eventDetails', 'eventLogo'],
};

function cricfyJsonClean(value) {
  if (value === null || value === undefined) return '';
  const text = String(value);
  return text.trim().toLowerCase() === 'null' ? '' : text;
}

function cricfyJsonNested(json, container, innerKey) {
  const child = json[container];
  if (typeof child !== 'object' || child === null || Array.isArray(child)) return '';
  return cricfyJsonClean(child[innerKey]);
}

function cricfyJsonString(json, key) {
  const direct = cricfyJsonClean(json[key]);
  if (direct.length > 0) return direct;
  const fallback = CRICFY_JSON_FALLBACKS[key];
  if (!fallback) return '';
  return cricfyJsonNested(json, fallback[0], fallback[1]);
}

// Missing counts as visible (`true`) — the server only hides an entry by
// explicitly setting `false`, same contract as Dart's `CricfyJson.boolean`.
function cricfyJsonBoolean(json, key) {
  const value = json[key];
  if (value === null || value === undefined) return true;
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  const text = String(value).trim().toLowerCase();
  if (text.length === 0 || text === 'null') return true;
  return text !== 'false' && text !== '0' && text !== 'no';
}

function cricfyDrmSchemeFromCode(code) {
  if (code === 0) return 'clearKey';
  if (code === 1) return 'widevine';
  return 'playReady';
}

function cricfyLinkFromJson(json) {
  const rawAudio = json.audio;
  const audio = typeof rawAudio === 'string' && rawAudio !== 'pronull' ? rawAudio : '';
  const rawScheme = json.scheme;
  const scheme =
    typeof rawScheme === 'number' ? rawScheme : parseInt(String(rawScheme), 10) || 0;
  return {
    name: String(json.name ?? ''),
    link: String(json.link ?? ''),
    drmApi: typeof json.api === 'string' ? json.api : '',
    tokenApi: typeof json.tokenApi === 'string' ? json.tokenApi : '',
    audio,
    scheme: cricfyDrmSchemeFromCode(scheme),
    secureDecoder: json.secure_decoder === true,
  };
}

function cricfyLinksFromList(items) {
  const links = [];
  for (const item of items) {
    if (typeof item === 'object' && item !== null && !Array.isArray(item)) {
      links.push(cricfyLinkFromJson(item));
    }
  }
  return links;
}

// A `links` field arrives as either a path to fetch later, or an embedded
// JSON array (sometimes itself encoded as a JSON *string*).
function cricfyParseLinksField(raw) {
  if (Array.isArray(raw)) return { path: '', embedded: cricfyLinksFromList(raw) };
  if (typeof raw !== 'string') return { path: '', embedded: [] };
  const value = raw.trim();
  if (value.length === 0) return { path: '', embedded: [] };
  if (!value.startsWith('[')) return { path: value, embedded: [] };
  let decoded;
  try {
    decoded = JSON.parse(value);
  } catch (_) {
    return { path: '', embedded: [] };
  }
  if (Array.isArray(decoded)) return { path: '', embedded: cricfyLinksFromList(decoded) };
  return { path: '', embedded: [] };
}

function cricfyEventFromJson(json) {
  const linksField = cricfyParseLinksField(json.links);
  const rawNames = json.link_names;
  const rawPriority = json.priority;
  return {
    eventName: cricfyJsonString(json, 'eventName'),
    category: cricfyJsonString(json, 'category'),
    linksPath: linksField.path,
    embeddedLinks: linksField.embedded,
    teamAName: cricfyJsonString(json, 'teamAName'),
    teamBName: cricfyJsonString(json, 'teamBName'),
    teamALogo: cricfyJsonString(json, 'teamALogo'),
    teamBLogo: cricfyJsonString(json, 'teamBLogo'),
    eventLogo: cricfyJsonString(json, 'eventLogo'),
    date: cricfyJsonString(json, 'date'),
    time: cricfyJsonString(json, 'time'),
    endDate: cricfyJsonString(json, 'end_date'),
    endTime: cricfyJsonString(json, 'end_time'),
    linkNames: Array.isArray(rawNames) ? rawNames.map((e) => String(e)) : [],
    priority:
      typeof rawPriority === 'number'
        ? Math.trunc(rawPriority)
        : parseInt(String(rawPriority), 10) || 0,
    visible: cricfyJsonBoolean(json, 'visible'),
  };
}

// Parses `dd/MM/yyyy` + `HH:mm:ss` as GMT via `Date.UTC`, which — like
// Dart's `DateTime.utc` — normalizes an out-of-range component rather than
// throwing; not spec-critical here since the server's dates are always
// well-formed, but it keeps the two implementations' edge-case behavior
// aligned rather than accidentally diverging.
function cricfyParseEventDateTime(date, time) {
  const parts = date.trim().split('/');
  if (parts.length !== 3) return null;
  const day = parseInt(parts[0], 10);
  const month = parseInt(parts[1], 10);
  const year = parseInt(parts[2], 10);
  if (isNaN(day) || isNaN(month) || isNaN(year)) return null;
  const clock = time.trim().split(':');
  const hour = clock.length > 0 ? parseInt(clock[0], 10) || 0 : 0;
  const minute = clock.length > 1 ? parseInt(clock[1], 10) || 0 : 0;
  const second = clock.length > 2 ? parseInt(clock[2], 10) || 0 : 0;
  const ms = Date.UTC(year, month - 1, day, hour, minute, second);
  return isNaN(ms) ? null : new Date(ms);
}

function cricfyEventStatusAt(event, nowMs, fallbackDurationMinutes = null) {
  const now = nowMs != null ? nowMs : Date.now();
  const end = cricfyParseEventDateTime(event.endDate, event.endTime);
  if (end !== null && now >= end.getTime()) return 'ended';
  const start = cricfyParseEventDateTime(event.date, event.time);
  if (
    end === null &&
    start !== null &&
    Number.isFinite(fallbackDurationMinutes) &&
    now >= start.getTime() + fallbackDurationMinutes * 60 * 1000
  ) {
    return 'ended';
  }
  if (start !== null && now >= start.getTime()) return 'live';
  return 'upcoming';
}

function cricfyStreamFormatFromUrl(url) {
  const lower = url.toLowerCase();
  if (lower.indexOf('.mpd') !== -1) return 'dash';
  if (lower.indexOf('.m3u8') !== -1) return 'hls';
  return 'other';
}

function cricfyResponseHeader(response, wanted) {
  const headers = response && response.headers;
  if (!headers || typeof headers !== 'object') return '';
  const lowerWanted = wanted.toLowerCase();
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === lowerWanted) return String(headers[key] || '');
  }
  return '';
}

function cricfyManifestFormatFromResponse(response) {
  const contentType = cricfyResponseHeader(response, 'content-type').toLowerCase();
  const body = String(response && response.body ? response.body : '')
    .replace(/^\uFEFF/, '')
    .trimStart();
  if (
    contentType.indexOf('mpegurl') !== -1 ||
    contentType.indexOf('m3u8') !== -1 ||
    body.startsWith('#EXTM3U')
  ) {
    return 'hls';
  }
  if (contentType.indexOf('dash+xml') !== -1 || /<MPD(?:\s|>)/i.test(body)) {
    return 'dash';
  }
  return 'other';
}

// Validate the manifest before handing it to the native player. Upstream
// mirrors sometimes return an HTML/502 body at a URL that still looks like a
// playlist; letting that body reach the player produces a misleading
// "missing #EXTM3U" parser error and can make a bad source look playable.
async function cricfyValidatePlaybackManifest(url, { headers, format }) {
  // Keep ordinary extensionless media (for example MP4 endpoints) on the
  // native path. A URL that advertises itself as a playlist is cheap to probe,
  // and its response gives us the authoritative format without a provider or
  // host-specific exception.
  const shouldProbeExtensionless =
    format === 'other' && /(?:^|[\/_-])playlist(?:[\/?#_-]|$)/i.test(url);
  if (format === 'other' && !shouldProbeExtensionless) return format;
  const response = await fetch(url, { headers });
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Playback manifest request failed: ${response.status}`);
  }
  const detected =
    format === 'other' ? cricfyManifestFormatFromResponse(response) : format;
  const body = String(response.body || '').trim();
  if (detected === 'hls' && !body.startsWith('#EXTM3U')) {
    throw new Error('Playback response is not an HLS playlist');
  }
  if (detected === 'dash' && !/<MPD(?:\s|>)/i.test(body)) {
    throw new Error('Playback response is not a DASH manifest');
  }
  return detected;
}

// ---- client (port of CricfyClient) ----

let cricfyConfigCache = null;

async function cricfyGetText(url, headers, timeoutMs) {
  // A Cloudflare challenge on Cricfy's catalog API must not block the whole
  // discovery fan-out. Catalog data is optional and can fall back to the
  // persisted event cache; playback sources use their own request path below.
  const response = await fetch(url, {
    headers: {
      ...headers,
      'x-qjsr-disable-cloudflare': '1',
    },
    timeoutMs: timeoutMs || null,
  });
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Cricfy request failed: ${response.status}`);
  }
  return response.body;
}

async function cricfyPostText(url, { headers, body, isJson }) {
  const response = await fetch(url, {
    method: 'POST',
    headers,
    body: isJson ? JSON.stringify(body) : String(body),
  });
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Cricfy request failed: ${response.status}`);
  }
  return response.body;
}

function cricfyDefaultHeaders() {
  return { 'User-Agent': CRICFY_DEFAULT_UA, Accept: 'application/json, text/plain, */*' };
}

function cricfyFallbackConfig() {
  return { Mode: 'GenZ', api_url: CRICFY_API_BASE_URL, enabled: true };
}

async function cricfyConfig() {
  if (cricfyConfigCache !== null) return cricfyConfigCache;
  for (const mirror of CRICFY_CONFIG_MIRRORS) {
    try {
      const body = await cricfyGetText(mirror, {
        'User-Agent': CRICFY_CONFIG_UA,
        Accept: 'application/json, text/plain, */*',
      });
      const decoded = decodeCricfyConfigPayload(body);
      const json = JSON.parse(decoded);
      if (typeof json === 'object' && json !== null && !Array.isArray(json)) {
        cricfyConfigCache = json;
        return json;
      }
    } catch (_) {
      continue;
    }
  }
  cricfyConfigCache = cricfyFallbackConfig();
  return cricfyConfigCache;
}

function cricfyConfigString(cfg, key) {
  const value = cfg[key];
  return typeof value === 'string' ? value.trim() : '';
}

function cricfyConfigFirstNonEmpty(cfg, keys) {
  for (const key of keys) {
    const value = cricfyConfigString(cfg, key);
    if (value.length > 0) return value;
  }
  return '';
}

function cricfyConfigMode(cfg) {
  const value = cricfyConfigString(cfg, 'Mode');
  return value.length === 0 ? 'genz' : value;
}

function cricfyConfigIsSignedApi(cfg) {
  const normalized = cricfyConfigMode(cfg).toLowerCase();
  if (normalized === 'genz' || normalized === 'chilli') return true;
  for (const key of ['getdata_enabled', 'get_data_enabled', 'signed_api_enabled']) {
    const value = cfg[key];
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string' && value.length > 0) return value.toLowerCase() === 'true';
  }
  return true;
}

function cricfyConfigApiUrl(cfg) {
  const value = cricfyConfigFirstNonEmpty(cfg, ['api_url', 'api2', 'api3', 'api_host']);
  return value.length === 0 ? CRICFY_API_BASE_URL : value;
}

function cricfyConfigSignedBaseUrl(cfg) {
  const value = cricfyConfigFirstNonEmpty(cfg, [
    'getdata_base_url',
    'get_data_base_url',
    'signed_api_base_url',
  ]);
  return value.length === 0 ? cricfyConfigApiUrl(cfg) : value;
}

function cricfyConfigSignedEndpoint(cfg) {
  const value = cricfyConfigString(cfg, 'getdata_endpoint');
  return value.length === 0 ? CRICFY_GETDATA_ENDPOINT : value;
}

function cricfyConfigSignedPathPrefix(cfg) {
  const value = cfg['getdata_path_prefix'];
  return typeof value === 'string' ? value : CRICFY_GETDATA_PATH_PREFIX;
}

function cricfyConfigSignedToken(cfg) {
  const value = cricfyConfigFirstNonEmpty(cfg, [
    'getdata_token',
    'get_data_token',
    'signed_api_token',
  ]);
  return value.length === 0 ? CRICFY_GETDATA_TOKEN : value;
}

function cricfyConfigEventsUrl(cfg) {
  return cricfyConfigFirstNonEmpty(cfg, ['events_url', 'events_path']);
}

function cricfyConfigChannelsBaseUrl(cfg) {
  return cricfyConfigFirstNonEmpty(cfg, ['channels_base_url', 'sports_base_url']);
}

function cricfyConfigEventLinksBaseUrl(cfg) {
  return cricfyConfigFirstNonEmpty(cfg, ['event_links_base_url', 'links_base_url']);
}

function cricfyConfigContentBaseUrl(cfg) {
  return cricfyConfigString(cfg, 'content_base_url');
}

function cricfySignedUri(cfg, base, path) {
  return cricfyBuildSignedUrl({
    base,
    endpoint: cricfyConfigSignedEndpoint(cfg),
    path,
    prefix: cricfyConfigSignedPathPrefix(cfg),
    token: cricfyConfigSignedToken(cfg),
  });
}

// `contentOverrideUrl` equivalent — only applies outside GenZ mode.
function cricfyOverrideUrl(cfg, path) {
  if (cricfyConfigMode(cfg).toLowerCase() === 'genz') return '';
  const clean = cricfyTrimLeadingSlash(path);
  const hostUrl = cricfyNormalizeHost(cricfyConfigApiUrl(cfg));
  const resolve = (override) => {
    if (override.length === 0) return '';
    return cricfyIsFullUrl(override) ? override : cricfyJoinUrl(hostUrl, override);
  };
  if (clean === CRICFY_EVENTS_PATH) return resolve(cricfyConfigEventsUrl(cfg));
  if (clean.startsWith('channels/')) {
    const base = cricfyConfigChannelsBaseUrl(cfg);
    return base.length > 0 ? cricfyJoinUrl(base, clean) : '';
  }
  if (clean.startsWith(CRICFY_EVENT_LINKS_PREFIX)) {
    const base = cricfyConfigEventLinksBaseUrl(cfg);
    return base.length > 0 ? cricfyJoinUrl(base, clean) : '';
  }
  const contentBase = cricfyConfigContentBaseUrl(cfg);
  if (contentBase.length > 0) return cricfyJoinUrl(contentBase, clean);
  return '';
}

function cricfyContentUri(cfg, path) {
  const base = cricfyConfigSignedBaseUrl(cfg);
  if (cricfyIsFullUrl(path)) {
    if (!cricfyConfigIsSignedApi(cfg)) return path;
    const relative = cricfyRelativeToBase(path, base);
    if (relative.length === 0) return path;
    return cricfySignedUri(cfg, base, relative);
  }
  const override = cricfyOverrideUrl(cfg, path);
  if (override.length > 0) return override;
  if (cricfyConfigIsSignedApi(cfg)) return cricfySignedUri(cfg, base, path);
  const hostUrl = cricfyNormalizeHost(cricfyConfigApiUrl(cfg));
  return cricfyJoinUrl(hostUrl, path);
}

async function cricfyFetchContent(path) {
  const cfg = await cricfyConfig();
  const fallback = cricfyFallbackConfig();
  const configs = [cfg];
  const configuredUri = cricfyContentUri(cfg, path);
  const fallbackUri = cricfyContentUri(fallback, path);
  if (fallbackUri !== configuredUri) configs.push(fallback);

  let lastError = null;
  for (const candidate of configs) {
    const uri = cricfyContentUri(candidate, path);
    try {
      const body = await cricfyGetText(
        uri,
        cricfyDefaultHeaders(),
        CRICFY_CONTENT_TIMEOUT_MS,
      );
      return decodeCricfyResponse(body);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error(`Cricfy content request failed: ${path}`);
}

// Fetches a list from a file whose every element wraps a JSON string, shape
// `[{"event":"{…}"}, …]` — the wrapper key varies (`event`, `cat`, `channel`).
async function cricfyFetchWrappedList(path, wrapperKey) {
  const text = await cricfyFetchContent(path);
  if (text.trim().length === 0) return [];
  let decoded;
  try {
    decoded = JSON.parse(text);
  } catch (_) {
    throw new Error(`Response for ${path} is not valid JSON`);
  }
  if (!Array.isArray(decoded)) throw new Error(`Response for ${path} is not a JSON array`);

  const items = [];
  for (const entry of decoded) {
    if (typeof entry !== 'object' || entry === null || Array.isArray(entry)) continue;
    const inner = entry[wrapperKey];
    if (typeof inner === 'string' && inner.trim().length > 0) {
      let innerJson;
      try {
        innerJson = JSON.parse(inner);
      } catch (_) {
        innerJson = null;
      }
      if (typeof innerJson === 'object' && innerJson !== null && !Array.isArray(innerJson)) {
        items.push(innerJson);
      }
    } else if (typeof inner === 'object' && inner !== null && !Array.isArray(inner)) {
      items.push(inner);
    } else {
      items.push(entry);
    }
  }
  return items;
}

async function cricfyEvents() {
  const cfg = await cricfyConfig();
  const path = cricfyConfigEventsUrl(cfg) || CRICFY_EVENTS_PATH;
  const items = await cricfyFetchWrappedList(path, 'event');
  const parsed = items.map(cricfyEventFromJson).filter((e) => e.visible);
  cricfyCacheEvents(parsed);
  parsed.sort((a, b) => {
    if (a.priority !== b.priority) return a.priority - b.priority;
    const left = cricfyParseEventDateTime(a.date, a.time);
    const right = cricfyParseEventDateTime(b.date, b.time);
    if (!left || !right) return 0;
    return left.getTime() - right.getTime();
  });
  return parsed;
}

function cricfyApplyNames(links, names) {
  if (names.length === 0) return links;
  return links.map((link, i) =>
    i < names.length && names[i].trim().length > 0
      ? Object.assign({}, link, { name: names[i] })
      : link,
  );
}

async function cricfyLinksFor(path, embedded, names) {
  if (embedded.length > 0) return cricfyApplyNames(embedded, names);
  if (path.trim().length === 0) return [];

  const text = await cricfyFetchContent(path);
  if (text.trim().length === 0) return [];
  let decoded;
  try {
    decoded = JSON.parse(text);
  } catch (_) {
    throw new Error(`Link list for ${path} is not valid JSON`);
  }
  const links = [];
  if (Array.isArray(decoded)) {
    for (const item of decoded) {
      if (typeof item === 'object' && item !== null && !Array.isArray(item)) {
        links.push(cricfyLinkFromJson(item));
      }
    }
  } else if (typeof decoded === 'object' && decoded !== null) {
    links.push(cricfyLinkFromJson(decoded));
  }
  return cricfyApplyNames(links, names);
}

async function cricfyEventLinks(event) {
  return cricfyLinksFor(event.linksPath, event.embeddedLinks, event.linkNames);
}

const CRICFY_MAX_RESOLVE_DEPTH = 4;

async function cricfyNeedsExchange(url) {
  if (!cricfyIsFullUrl(url)) return true;
  const cfg = await cricfyConfig();
  const base = cricfyConfigSignedBaseUrl(cfg);
  return cricfyRelativeToBase(url, base).length > 0;
}

// Exchanges an API path/URL for a link object carrying the real stream URL.
// A nested `playlist` field means one more level of descent is needed.
async function cricfyExchange(path, source) {
  const text = await cricfyFetchContent(path);
  if (text.trim().length === 0) throw new Error(`Server returned no link for ${path}`);
  let decoded;
  try {
    decoded = JSON.parse(text);
  } catch (_) {
    throw new Error(`Link response for ${path} is not JSON`);
  }
  const entries = Array.isArray(decoded) ? decoded : [decoded];
  if (entries.length === 0) throw new Error(`Empty link list for ${path}`);
  const first = entries[0];
  if (typeof first !== 'object' || first === null || Array.isArray(first)) {
    throw new Error(`Unrecognized link shape for ${path}`);
  }

  const playlist = first.playlist;
  if (playlist !== undefined && playlist !== null) {
    if (typeof playlist === 'string' && playlist.trim().length > 0) {
      return {
        name: source.name,
        link: playlist,
        drmApi: '',
        tokenApi: '',
        audio: '',
        scheme: 'clearKey',
        secureDecoder: false,
      };
    }
    if (Array.isArray(playlist) && playlist.length > 0) {
      const item = playlist[0];
      if (typeof item === 'object' && item !== null) return cricfyLinkFromJson(item);
    }
    throw new Error(`Empty playlist for ${path}`);
  }
  return cricfyLinkFromJson(first);
}

function cricfyExtractKey(payload, key) {
  if (typeof payload === 'object' && payload !== null && !Array.isArray(payload)) {
    const direct = payload[key];
    if (typeof direct === 'string' && direct.length > 0) return direct;
    for (const value of Object.values(payload)) {
      const nested = cricfyExtractKey(value, key);
      if (nested !== null) return nested;
    }
  } else if (Array.isArray(payload)) {
    for (const value of payload) {
      const nested = cricfyExtractKey(value, key);
      if (nested !== null) return nested;
    }
  }
  return null;
}

// ---- `tokenApi` type "embed" ----
//
// An embed entry carries no `url`; its target is `api`, an HTML page rather
// than the JSON the plain token flow expects. The page is a wrapper whose
// iframe holds a Clappr player, and the player's `source:` is the playback
// URL under `window.atob`. Two hops, both plain HTML:
//
//   api (stream-N.php)  ->  <iframe src="…/daddy.php?id=N">
//   iframe              ->  source: window.atob('<base64 m3u8 URL>')
//
// The signed URL 403s without the iframe's `Referer`/`Origin`, so those ride
// back on the returned string in the usual `url|Header=value` form and reach
// the player through the caller's existing header merge.

const CRICFY_EMBED_IFRAME = /<iframe[^>]+src=["']([^"']+)["']/i;
const CRICFY_EMBED_SOURCE = /source\s*:\s*(?:window\.)?atob\(\s*["']([A-Za-z0-9+/=]+)["']\s*\)/i;

function cricfyEmbedOrigin(url) {
  const match = /^(https?:\/\/[^/?#]+)/i.exec(url.trim());
  return match ? match[1] : '';
}

// `//host/path` is protocol-relative, not a path — resolve it against the
// page's own scheme rather than treating it as relative to the origin.
function cricfyEmbedAbsolute(candidate, baseUrl) {
  const value = candidate.trim();
  if (/^https?:\/\//i.test(value)) return value;
  const origin = cricfyEmbedOrigin(baseUrl);
  if (origin.length === 0) return '';
  if (value.startsWith('//')) return `${origin.split('://')[0]}:${value}`;
  if (value.startsWith('/')) return origin + value;
  return `${origin}/${value}`;
}

async function cricfyResolveEmbedUrl(apiUrl) {
  const target = apiUrl.trim();
  if (target.length === 0) throw new Error('embed tokenApi has no api url');

  const wrapper = await cricfyGetText(target, {
    'User-Agent': CRICFY_DEFAULT_UA,
  });
  const iframeMatch = CRICFY_EMBED_IFRAME.exec(wrapper);
  if (iframeMatch === null) throw new Error('embed page has no iframe');
  const iframeUrl = cricfyEmbedAbsolute(iframeMatch[1], target);
  if (iframeUrl.length === 0) throw new Error('embed iframe url is not absolute');

  const origin = cricfyEmbedOrigin(target);
  const player = await cricfyGetText(iframeUrl, {
    'User-Agent': CRICFY_DEFAULT_UA,
    Referer: origin.length === 0 ? target : `${origin}/`,
  });
  const sourceMatch = CRICFY_EMBED_SOURCE.exec(player);
  if (sourceMatch === null) throw new Error('embed player has no source');

  let playbackUrl;
  try {
    playbackUrl = host.codec.base64ToText(sourceMatch[1]).trim();
  } catch (_) {
    throw new Error('embed source is not valid base64');
  }
  if (!cricfyIsFullUrl(playbackUrl)) {
    throw new Error('embed source did not decode to a url');
  }

  // Without these the signed playlist answers 403.
  const iframeOrigin = cricfyEmbedOrigin(iframeUrl);
  if (iframeOrigin.length === 0) return playbackUrl;
  return `${playbackUrl}|Referer=${iframeOrigin}/&Origin=${iframeOrigin}`;
}

// Runs the `tokenApi` flow and returns the playback URL. No real captured
// fixture exists for this path (the Dart client's own test suite has none
// either) — the JS unit tests build one from the exact shape this function
// (and its Dart original) expect, using `CricfyCodec.encodePayload`, the
// same wire encoding used by the captured fixture helpers.
async function cricfyResolveTokenUrl(blob) {
  const decoded = decodeCricfyPayload(blob);
  let json;
  try {
    json = JSON.parse(decoded);
  } catch (_) {
    throw new Error('tokenApi blob is not a JSON object');
  }
  if (typeof json !== 'object' || json === null || Array.isArray(json)) {
    throw new Error('tokenApi blob is not a JSON object');
  }

  const type = String(json.type ?? 'token').toLowerCase();
  if (type === 'daddy') {
    throw new Error('tokenApi type "daddy" is not supported by this client');
  }
  if (type === 'embed') return cricfyResolveEmbedUrl(String(json.api ?? ''));

  const split = cricfySplitLinkAndHeaders(String(json.url ?? ''));
  if (split.url.length === 0) throw new Error('tokenApi did not include a url');

  const headers = cricfyMergeHeaders([
    { 'User-Agent': CRICFY_DEFAULT_UA },
    cricfyParseHeaderQuery(String(json.api ?? '')),
    split.headers,
  ]);
  const linkKey = String(json.link_key ?? 'playback_url');
  const requestType = String(json.request_type ?? 'get').toLowerCase();
  const bodyType = String(json.request_body_type ?? 'normal').toLowerCase();
  const requestBody = String(json.request_body ?? '');
  const isJson = bodyType === 'json';

  const responseText =
    requestType === 'post'
      ? await cricfyPostText(split.url, {
          headers,
          body: isJson && requestBody.length > 0 ? JSON.parse(requestBody) : requestBody,
          isJson,
        })
      : await cricfyGetText(split.url, headers);

  const payload = JSON.parse(decodeCricfyPayload(responseText));
  const extracted = cricfyExtractKey(payload, linkKey);
  if (extracted === null || extracted.length === 0) {
    throw new Error(`tokenApi did not return "${linkKey}"`);
  }
  return extracted;
}

function cricfyBuildDrm(link) {
  const api = link.drmApi.trim();
  if (api.length === 0) return null;
  if (cricfyIsFullUrl(api)) return { scheme: link.scheme, licenseUrl: api };
  const clearKey = cricfyToClearKeyJson(api);
  if (clearKey === null) return null;
  return { scheme: 'clearKey', clearKeyJson: clearKey };
}

// Turns a `CricfyLink` into a ready-to-play stream. Handles three cases: a
// link that's already a stream URL, one that needs exchanging through the
// signed endpoint first, and one that needs a `tokenApi` call.
async function cricfyResolveStreamAt(link, depth) {
  if (depth > CRICFY_MAX_RESOLVE_DEPTH) throw new Error('Link resolution looped too deep');

  const split = cricfySplitLinkAndHeaders(link.link);
  const hasTokenApi = link.tokenApi.trim().length > 0;
  // A link that carries only a `tokenApi` is normal, not malformed: the
  // playback URL is what that call returns. Only a link with neither is empty.
  if (split.url.length === 0 && !hasTokenApi) throw new Error('Empty link');

  if (split.url.length > 0 && (await cricfyNeedsExchange(split.url))) {
    const resolved = await cricfyExchange(split.url, link);
    return cricfyResolveStreamAt(resolved, depth + 1);
  }

  let finalUrl = split.url;
  if (hasTokenApi) {
    finalUrl = await cricfyResolveTokenUrl(link.tokenApi);
  }

  const finalSplit = cricfySplitLinkAndHeaders(finalUrl);
  const merged = cricfyMergeHeaders([
    { 'User-Agent': CRICFY_DEFAULT_UA },
    split.headers,
    finalSplit.headers,
  ]);
  const format = cricfyStreamFormatFromUrl(finalSplit.url);
  const validatedFormat = await cricfyValidatePlaybackManifest(finalSplit.url, {
    headers: merged,
    format,
  });

  return {
    url: finalSplit.url,
    headers: merged,
    format: validatedFormat,
    drm: cricfyBuildDrm(link),
    audioUrl: link.audio.length === 0 ? null : link.audio,
    label: link.name,
  };
}

function cricfyResolveStream(link) {
  return cricfyResolveStreamAt(link, 0);
}

// ---- CricfyBroadcastSource equivalent ----

function cricfyIsLiveOrUpcoming(event) {
  const status = cricfyEventStatusAt(event);
  return status === 'live' || status === 'upcoming';
}

// Live-or-upcoming candidates are kept broad because source resolution is
// driven by the selected item's participants and kickoff. Non-matching
// events are discarded by the matcher.
function cricfyCandidatesFrom(events) {
  const out = [];
  for (const event of events) {
    if (cricfyIsLiveOrUpcoming(event)) {
      const start = cricfyParseEventDateTime(event.date, event.time);
      out.push({
        teamA: event.teamAName,
        teamB: event.teamBName,
        startsAt: start ? start.toISOString() : null,
        event,
      });
    }
  }
  return out;
}

// ---- the schedule, cached across launches ----
//
// `host.storage` is a cache an extension may use, never one it may rely on:
// an older host has no storage at all, a value can be dropped between
// launches, and a write can be refused for being too big. Every path here
// therefore treats a miss as ordinary and falls through to the network.

function cricfyStorage() {
  return typeof host === 'object' && host !== null && host.storage
    ? host.storage
    : null;
}

function cricfyCacheEvents(events) {
  const storage = cricfyStorage();
  if (storage === null) return;
  try {
    storage.write(
      CRICFY_EVENTS_CACHE_KEY,
      JSON.stringify(events),
      CRICFY_EVENTS_CACHE_TTL_MS,
    );
  } catch (_) {
    // A cache that won't take the value changes nothing about this session.
  }
}

// Returns the stored schedule, or null when there isn't a usable one. The
// events were written as already-parsed objects, so nothing here repeats the
// decode — that is most of what makes reading them cheap.
function cricfyCachedEvents() {
  const storage = cricfyStorage();
  if (storage === null) return null;
  let raw;
  try {
    raw = storage.read(CRICFY_EVENTS_CACHE_KEY);
  } catch (_) {
    return null;
  }
  if (typeof raw !== 'string' || raw.length === 0) return null;
  let decoded;
  try {
    decoded = JSON.parse(raw);
  } catch (_) {
    return null;
  }
  if (!Array.isArray(decoded) || decoded.length === 0) return null;
  for (const event of decoded) {
    if (typeof event !== 'object' || event === null) return null;
    if (typeof event.date !== 'string' || typeof event.time !== 'string') {
      return null;
    }
  }
  return decoded;
}

// Events list is a forward schedule, same shape as fixtures.js's own TV
// guide memo — cached for CRICFY_EVENTS_TTL_MS, not the engine's whole
// lifetime. A plain never-expiring memo (the original shape here) meant a
// fixture added to Cricfy's events.txt after the first fetch of a session
// never appeared — no source, and never showing under the "live" category —
// no matter how many times the app was refreshed, since the catalog protocol
// has no refresh signal for an extension to key off. Cleared on failure so a
// later call can retry rather than being stuck with a rejected promise.
const CRICFY_EVENTS_TTL_MS = 15 * 60 * 1000;
let cricfyEventsMemo = null;

function cricfyFetchEventsMemo(nowMs) {
  const now = nowMs != null ? nowMs : Date.now();
  if (cricfyEventsMemo === null) {
    const cached = cricfyCachedEvents();
    if (cached !== null) {
      // Serve last launch's schedule now and fetch behind it. The cached
      // copy is dated by the statuses derived from each event's own kickoff,
      // not by when it was stored, so a few hours old still answers "what is
      // live right now" correctly for everything already on it — and what it
      // can't know about (an event added since) arrives with the refresh,
      // rather than holding up every source lookup until it does.
      cricfyEventsMemo = { promise: Promise.resolve(cached), fetchedAt: now };
      cricfyRefreshEventsInBackground();
      return cricfyEventsMemo.promise;
    }
  }
  if (
    cricfyEventsMemo === null ||
    now - cricfyEventsMemo.fetchedAt >= CRICFY_EVENTS_TTL_MS
  ) {
    const promise = cricfyEvents().catch((e) => {
      cricfyEventsMemo = null;
      throw e;
    });
    cricfyEventsMemo = { promise, fetchedAt: now };
  }
  return cricfyEventsMemo.promise;
}

// Replaces a cache-seeded memo once the real list lands. Deliberately not
// awaited by anyone: the caller already has an answer, and this one is only
// worth having if it arrives. At most one runs at a time, and a failure
// leaves the seeded memo in place — the cached schedule is still better than
// nothing, and the normal TTL will try again.
let cricfyBackgroundRefresh = null;

function cricfyRefreshEventsInBackground() {
  if (cricfyBackgroundRefresh !== null) return;
  cricfyBackgroundRefresh = cricfyEvents().then(
    (events) => {
      cricfyBackgroundRefresh = null;
      cricfyEventsMemo = {
        promise: Promise.resolve(events),
        fetchedAt: Date.now(),
      };
    },
    () => {
      cricfyBackgroundRefresh = null;
    },
  );
}

// Resolved links are cached by a stable link key so repeated discovery can
// replace the same source instead of making the picker show it twice. The
// cache is capped so a long session can't grow it forever.
let cricfyLinkCache = {};
const CRICFY_MAX_LINK_CACHE_ENTRIES = 500;

function cricfyTrimLinkCache() {
  const keys = Object.keys(cricfyLinkCache);
  const overflow = keys.length - CRICFY_MAX_LINK_CACHE_ENTRIES;
  if (overflow <= 0) return;
  for (const key of keys.slice(0, overflow)) delete cricfyLinkCache[key];
}

function cricfyLinkHost(link) {
  const candidates = [link.link, link.tokenApi, link.drmApi, link.audio];
  for (const candidate of candidates) {
    const value = String(candidate ?? '').trim().split('|')[0];
    const match = /^https?:\/\/([^/?#]+)/i.exec(value);
    if (match) return match[1].toLowerCase();
  }
  return '';
}

function cricfySourceIdentity(link) {
  const name = String(link.name ?? '').trim().toLowerCase();
  const hostName = cricfyLinkHost(link);
  if (name.length > 0 && hostName.length > 0) return `${name}@${hostName}`;
  if (name.length > 0) return `name:${name}`;
  if (hostName.length > 0) return `host:${hostName}`;

  const path = String(link.link ?? '').trim().split(/[|?#]/)[0].toLowerCase();
  return path.length > 0 ? `path:${path}` : 'unknown';
}

function cricfyEventSourceKey(event) {
  const path = String(event.linksPath ?? '').trim().toLowerCase();
  if (path.length > 0) return `path:${path}`;
  return [
    event.eventName,
    event.teamAName,
    event.teamBName,
    event.date,
    event.time,
  ]
    .map((value) => String(value ?? '').trim().toLowerCase())
    .join('|');
}

function cricfySourceCacheKey(event, link) {
  const stable = {
    event: cricfyEventSourceKey(event),
    name: String(link.name ?? '').trim().toLowerCase(),
    link: String(link.link ?? '').trim().split(/[|?#]/)[0].toLowerCase(),
    tokenApi: String(link.tokenApi ?? '').trim().split(/[|?#]/)[0].toLowerCase(),
    drmApi: String(link.drmApi ?? '').trim().split(/[|?#]/)[0].toLowerCase(),
    audio: String(link.audio ?? '').trim().split(/[|?#]/)[0].toLowerCase(),
  };
  return host.codec
    .textToBase64(JSON.stringify(stable))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

async function cricfySourcesForEvent(event) {
  const links = await cricfyEventLinks(event);
  const sources = [];
  for (let i = 0; i < links.length; i++) {
    const id = cricfySourceCacheKey(event, links[i]);
    const identity = cricfySourceIdentity(links[i]);
    const label = sourceAliasWithQuality(
      `${CRICFY_PROVIDER_KEY}:${identity}`,
      null,
      links[i].name || `Cricfy Link ${i + 1}`,
    );
    cricfyLinkCache[id] = { ...links[i], name: label };
    sources.push({
      id: `${CRICFY_PROVIDER_KEY}:${id}`,
      label,
      provider: 'Nimora',
      providerId: 'nimora.cricfy',
    });
  }
  cricfyTrimLinkCache();
  return sources;
}

function cricfyIsMotorsportItem(item) {
  return /motogp|motorsport|formula|nascar|racing|mxgp|wrc/i.test(
    `${item?.title || ''} ${item?.subtitle || ''}`,
  );
}

function cricfyFindMotorsportEvent(events, item) {
  if (!cricfyIsMotorsportItem(item)) return null;
  const kickoff = Date.parse(item.schedule?.startsAt);
  if (!Number.isFinite(kickoff)) return null;
  return events
    .filter((event) => event.category === 'Motorsport')
    .map((event) => ({
      event,
      kickoff: cricfyParseEventDateTime(event.date, event.time),
    }))
    .filter((candidate) => candidate.kickoff != null)
    .map((candidate) => ({
      ...candidate,
      distance: Math.abs(candidate.kickoff.getTime() - kickoff),
    }))
    .filter((candidate) => candidate.distance <= 6 * 60 * 60 * 1000)
    .sort((a, b) => a.distance - b.distance)[0]?.event || null;
}

function cricfyMapDrm(drm) {
  if (!drm) return null;
  if (drm.scheme === 'clearKey') return { scheme: 'clearKey', clearKeyJson: drm.clearKeyJson };
  if (drm.scheme === 'widevine') return { scheme: 'widevine', licenseUrl: drm.licenseUrl };
  // PlayReady isn't supported on this app's players — mapped to
  // "unsupported" so the UI shows an honest message instead of trying to
  // play and failing, same as CricfyBroadcastSource._mapDrm.
  return { scheme: 'unsupported' };
}

async function resolveCricfySource(sourceId) {
  const prefix = `${CRICFY_PROVIDER_KEY}:`;
  const inner = sourceId.startsWith(prefix) ? sourceId.slice(prefix.length) : sourceId;
  const link = cricfyLinkCache[inner];
  if (!link) throw new Error(`Cricfy source expired: ${sourceId}`);
  const stream = await cricfyResolveStream(link);
  return {
    url: stream.url,
    headers: stream.headers,
    format: stream.format,
    drm: cricfyMapDrm(stream.drm),
    audioUrl: stream.audioUrl,
    label: stream.label,
  };
}

async function cricfySources(args) {
  const item = args.item;
  const enabled = args.enabledProviders;
  if (enabled != null && enabled.indexOf(CRICFY_PROVIDER_ID) === -1) return { sources: [] };

  let events;
  try {
    events = await cricfyFetchEventsMemo();
  } catch (_) {
    return { sources: [] };
  }

  const catalogPrefix = 'cricfy:';
  const itemId = item.ref && String(item.ref.id || '');
  if (itemId.startsWith(catalogPrefix)) {
    const linksPath = itemId.slice(catalogPrefix.length);
    const event = events.find((candidate) => candidate.linksPath === linksPath);
    if (!event) return { sources: [] };
    try {
      return { sources: await cricfySourcesForEvent(event) };
    } catch (_) {
      return { sources: [] };
    }
  }

  // A shared catalog card may keep Roxie's or another provider's stable id.
  // Generic events such as Formula 1 have no participants, so recover the
  // Cricfy event by its canonical catalog title before declining the item.
  const titleKey = typeof catalogTitleKey === 'function'
    ? catalogTitleKey
    : (value) => String(value || '').trim().toLowerCase()
        .replace(/[^a-z0-9]+/g, ' ')
        .replace(/\s+/g, ' ')
        .replace(/\bformula one\b|\bf1\b/g, 'formula 1')
        .replace(/\bmoto gp\b/g, 'motogp')
        .trim();
  const itemTitle = titleKey(item.title);
  if (itemTitle.length > 0) {
    const event = events.find((candidate) =>
      titleKey(candidate.eventName) === itemTitle);
    if (event) {
      try {
        return { sources: await cricfySourcesForEvent(event) };
      } catch (_) {
        return { sources: [] };
      }
    }
  }

  // SPOTV supplies the canonical motorsport title, while Cricfy may publish
  // the same broadcast under a generic name such as "MotoGP". Match the
  // provider event by category and nearest kickoff before requiring teams.
  const motorsportEvent = cricfyFindMotorsportEvent(events, item);
  if (motorsportEvent) {
    try {
      return { sources: await cricfySourcesForEvent(motorsportEvent) };
    } catch (_) {
      return { sources: [] };
    }
  }

  if (!item.participants || item.participants.length !== 2) return { sources: [] };
  const candidates = cricfyCandidatesFrom(events);
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
    { profile: CRICFY_FOOTBALL_PROFILE },
  );
  if (!result) return { sources: [] };

  try {
    return { sources: await cricfySourcesForEvent(candidates[result.index].event) };
  } catch (_) {
    return { sources: [] };
  }
}

// ---- registration — see kora.js's tail for the shared aggregator ----

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: CRICFY_PROVIDER_KEY,
  sources: cricfySources,
  resolve: (sourceId) => resolveCricfySource(sourceId),
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
