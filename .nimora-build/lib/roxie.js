// RoxieStreams live-event source provider.
//
// RoxieStreams publishes event pages separately from its stream host list.
// Roxie contributes missing items to the existing Nimora live-event catalog,
// but does not declare a separate user-facing catalog. Its current event page
// and domain list are fetched again when a source is resolved.

const ROXIE_PROVIDER_ID = 'nimora.roxie';
const ROXIE_PROVIDER_KEY = 'roxie';
const ROXIE_ORIGIN = 'https://roxiestreams.su';
const ROXIE_HOME_PATH = '/';
const ROXIE_INDEX_PATH = '/soccer';
const ROXIE_GENERIC_EVENT_PATHS = ['/', '/fighting', '/motorsports'];
const ROXIE_DOMAINS_FALLBACK_PATH = '/domainsz76.txt';
const ROXIE_UPCOMING_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
const ROXIE_RECENT_WINDOW_MS = 48 * 60 * 60 * 1000;
// Roxie exposes kickoff only, without an end-time or completion status.
// Keep event-specific windows so completed events remain available in
// schedule history but are not advertised as Live Now. This must stay in
// sync with eventSchedule() in fixtures.js, which gives motorsport 210 min.
const ROXIE_LIVE_WINDOW_MS = 3 * 60 * 60 * 1000;
const ROXIE_MOTORSPORT_WINDOW_MS = 210 * 60 * 1000;
// countdownfinal2.js reparses the displayed local time as Pacific daylight
// time before comparing it with Date.now(). Keep the same fixed offset here;
// the source page currently uses -07:00 for both its countdown and localized
// start-time display.
const ROXIE_COUNTDOWN_OFFSET = '-07:00';
const ROXIE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';

// Keep Roxie's matching independent from the full profile's Kora source.
// Compact bundles do not include kora.js, but both profiles still need to
// match Roxie soccer broadcasts against FotMob's existing match items.
const ROXIE_MATCH_PROFILE = {
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

function roxieText(value) {
  return value == null ? '' : String(value).trim();
}

function roxieOrigin() {
  return roxieText(globalThis.__roxieOrigin) || ROXIE_ORIGIN;
}

function roxiePageUrl(path) {
  const target = roxieText(path);
  if (/^https?:\/\//i.test(target)) return target;
  return `${roxieOrigin().replace(/\/+$/, '')}/${target.replace(/^\/+/, '')}`;
}

async function roxieFetch(path, options) {
  const response = await fetch(roxiePageUrl(path), options || {});
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`RoxieStreams request failed: ${response.status}`);
  }
  return response;
}

function roxieResponseText(response) {
  return response && typeof response.body === 'string' ? response.body : '';
}

function roxieDecodeEntities(value) {
  return roxieText(value)
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&nbsp;/gi, ' ');
}

function roxieStripHtml(value) {
  return roxieDecodeEntities(
    roxieText(value)
      .replace(/<[^>]*>/g, ' ')
      .replace(/\s+/g, ' '),
  );
}

function roxieNormalize(value) {
  let text = roxieDecodeEntities(value).toLowerCase();
  try { text = text.normalize('NFD').replace(/[\u0300-\u036f]/g, ''); } catch (_) {}
  return text.replace(/[^a-z0-9]+/g, ' ').trim();
}

function roxieDate(value) {
  const text = roxieText(value);
  if (!text) return null;
  const localDate = text.match(
    /^(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2}(?:,)?\s+\d{4}\s+\d{1,2}:\d{2}\s*(?:AM|PM)$/i,
  );
  // The raw Roxie table has no timezone. Append the same offset used by its
  // countdown script instead of inheriting the extension runtime timezone.
  const timestamp = Date.parse(
    localDate == null ? text : `${text}${ROXIE_COUNTDOWN_OFFSET}`,
  );
  return Number.isFinite(timestamp) ? new Date(timestamp).toISOString() : null;
}

function roxieDateInContext(body, start, end) {
  const rowStart = body.lastIndexOf('<tr', start);
  const rowClose = body.indexOf('</tr>', end);
  const context = rowStart !== -1 && rowClose !== -1
    ? body.slice(rowStart, rowClose)
    : body.slice(Math.max(0, start - 700), Math.min(body.length, end + 700));
  const text = roxieStripHtml(context);
  const dateMatch = text.match(
    /\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2}(?:,)?\s+\d{4}\s+\d{1,2}:\d{2}\s*(?:AM|PM)\b/i,
  );
  return roxieDate(dateMatch && dateMatch[0]);
}

function roxieParseIndex(html) {
  const body = roxieText(html);
  const events = [];
  const linkPattern = /<a\b[^>]*href\s*=\s*["'](\/soccer-streams-[^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = linkPattern.exec(body)) != null) {
    const title = roxieStripHtml(match[2]);
    const sides = title.split(/\s+vs\.?\s+/i).map(roxieText);
    if (sides.length !== 2 || !sides[0] || !sides[1]) continue;

    events.push({
      pagePath: match[1],
      title,
      teamA: sides[0],
      teamB: sides[1],
      startsAt: roxieDateInContext(body, match.index, linkPattern.lastIndex),
    });
  }
  return events;
}

function roxieParseGenericIndex(html) {
  const body = roxieText(html);
  const events = [];
  const linkPattern = /<a\b[^>]*href\s*=\s*["'](\/(?:ppv-streams-\d+|f1|nfl|ufc|tennis-\d+|supercross|nascar|motogp|mxgp|formula-1|indycar|racing-\d+))["'][^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = linkPattern.exec(body)) != null) {
    const title = roxieStripHtml(match[2]);
    if (!title) continue;
    events.push({
      pagePath: match[1],
      title,
      teamA: '',
      teamB: '',
      startsAt: roxieDateInContext(body, match.index, linkPattern.lastIndex),
    });
  }
  return events;
}

function roxieParseStreamPage(html) {
  const body = roxieText(html);
  const match = /getRandomStream\s*\(\s*["']([^"']+)["']\s*,\s*["']([^"']+)["']\s*\)/i.exec(body);
  if (!match) return null;
  const domainsMatch = /fetch\s*\(\s*["']([^"']*domainsz\d+\.txt)["']\s*\)/i.exec(body);
  return {
    streamPath: match[1].trim(),
    subdomain: match[2].trim(),
    domainsPath: roxieText(domainsMatch && domainsMatch[1]) || ROXIE_DOMAINS_FALLBACK_PATH,
  };
}

function roxieParseDomains(value) {
  const domains = [];
  for (const line of roxieText(value).split(/\r?\n/)) {
    const domain = line
      .trim()
      .replace(/^https?:\/\//i, '')
      .replace(/\/.*$/, '');
    if (!domain || !/^[a-z0-9.-]+(?::\d+)?$/i.test(domain)) continue;
    if (!domains.includes(domain)) domains.push(domain);
  }
  return domains;
}

function roxieSourceId(payload) {
  return `${ROXIE_PROVIDER_KEY}:${host.codec.textToBase64(JSON.stringify(payload))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '')}`;
}

function roxieFromSourceId(sourceId) {
  const prefix = `${ROXIE_PROVIDER_KEY}:`;
  if (!roxieText(sourceId).startsWith(prefix)) {
    throw new Error(`Invalid RoxieStreams source id: ${sourceId}`);
  }
  let encoded = sourceId.slice(prefix.length).replace(/-/g, '+').replace(/_/g, '/');
  while (encoded.length % 4) encoded += '=';
  const payload = JSON.parse(host.codec.base64ToText(encoded));
  if (!payload || !payload.p || !payload.s || !payload.h || !payload.d) {
    throw new Error('Invalid RoxieStreams source payload');
  }
  return payload;
}

function roxieStreamUrl(subdomain, domain, streamPath) {
  const override = roxieText(globalThis.__roxieStreamBaseUrl);
  if (override) {
    return `${override.replace(/\/+$/, '')}/${roxieText(streamPath).replace(/^\/+/, '')}`;
  }
  const scheme = /^https:/i.test(roxieOrigin()) ? 'https' : 'http';
  return `${scheme}://${roxieText(subdomain)}.${roxieText(domain)}/${roxieText(streamPath).replace(/^\/+/, '')}`;
}

async function roxieLoadEvents() {
  const response = await roxieFetch(ROXIE_INDEX_PATH, {
    headers: {
      Accept: 'text/html,*/*;q=0.8',
      Referer: `${roxieOrigin().replace(/\/+$/, '')}/`,
      'User-Agent': ROXIE_UA,
    },
  });
  return roxieParseIndex(roxieResponseText(response));
}

async function roxieLoadGenericEvents(path = ROXIE_HOME_PATH) {
  const response = await roxieFetch(path, {
    headers: {
      Accept: 'text/html,*/*;q=0.8',
      Referer: `${roxieOrigin().replace(/\/+$/, '')}/`,
      'User-Agent': ROXIE_UA,
    },
  });
  return roxieParseGenericIndex(roxieResponseText(response));
}

function roxieSportName(event) {
  if (event.teamA && event.teamB) return 'Football';
  if (/\/(?:f1|supercross|nascar|motogp|mxgp|formula-1|indycar|racing-\d+)(?:$|-)/i.test(event.pagePath)) return 'Motorsport';
  if (/\/tennis-/i.test(event.pagePath)) return 'Tennis';
  const identity = roxieNormalize(`${event.title} ${event.pagePath}`);
  if (
    /ppv streams|ufc|boxing|mma|wwe|wrestling|fighting|combat|kickboxing|one samurai|one championship|fight night/.test(identity)
  ) {
    return 'Fighting';
  }
  return 'Other Live Sports';
}

function roxieCatalogTitleKey(value) {
  if (typeof catalogTitleKey === 'function') return catalogTitleKey(value);
  return roxieNormalize(value)
    .replace(/\bformula one\b|\bf1\b/g, 'formula 1')
    .replace(/\bmoto gp\b/g, 'motogp');
}

function roxieEventDedupeKey(event) {
  if (!event.teamA || !event.teamB) {
    return `generic:${event.pagePath}:${roxieNormalize(event.title)}`;
  }
  return `football:${[event.teamA, event.teamB]
    .map(roxieNormalize)
    .sort()
    .join('|')}:${event.startsAt}`;
}

function roxieEventIsRelevant(event, nowMs) {
  const startsAt = Date.parse(event.startsAt);
  if (!Number.isFinite(startsAt)) return false;
  return startsAt - nowMs <= ROXIE_UPCOMING_WINDOW_MS &&
    nowMs - startsAt <= ROXIE_RECENT_WINDOW_MS;
}

function roxieEventLiveWindowMs(event) {
  const sport = roxieSportName(event);
  if (sport === 'Motorsport') return ROXIE_MOTORSPORT_WINDOW_MS;
  return ROXIE_LIVE_WINDOW_MS;
}

function roxieCountdownState(event, nowMs) {
  const startsAt = Date.parse(event.startsAt);
  if (!Number.isFinite(startsAt)) return 'scheduled';
  if (nowMs - startsAt >= roxieEventLiveWindowMs(event)) return 'ended';
  return startsAt <= nowMs ? 'live' : 'scheduled';
}

function roxieCatalogId(event) {
  const payload = {
    p: event.pagePath,
    t: roxieNormalize(event.title),
    k: event.startsAt,
  };
  return `roxie:${host.codec.textToBase64(JSON.stringify(payload))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '')}`;
}

function roxieCatalogEntry(event, nowMs = Date.now()) {
  const startsAt = Date.parse(event.startsAt);
  // The event page countdown is the source of truth. A stale `live` flag from
  // an index/cache must not promote a future event into the Live catalog.
  const state = roxieCountdownState(event, nowMs);
  const live = state === 'live';
  const item = {
    ref: {
      extensionId: globalThis.__nimoraExtensionId || 'nimora',
      providerId: 'nimora.matches',
      id: roxieCatalogId(event),
    },
    kind: 'event',
    title: event.title,
    subtitle: roxieSportName(event),
    schedule: typeof eventSchedule === 'function'
      ? eventSchedule(startsAt, state, roxieSportName(event), event.title)
      : {
          startsAt: new Date(startsAt).toISOString(),
          state,
        },
  };
  if (event.teamA && event.teamB) {
    item.participants = [{ name: event.teamA }, { name: event.teamB }];
  }
  return {
    sportId: roxieSportName(event),
    sportName: roxieSportName(event),
    live,
    item,
  };
}

async function roxieSportEntries(nowMs) {
  const [soccer, genericPages] = await Promise.all([
    roxieLoadEvents().catch(() => []),
    Promise.all(
      ROXIE_GENERIC_EVENT_PATHS.map((path) =>
        roxieLoadGenericEvents(path).catch(() => []),
      ),
    ),
  ]);
  const seen = new Set();
  return [...soccer, ...genericPages.flat()]
    .filter((event) => roxieEventIsRelevant(event, nowMs))
    .filter((event) => {
      const key = roxieEventDedupeKey(event);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .map((event) => roxieCatalogEntry(event, nowMs));
}

async function roxieLoadStream(event) {
  const response = await roxieFetch(event.pagePath, {
    headers: {
      Accept: 'text/html,*/*;q=0.8',
      Referer: `${roxieOrigin().replace(/\/+$/, '')}${ROXIE_INDEX_PATH}`,
      'User-Agent': ROXIE_UA,
    },
  });
  const stream = roxieParseStreamPage(roxieResponseText(response));
  if (!stream || !stream.streamPath || !stream.subdomain) {
    throw new Error('RoxieStreams event has no stream');
  }
  return stream;
}

async function roxieLoadDomains(referer, domainsPath) {
  const response = await roxieFetch(domainsPath || ROXIE_DOMAINS_FALLBACK_PATH, {
    headers: {
      Accept: 'text/plain,*/*;q=0.8',
      Referer: `${roxieOrigin().replace(/\/+$/, '')}${roxieText(referer) || ROXIE_INDEX_PATH}`,
      'User-Agent': ROXIE_UA,
    },
  });
  return roxieParseDomains(roxieResponseText(response));
}

async function roxieSources(args) {
  if (args.enabledProviders != null && !args.enabledProviders.includes(ROXIE_PROVIDER_ID)) {
    return { sources: [] };
  }
  const item = args.item || {};
  if (!item.ref || item.ref.providerId !== 'nimora.matches') return { sources: [] };
  let events;
  try {
    if (Array.isArray(item.participants) && item.participants.length === 2) {
      events = await roxieLoadEvents();
    } else if (roxieText(item.title)) {
      const pages = await Promise.all(
        ROXIE_GENERIC_EVENT_PATHS.map((path) =>
          roxieLoadGenericEvents(path).catch(() => []),
        ),
      );
      events = pages.flat();
    } else {
      return { sources: [] };
    }
  } catch (_) {
    return { sources: [] };
  }
  if (events.length === 0) return { sources: [] };

  let event;
  if (Array.isArray(item.participants) && item.participants.length === 2) {
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
        events.map((candidate) => ({
          teamA: candidate.teamA,
          teamB: candidate.teamB,
          startsAt: candidate.startsAt,
        })),
        { profile: ROXIE_MATCH_PROFILE },
      );
    } catch (_) {
      return { sources: [] };
    }
    event = result && events[result.index];
  } else {
    const title = roxieCatalogTitleKey(item.title);
    event = events.find((candidate) =>
      roxieCatalogTitleKey(candidate.title) === title);
  }
  if (!event) return { sources: [] };

  try {
    const stream = await roxieLoadStream(event);
    const domains = await roxieLoadDomains(event.pagePath, stream.domainsPath);
    return {
      sources: domains.map((domain) => ({
        id: roxieSourceId({
          p: event.pagePath,
          s: stream.streamPath,
          h: stream.subdomain,
          d: domain,
        }),
        label: `RoxieStreams · ${domain}`,
        provider: 'Nimora',
        providerId: ROXIE_PROVIDER_ID,
      })),
    };
  } catch (_) {
    return { sources: [] };
  }
}

async function roxieResolve(sourceId) {
  const payload = roxieFromSourceId(sourceId);
  const eventResponse = await roxieFetch(payload.p, {
    headers: {
      Accept: 'text/html,*/*;q=0.8',
      Referer: `${roxieOrigin().replace(/\/+$/, '')}${ROXIE_INDEX_PATH}`,
      'User-Agent': ROXIE_UA,
    },
  });
  const stream = roxieParseStreamPage(roxieResponseText(eventResponse));
  if (!stream || stream.streamPath !== payload.s || stream.subdomain !== payload.h) {
    throw new Error('RoxieStreams event stream changed; refresh sources');
  }

  const domains = await roxieLoadDomains(payload.p, stream.domainsPath);
  if (!domains.includes(payload.d)) {
    throw new Error('RoxieStreams stream domain is no longer available');
  }

  const origin = roxieOrigin().replace(/\/+$/, '');
  const headers = {
    Accept: '*/*',
    Origin: origin,
    Referer: `${origin}${payload.p}`,
    'User-Agent': ROXIE_UA,
    // A Roxie edge may be Cloudflare-protected. Do not open a challenge
    // automatically during source discovery; expose the event page instead
    // so the user can explicitly choose WebView playback.
    'x-qjsr-disable-cloudflare': '1',
  };
  const url = roxieStreamUrl(payload.h, payload.d, payload.s);
  const response = await fetch(url, { headers });
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`RoxieStreams playback request failed: ${response.status}`);
  }
  if (!roxieResponseText(response).startsWith('#EXTM3U')) {
    throw new Error('RoxieStreams returned an invalid HLS manifest');
  }
  return {
    url,
    headers,
    format: 'hls',
    label: `RoxieStreams · ${payload.d}`,
  };
}

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__roxieSportEntries = roxieSportEntries;
globalThis.__streamProviders.push({
  providerKey: ROXIE_PROVIDER_KEY,
  sources: roxieSources,
  resolve: roxieResolve,
});
