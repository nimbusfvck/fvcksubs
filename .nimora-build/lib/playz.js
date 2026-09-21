// PlayZTV live events stream provider.
//
// The upstream plugin is a callback-based SkyStream extension. Nimora keeps
// the same event/link protocol, but exposes only the v2 stream-provider
// contract. It matches against the existing FotMob catalog; it does not add
// a catalog or shelf of its own. URLs are resolved again when selected so
// signed/tokenized links never become stale source ids.

const PLAYZ_PROVIDER_ID = 'nimora.playz';
const PLAYZ_PROVIDER_KEY = 'playz';
const PLAYZ_REMOTE_CONFIG_URL =
  'https://firebaseremoteconfig.googleapis.com/v1/projects/516859456626/namespaces/firebase:fetch';
const PLAYZ_FIREBASE_API_KEY =
  'AIzaSyDKRqLlbaZBIpHzLBiQTUrJqr3gN-nDWWc';
const PLAYZ_FIREBASE_APP_ID =
  '1:516859456626:android:12a75869902c4f8a6826eb';
const PLAYZ_DEFAULT_BASE_URLS = [
  'https://tourniquest.site',
  'https://adsflw.xyz',
  'https://playztv2828.store',
];
const PLAYZ_PRIMARY_KEY = 'Yi8xam1sNW5rNHg1azdwTg==';
const PLAYZ_PRIMARY_IV = 'MTRuTWs4bU41S2w1S0w3bA==';
const PLAYZ_LEGACY_KEY = 'bTVLbDVuazR4SzFrTjdwTg==';
const PLAYZ_LEGACY_IV = 'azVLNG5NOG1LbE5MN2wxNQ==';
const PLAYZ_NATIVE_KEY = 'cz14RStkN01PVE5w';
const PLAYZ_NATIVE_IV = 'WTlEvckd2UR41sdk';
const PLAYZ_SUBSTITUTION_FROM =
  'aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ';
const PLAYZ_SUBSTITUTION_TO =
  'fFgGjJkKaApPbBmMoOzZeEnNcCdDrRqQtTvVuUxXhHiIwWyYlLsS';
const PLAYZ_REVERSE_SUBSTITUTION = {};

for (let i = 0; i < PLAYZ_SUBSTITUTION_TO.length; i++) {
  PLAYZ_REVERSE_SUBSTITUTION[PLAYZ_SUBSTITUTION_TO[i]] =
    PLAYZ_SUBSTITUTION_FROM[i];
}

const PLAYZ_UA =
  'Dalvik/2.1.0 (Linux; U; Android 10; SM-A505F)';

// Keep PlayZTV's matching independent from the full profile's Kora source.
// Compact bundles do not include kora.js, but both profiles still need to
// match PlayZTV broadcasts against FotMob's existing match items.
const PLAYZ_MATCH_PROFILE = {
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

function playzText(value) {
  if (value == null) return '';
  return String(value).trim();
}

function playzJson(value) {
  try {
    return JSON.parse(String(value || ''));
  } catch (_) {
    return null;
  }
}

function playzInstanceId() {
  let value = '';
  while (value.length < 32) {
    value += Math.random().toString(16).slice(2);
  }
  return value.slice(0, 32);
}

function playzBase64Url(value) {
  return host.codec.textToBase64(JSON.stringify(value))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function playzFromBase64Url(value) {
  let base64 = playzText(value).replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4) base64 += '=';
  return JSON.parse(host.codec.base64ToText(base64));
}

function playzAbsoluteUrl(base, value) {
  const target = playzText(value);
  if (/^https?:\/\//i.test(target)) return target;
  const originMatch = /^(https?:\/\/[^/]+)/i.exec(playzText(base));
  if (!originMatch || !target) return '';
  if (target.startsWith('//')) return `${originMatch[1].split('://')[0]}:${target}`;
  if (target.startsWith('/')) return `${originMatch[1]}${target}`;
  return `${playzText(base).replace(/\/+$/, '')}/${target.replace(/^\/+/, '')}`;
}

function playzResponseText(response) {
  return response && typeof response.body === 'string' ? response.body : '';
}

function playzDecodeSubstitution(value) {
  return [...playzText(value)].map(
    (char) => PLAYZ_REVERSE_SUBSTITUTION[char] || char,
  ).join('');
}

function playzNormalizeBase64(value) {
  let normalized = playzText(value)
    .replace(/\s/g, '')
    .replace(/-/g, '+')
    .replace(/_/g, '/');
  while (normalized.length % 4) normalized += '=';
  return normalized;
}

// The primary provider payload has two Base64 layers:
// substitution(payload) -> Base64(ciphertext) -> AES-128-CBC(JSON).
function playzDecodeSubstitutionPayload(value) {
  const restored = playzDecodeSubstitution(value);
  return host.codec.base64ToText(playzNormalizeBase64(restored));
}

function playzAesJson(payload, key, iv) {
  try {
    const plain = host.crypto.aesCbcDecrypt(
      key,
      iv,
      playzNormalizeBase64(payload),
    );
    if (plain == null) return '';
    return playzText(host.codec.base64ToText(plain));
  } catch (_) {
    return '';
  }
}

function playzSwapAdjacent(value) {
  const chars = [...value];
  for (let index = 0; index + 1 < chars.length; index += 2) {
    const temp = chars[index];
    chars[index] = chars[index + 1];
    chars[index + 1] = temp;
  }
  return chars.join('');
}

// Current PlayZTV feeds use the native plugin's byte transform before AES:
// Base64 -> reverse bytes -> swap adjacent bytes -> Base64 -> AES-CBC.
function playzNativeCiphertext(value) {
  const decoded = host.codec.base64ToText(playzNormalizeBase64(value));
  return playzSwapAdjacent([...decoded].reverse().join(''));
}

// Compatibility format used by the Android provider: the ciphertext is
// reconstructed from the first/last 10 characters while IV and key are
// embedded in the middle and tail of the payload.
function playzDecodeEmbeddedEnvelope(value) {
  const raw = playzText(value).replace(/\s/g, '');
  if (raw.length < 79) return '';
  const encrypted = raw.slice(0, 10) + raw.slice(34, raw.length - 54) + raw.slice(-10);
  const iv = raw.slice(10, 34);
  const key = raw.slice(raw.length - 54, raw.length - 10);
  return playzAesJson(encrypted, key, iv);
}

function playzDecodeEncrypted(value) {
  const raw = playzText(value);
  if (!raw) return '';
  if (raw.startsWith('{') || raw.startsWith('[')) return raw;

  let native = '';
  try {
    native = playzAesJson(
      playzNativeCiphertext(raw),
      host.codec.textToBase64(PLAYZ_NATIVE_KEY),
      host.codec.textToBase64(PLAYZ_NATIVE_IV),
    );
  } catch (_) {}
  if (native.startsWith('{') || native.startsWith('[')) return native;

  const primary = playzAesJson(
    playzDecodeSubstitutionPayload(raw),
    PLAYZ_PRIMARY_KEY,
    PLAYZ_PRIMARY_IV,
  );
  if (primary.startsWith('{') || primary.startsWith('[')) return primary;

  const fallback = playzAesJson(raw, PLAYZ_LEGACY_KEY, PLAYZ_LEGACY_IV);
  if (fallback.startsWith('{') || fallback.startsWith('[')) return fallback;

  const embedded = playzDecodeEmbeddedEnvelope(raw);
  if (embedded.startsWith('{') || embedded.startsWith('[')) return embedded;

  return '';
}

async function playzFetch(url, options) {
  const response = await fetch(url, options || {});
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`PlayZTV request failed: ${response.status}`);
  }
  return response;
}

async function playzRemoteBases() {
  const override = globalThis.__playzBaseUrls;
  if (Array.isArray(override)) return override.filter((value) => playzText(value));

  try {
    const response = await playzFetch(PLAYZ_REMOTE_CONFIG_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-Android-Package': 'com.playz.tv',
        'X-Goog-Api-Key': PLAYZ_FIREBASE_API_KEY,
        'User-Agent': 'okhttp/4.12.0',
      },
      body: JSON.stringify({
        appInstanceId: playzInstanceId(),
        appInstanceIdToken: '',
        appId: PLAYZ_FIREBASE_APP_ID,
        countryCode: 'US',
        languageCode: 'en-US',
        platformVersion: '30',
        timeZone: 'UTC',
        appVersion: '2.1',
        appBuild: '4',
        packageName: 'com.playz.tv',
        sdkVersion: '22.1.0',
        analyticsUserProperties: {},
      }),
    });
    const data = playzJson(playzResponseText(response));
    const configured = data && data.entries && data.entries.api_url;
    if (playzText(configured)) return [configured, ...PLAYZ_DEFAULT_BASE_URLS];
  } catch (_) {
    // The static mirrors remain useful when Remote Config is unavailable.
  }
  return PLAYZ_DEFAULT_BASE_URLS.slice();
}

let playzBasesMemo = null;
async function playzBaseUrls() {
  if (playzBasesMemo == null) {
    playzBasesMemo = playzRemoteBases().then((values) => {
      const seen = new Set();
      return values
        .map((value) => playzText(value).replace(/\/+$/, ''))
        .filter((value) => /^https?:\/\//i.test(value) && !seen.has(value) && seen.add(value));
    });
  }
  return playzBasesMemo;
}

async function playzFetchDecoded(path) {
  const target = playzText(path);
  if (!target) return '';
  const bases = await playzBaseUrls();
  for (const base of bases) {
    try {
      const response = await playzFetch(
        playzAbsoluteUrl(base, target),
        { headers: { 'User-Agent': PLAYZ_UA, Accept: '*/*' } },
      );
      const decoded = playzDecodeEncrypted(playzResponseText(response));
      if (decoded) return decoded;
    } catch (_) {
      // Continue to the next mirror.
    }
  }
  return '';
}

async function playzFetchJson(path) {
  const decoded = await playzFetchDecoded(path);
  const data = playzJson(decoded);
  return data;
}

function playzDate(date, time) {
  const dateMatch = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(playzText(date));
  const timeMatch = /^(\d{1,2}):(\d{1,2})(?::(\d{1,2}))?$/.exec(playzText(time));
  if (!dateMatch || !timeMatch) return null;
  const ms = Date.UTC(
    Number(dateMatch[3]), Number(dateMatch[2]) - 1, Number(dateMatch[1]),
    Number(timeMatch[1]), Number(timeMatch[2]), Number(timeMatch[3] || 0),
  );
  return Number.isFinite(ms) ? new Date(ms) : null;
}

function playzStatus(event, now) {
  const end = playzDate(event.endDate, event.endTime);
  if (end && now >= end.getTime()) return 'ended';
  const start = playzDate(event.date, event.time);
  if (start && now >= start.getTime()) return 'live';
  return 'upcoming';
}

function playzCategory(value) {
  const category = playzText(value) || 'Other';
  if (/cricket/i.test(category)) return 'Cricket';
  if (/football|soccer/i.test(category)) return 'Football';
  if (/basketball/i.test(category)) return 'Basketball';
  if (/tennis/i.test(category)) return 'Tennis';
  if (/boxing/i.test(category)) return 'Boxing';
  if (/motorsport|formula|racing/i.test(category)) return 'Motorsport';
  if (/wwe|wrestling/i.test(category)) return 'WWE';
  return category;
}

function playzEventTitle(event) {
  const home = playzText(event.teamAName);
  const away = playzText(event.teamBName);
  if (home && away && home !== away) return `${home} vs ${away}`;
  return playzText(event.eventName) || 'Live Event';
}

function playzNormalizeEvent(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const event = typeof raw.event === 'string' ? playzJson(raw.event) : raw;
  if (!event || event.visible === false) return null;
  const linksPath = playzText(event.links);
  if (!linksPath) return null;
  return {
    category: playzCategory(event.category),
    eventName: playzText(event.eventName),
    eventLogo: playzText(event.eventLogo),
    teamAName: playzText(event.teamAName),
    teamBName: playzText(event.teamBName),
    teamAFlag: playzText(event.teamAFlag),
    teamBFlag: playzText(event.teamBFlag),
    linksPath,
    date: playzText(event.date),
    time: playzText(event.time),
    endDate: playzText(event.end_date),
    endTime: playzText(event.end_time),
    priority: Number.isFinite(event.priority) ? event.priority : Number(event.priority || 0),
    linkNames: Array.isArray(event.link_names) ? event.link_names : [],
  };
}

function playzEvents(data) {
  if (!Array.isArray(data)) return [];
  return data.map(playzNormalizeEvent).filter((event) => event != null);
}

let playzEventsMemo = null;
async function playzLoadEvents() {
  if (playzEventsMemo == null) {
    playzEventsMemo = playzFetchJson('events.txt').then(playzEvents).catch((error) => {
      playzEventsMemo = null;
      throw error;
    });
  }
  return playzEventsMemo;
}

function playzSplit(value) {
  const parts = playzText(value).split('|');
  const headers = {};
  for (const part of parts.slice(1)) {
    const index = part.indexOf('=');
    if (index <= 0) continue;
    let headerValue = part.slice(index + 1);
    try { headerValue = decodeURIComponent(headerValue); } catch (_) {}
    headers[part.slice(0, index)] = headerValue;
  }
  return { url: parts[0], headers };
}

function playzEntries(value) {
  if (Array.isArray(value)) return value.filter((entry) => entry && typeof entry === 'object');
  return value && typeof value === 'object' ? [value] : [];
}

function playzSourceId(payload) {
  return `${PLAYZ_PROVIDER_KEY}:${playzBase64Url(payload)}`;
}

async function playzSourcesForEvent(event) {
  const links = playzEntries(await playzFetchJson(event.linksPath));
  return links.map((link, index) => ({
    id: playzSourceId({ p: event.linksPath, i: index, n: event.linkNames || [] }),
    label: playzText(link.name) || playzText(event.linkNames && event.linkNames[index]) || `PlayZTV ${index + 1}`,
    provider: 'Nimora',
    providerId: PLAYZ_PROVIDER_ID,
  }));
}

function playzIsMotorsportItem(item) {
  return /motogp|motorsport|formula|nascar|racing|mxgp|wrc/i.test(
    `${item?.title || ''} ${item?.subtitle || ''}`,
  );
}

function playzFindMotorsportEvent(events, item) {
  if (!playzIsMotorsportItem(item)) return null;
  const kickoff = Date.parse(item.schedule?.startsAt);
  if (!Number.isFinite(kickoff)) return null;
  return events
    .filter((event) => event.category === 'Motorsport')
    .map((event) => ({
      event,
      kickoff: playzDate(event.date, event.time),
    }))
    .filter((candidate) => candidate.kickoff != null)
    .map((candidate) => ({
      ...candidate,
      distance: Math.abs(candidate.kickoff.getTime() - kickoff),
    }))
    .filter((candidate) => candidate.distance <= 6 * 60 * 60 * 1000)
    .sort((a, b) => a.distance - b.distance)[0]?.event || null;
}

async function playzSources(args) {
  if (args.enabledProviders != null && !args.enabledProviders.includes(PLAYZ_PROVIDER_ID)) {
    return { sources: [] };
  }
  const item = args.item || {};
  if (!item.ref || item.ref.providerId !== 'nimora.matches') return { sources: [] };

  let events;
  try {
    events = await playzLoadEvents();
  } catch (_) {
    return { sources: [] };
  }

  // SPOTV supplies the canonical motorsport title, while PlayZ may publish
  // the same broadcast under a generic name without participants.
  const motorsportEvent = playzFindMotorsportEvent(events, item);
  if (motorsportEvent) {
    try {
      return { sources: await playzSourcesForEvent(motorsportEvent) };
    } catch (_) {
      return { sources: [] };
    }
  }

  if (!Array.isArray(item.participants) || item.participants.length !== 2) {
    return { sources: [] };
  }
  const now = Date.now();
  const candidates = events
    .filter((event) => playzStatus(event, now) !== 'ended')
    .filter((event) => event.teamAName && event.teamBName)
    .map((event) => {
      const startsAt = playzDate(event.date, event.time);
      return {
        event,
        teamA: event.teamAName,
        teamB: event.teamBName,
        startsAt: startsAt ? startsAt.toISOString() : null,
      };
    });
  if (candidates.length === 0) return { sources: [] };

  let result;
  try {
    result = host.match.resolve(
      {
        teamA: item.participants[0].name,
        teamB: item.participants[1].name,
        teamAShort: item.participants[0].shortName || null,
        teamBShort: item.participants[1].shortName || null,
        kickoff: item.schedule ? item.schedule.startsAt : null,
      },
      candidates.map((candidate) => ({
        teamA: candidate.teamA,
        teamB: candidate.teamB,
        startsAt: candidate.startsAt,
      })),
      { profile: PLAYZ_MATCH_PROFILE },
    );
  } catch (_) {
    return { sources: [] };
  }
  if (!result || !candidates[result.index]) return { sources: [] };

  try {
    return { sources: await playzSourcesForEvent(candidates[result.index].event) };
  } catch (_) {
    return { sources: [] };
  }
}

function playzExtractUrl(text, key) {
  const body = playzText(text);
  const parsed = playzJson(body);
  const desired = playzText(key) || 'playback_url';
  if (parsed && typeof parsed === 'object' && playzText(parsed[desired])) return playzText(parsed[desired]);
  const escaped = desired.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = new RegExp(`"${escaped}"\\s*:\\s*"([^"]+)"`, 'i').exec(body);
  if (match) return match[1].replace(/\\\//g, '/').replace(/\\u0026/g, '&');
  const media = /https?:\\?\/\\?\/[^"'<>\\s]+?\.(?:m3u8|mpd|mp4)(?:[^"'<>\\s]*)/i.exec(body);
  return media ? media[0].replace(/\\\//g, '/') : '';
}

async function playzToken(entry) {
  const config = playzJson(entry.tokenApi);
  if (!config || !config.api) return null;
  const request = playzSplit(config.api);
  const headers = Object.assign({ 'User-Agent': PLAYZ_UA }, request.headers);
  const options = { headers };
  if (playzText(config.request_type).toLowerCase() === 'post') {
    options.method = 'POST';
    options.body = playzText(config.request_body);
    if (!options.headers['Content-Type']) {
      options.headers['Content-Type'] = playzText(config.request_body_type).toLowerCase() === 'json'
        ? 'application/json' : 'application/x-www-form-urlencoded';
    }
  }
  const response = await playzFetch(request.url, options);
  const decoded = playzDecodeEncrypted(playzResponseText(response)) || playzResponseText(response);
  const url = playzExtractUrl(decoded, config.link_key);
  return url ? { url, headers } : null;
}

function playzFormat(url) {
  if (/\.mpd(?:[?#]|$)/i.test(url)) return 'dash';
  if (
    /\.m3u8?(?:[?#]|$)/i.test(url) ||
    /\/hls\//i.test(url) ||
    /\/play\.php\?/i.test(url) ||
    /[?&]e=\.m3u(?:[&#]|$)/i.test(url)
  ) return 'hls';
  return 'other';
}

function playzDrm(entry, parsed, url) {
  const raw = playzText(entry.api || parsed.drmApi);
  if (!raw) return null;
  if (/^[0-9a-f]{32,}:[0-9a-f]{32,}$/i.test(raw)) {
    const parts = raw.split(':');
    const kid = host.codec.hexToBase64(parts[0]).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    const key = host.codec.hexToBase64(parts[1]).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    return { scheme: 'clearKey', clearKeyJson: JSON.stringify({ keys: [{ kty: 'oct', k: key, kid }], type: 'temporary' }) };
  }
  if (/^https?:\/\//i.test(raw) && playzFormat(url) === 'dash') {
    return { scheme: 'widevine', licenseUrl: raw };
  }
  return null;
}

async function playzResolve(sourceId) {
  const prefix = `${PLAYZ_PROVIDER_KEY}:`;
  if (!playzText(sourceId).startsWith(prefix)) throw new Error(`Invalid PlayZTV source id: ${sourceId}`);
  const payload = playzFromBase64Url(sourceId.slice(prefix.length));
  const links = playzEntries(await playzFetchJson(payload.p));
  const entry = links[payload.i];
  if (!entry) throw new Error('PlayZTV source is no longer offered');

  let resolved = await playzToken(entry);
  const direct = playzSplit(entry.link);
  if (!resolved) resolved = direct.url ? { url: direct.url, headers: direct.headers } : null;
  if (!resolved || !/^https?:\/\//i.test(resolved.url)) throw new Error('PlayZTV returned no playable URL');

  const headers = Object.assign({}, direct.headers, resolved.headers);
  const format = playzFormat(resolved.url);
  if (format === 'hls' || format === 'dash') {
    const manifest = await playzFetch(resolved.url, { headers });
    const body = playzText(playzResponseText(manifest));
    if ((format === 'hls' && !body.startsWith('#EXTM3U')) ||
        (format === 'dash' && !/<MPD(?:\s|>)/i.test(body))) {
      throw new Error('PlayZTV returned an invalid playback manifest');
    }
  }
  return {
    url: resolved.url,
    headers,
    format,
    drm: playzDrm(entry, direct, resolved.url),
    label: playzText(entry.name) || playzText(payload.n && payload.n[payload.i]) || `PlayZTV ${Number(payload.i) + 1}`,
  };
}

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: PLAYZ_PROVIDER_KEY,
  sources: playzSources,
  resolve: playzResolve,
});
