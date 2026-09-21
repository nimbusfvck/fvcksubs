// MeteGol's football stream provider.
//
// It keeps FotMob/Nimora's catalog as the source of truth: these agendas are
// only candidate lists used to add streams to an existing football fixture.
// The embed URL is carried in the opaque source id and the final playback URL
// is extracted fresh in resolve, because the player URLs are tokenized.

const METEGOL_PROVIDER_KEY = 'metegol';
const METEGOL_PROVIDER_ID = 'nimora.metegol';
const METEGOL_AGENDA18_URL =
  globalThis.__metegolAgendaUrl || 'https://agenda18.com/agenda.json?v=1.1';
const METEGOL_ALANGULO_URL =
  globalThis.__metegolAlAnguloUrl || 'https://alangulotv.cx/agenda.php';
const METEGOL_FUTBOLIBRE_URL =
  globalThis.__metegolFutbolLibreUrl || 'https://futbollibretv.sx/eventos.js';
const METEGOL_DEPORFLIX_SEARCH_URL =
  globalThis.__metegolDeporflixSearchUrl ||
  'https://deporflix.pe/wp-json/wp/v2/search?search=vs&per_page=20&_embed=1';
const METEGOL_DEPORFLIX_AJAX_URL =
  globalThis.__metegolDeporflixAjaxUrl ||
  'https://deporflix.pe/wp-admin/admin-ajax.php';
const METEGOL_AGENDA18_REFERER = 'https://agenda18.com/';
const METEGOL_ALANGULO_REFERER = 'https://alangulotv.cx/';
const METEGOL_FUTBOLIBRE_REFERER = 'https://futbollibretv.sx/';
const METEGOL_DEPORFLIX_REFERER = 'https://deporflix.pe/';
const METEGOL_CACHE_KEY = 'metegol.events.v2';
const METEGOL_LEGACY_CACHE_KEY = 'metegol.agenda18.events.v1';
const METEGOL_CACHE_TTL_MS = 6 * 60 * 60 * 1000;
const METEGOL_EVENTS_TTL_MS = 15 * 60 * 1000;
const METEGOL_USER_AGENT =
  'Mozilla/5.0 (Linux; Android 10; Pixel 3 XL) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';

function metegolStorage() {
  return typeof host === 'object' && host !== null && host.storage
    ? host.storage
    : null;
}

function metegolText(value) {
  return value === null || value === undefined ? '' : String(value).trim();
}

function metegolNormalizeTitle(value) {
  return metegolText(value)
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[:\u2013\u2014_-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function metegolToStartUtc(dateText, timeText) {
  const time = metegolText(timeText);
  const date = metegolText(dateText);
  const timeParts = time.split(':').map(Number);
  const dateParts = date.split('-').map(Number);
  if (
    dateParts.length !== 3 ||
    timeParts.length < 2 ||
    dateParts.some((value) => Number.isNaN(value)) ||
    timeParts.slice(0, 2).some((value) => Number.isNaN(value))
  ) {
    return null;
  }
  return new Date(
    Date.UTC(
      dateParts[0],
      dateParts[1] - 1,
      dateParts[2],
      timeParts[0] + 5,
      timeParts[1],
      Number.isNaN(timeParts[2]) ? 0 : timeParts[2],
    ),
  ).toISOString();
}

function metegolDecodeBase64(value) {
  let token = metegolText(value).replace(/-/g, '+').replace(/_/g, '/');
  const remainder = token.length % 4;
  if (remainder !== 0) token += '='.repeat(4 - remainder);
  try {
    return host.codec.base64ToText(token);
  } catch (_) {
    return null;
  }
}

function metegolDecodeHref(href) {
  const match = /[?&]r=([A-Za-z0-9+/_=-]+)/.exec(metegolText(href));
  return match === null ? null : metegolDecodeBase64(match[1]);
}

function metegolTeamNames(title) {
  let value = metegolText(title).split('|')[0];
  const colon = value.indexOf(':');
  if (colon >= 0 && colon < value.length - 1) value = value.slice(colon + 1);
  return value
    .split(/\s+v(?:s|s\.)?\.?\s+|\s+@\s+|\s+[–—-]\s+/i)
    .map((team) => team.trim())
    .filter((team) => team.length > 0)
    .slice(0, 2);
}

function metegolSameTeams(left, right) {
  const a = metegolTeamNames(left).map(metegolNormalizeTitle);
  const b = metegolTeamNames(right).map(metegolNormalizeTitle);
  if (a.length !== 2 || b.length !== 2) return false;
  const contains = (x, y) => x.includes(y) || y.includes(x);
  return (
    (contains(a[0], b[0]) && contains(a[1], b[1])) ||
    (contains(a[0], b[1]) && contains(a[1], b[0]))
  );
}

function metegolIsFootball(category) {
  const value = metegolText(category).toLowerCase();
  return value === 'futbol' || value === 'football' || value.includes('futbol');
}

function metegolLabel(attributes, prefix) {
  const name = metegolText(attributes.embed_name) || 'Agenda18';
  const language = metegolText(attributes.idioma);
  const label = language.length === 0 ? name : `${name} · ${language}`;
  return prefix ? `${prefix} · ${label}` : label;
}

function metegolParseAgenda(json) {
  const rows = json && Array.isArray(json.data) ? json.data : [];
  const seen = {};
  const events = [];
  for (const row of rows) {
    const attributes = row && row.attributes ? row.attributes : {};
    if (!metegolIsFootball(attributes.deportes)) continue;
    const title = metegolText(attributes.diary_description);
    if (title.length === 0) continue;

    const embeds =
      attributes.embeds && Array.isArray(attributes.embeds.data)
        ? attributes.embeds.data
        : [];
    const streams = [];
    for (const embed of embeds) {
      const embedAttributes = embed && embed.attributes ? embed.attributes : {};
      const url = metegolDecodeHref(embedAttributes.embed_iframe);
      if (url === null || url.length === 0) continue;
      if (/\.mpd(?:\?|$)/i.test(url) || /drm\.php/i.test(url)) continue;
      if (/tarjetarojita|proveseat|la10tv|la10\.com/i.test(url)) continue;
      streams.push({
        url,
        label: metegolLabel(embedAttributes),
        source: 'agenda18',
        referer: METEGOL_AGENDA18_REFERER,
      });
    }
    if (streams.length === 0) continue;

    const key = title.toLowerCase();
    if (seen[key]) continue;
    seen[key] = true;
    events.push({
      title,
      date: metegolText(attributes.date_diary),
      time: metegolText(attributes.diary_hour).slice(0, 8),
      startUtc: metegolToStartUtc(
        attributes.date_diary,
        attributes.diary_hour,
      ),
      streams,
    });
  }
  return events;
}

function metegolParseAlAngulo(html) {
  const events = [];
  const liRe =
    /<li class="([A-Z0-9\s]+)"><a href="#">([\s\S]*?)<\/a>\s*<ul>([\s\S]*?)<\/ul>\s*<\/li>/g;
  let match;
  while ((match = liRe.exec(html)) !== null) {
    const body = match[2];
    const streamsHtml = match[3];
    const title = body
      .split('<span class="t">')[0]
      .replace(/<[^>]+>/g, ' ')
      .replace(/\s+/g, ' ')
      .replace(/:\s*$/, '')
      .trim();
    if (title.length === 0) continue;

    const streams = [];
    const streamRe =
      /<li class="([^"]+)"><a href="[^"?]*\?r=([A-Za-z0-9+/=]+)"[^>]*>([\s\S]*?)<\/a><\/li>/g;
    let streamMatch;
    while ((streamMatch = streamRe.exec(streamsHtml)) !== null) {
      const url = metegolDecodeBase64(streamMatch[2]);
      if (url === null || url.length === 0) continue;
      // The site prints "Calidad 720p" inside a <span> on every single
      // channel, HD or not — it is a template constant, not a measurement,
      // so keeping it would put a specific claim on the label the site
      // itself does not back up. Drop the span and keep the channel name.
      const label = streamMatch[3]
        .replace(/<span[\s\S]*?<\/span>/gi, '')
        .replace(/<[^>]+>/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
      streams.push({
        source: 'alangulo',
        referer: METEGOL_ALANGULO_REFERER,
        label: label || 'Stream',
        url,
      });
    }
    if (streams.length === 0) continue;
    events.push({ title, streams, sport: metegolText(match[1]) });
  }
  return events;
}

function metegolParseFutbolLibre(body) {
  const match = /EVENTOS_DATA\s*=\s*(\[[\s\S]*\])\s*;?\s*$/.exec(body);
  if (match === null) return [];
  let data;
  try {
    data = JSON.parse(match[1]);
  } catch (_) {
    return [];
  }
  if (!Array.isArray(data)) return [];

  const events = [];
  const seen = {};
  for (const row of data) {
    if (!row || !row.titulo || !Array.isArray(row.canales)) continue;
    const streams = [];
    for (const channel of row.canales) {
      const url = metegolDecodeHref(channel && channel.url);
      if (url === null || url.length === 0) continue;
      const name = metegolText(channel && channel.nombre) || 'Stream';
      // `calidad` reads "720p" on every channel in this feed regardless of
      // what actually plays — a fixed field, not a real measurement — so
      // appending it would put a specific claim on the label the source
      // does not back up.
      streams.push({
        source: 'futbollibre',
        referer: METEGOL_FUTBOLIBRE_REFERER,
        label: name,
        url,
      });
    }
    if (streams.length === 0) continue;
    const title = metegolText(row.titulo);
    const key = metegolNormalizeTitle(title);
    if (seen[key]) continue;
    seen[key] = true;
    events.push({ title, streams, sport: metegolText(row.clase) });
  }
  return events;
}

async function metegolFetchDeporflixEvents() {
  const searchResponse = await fetch(METEGOL_DEPORFLIX_SEARCH_URL, {
    headers: {
      'User-Agent': METEGOL_USER_AGENT,
      Accept: 'application/json, text/plain, */*',
      Referer: METEGOL_DEPORFLIX_REFERER,
    },
    timeoutMs: 12000,
  });
  if (searchResponse.status < 200 || searchResponse.status >= 300) {
    throw new Error(`MeteGol Deporflix search failed: ${searchResponse.status}`);
  }
  let results;
  try {
    results = JSON.parse(searchResponse.body);
  } catch (_) {
    return [];
  }
  if (!Array.isArray(results)) return [];

  const matches = results.filter(
    (row) =>
      row &&
      row.id &&
      row.title &&
      /\s+vs\s+/i.test(row.title) &&
      typeof row.url === 'string' &&
      /\/canales\//.test(row.url),
  );
  const events = await Promise.all(
    matches.map(async (row) => {
      try {
        const response = await fetch(METEGOL_DEPORFLIX_AJAX_URL, {
          method: 'POST',
          headers: {
            'User-Agent': METEGOL_USER_AGENT,
            Accept: 'application/json, text/plain, */*',
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-Requested-With': 'XMLHttpRequest',
            Referer: row.url,
          },
          body:
            `action=doo_player_ajax&post=${encodeURIComponent(row.id)}` +
            '&nume=1&type=movie',
          timeoutMs: 10000,
        });
        if (response.status < 200 || response.status >= 300) return null;
        const payload = JSON.parse(response.body);
        if (!payload || typeof payload.embed_url !== 'string') return null;
        return {
          title: metegolText(row.title),
          streams: [
            {
              source: 'deporflix',
              referer: row.url,
              label: 'Deporflix',
              url: payload.embed_url,
            },
          ],
        };
      } catch (_) {
        return null;
      }
    }),
  );
  return events.filter((event) => event !== null);
}

async function metegolFetchText(url, headers, timeoutMs) {
  const response = await fetch(url, {
    headers,
    timeoutMs: timeoutMs || null,
  });
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`MeteGol request failed: ${response.status}`);
  }
  return response.body;
}

function metegolMergeStreams(left, right) {
  const streams = [...(left || [])];
  const urls = {};
  for (const stream of streams) urls[stream.url] = true;
  for (const stream of right || []) {
    if (!stream || !stream.url || urls[stream.url]) continue;
    urls[stream.url] = true;
    streams.push(stream);
  }
  return streams;
}

function metegolMergeEvents(...lists) {
  const events = [];
  for (const list of lists) {
    for (const event of list || []) {
      const key = metegolNormalizeTitle(event.title);
      if (key.length === 0) continue;
      const existing = events.find(
        (candidate) =>
          metegolNormalizeTitle(candidate.title) === key ||
          metegolSameTeams(candidate.title, event.title),
      );
      if (existing) {
        existing.streams = metegolMergeStreams(existing.streams, event.streams);
        if (!existing.startUtc && event.startUtc) existing.startUtc = event.startUtc;
      } else {
        const copy = {
          ...event,
          streams: metegolMergeStreams([], event.streams),
        };
        events.push(copy);
      }
    }
  }
  return events;
}

function metegolAddDeporflixStreams(events, extras) {
  for (const extra of extras || []) {
    const exact = metegolNormalizeTitle(extra.title);
    const target = events.find(
      (event) =>
        metegolNormalizeTitle(event.title) === exact ||
        metegolSameTeams(event.title, extra.title),
    );
    if (target) target.streams = metegolMergeStreams(target.streams, extra.streams);
  }
  return events;
}

async function metegolFetchEvents() {
  // Deporflix disabled for now: unlike the other three, it needs two chained
  // requests (search, then an ajax lookup per match) and matches events by a
  // loose " vs " title filter — the most likely of the four to time out or
  // hang a wrong stream on an event. Commented out, not deleted; uncomment
  // both blocks below to bring it back.
  //
  // FutbolLibre disabled too: it draws from the same channel pool as
  // AlAngulo (la18hd.su, streamtp-golden1.click) but covers fewer matches
  // and fewer streams per match, so it mostly just relabels AlAngulo's own
  // channels under a second near-identical name. Uncomment to bring it back.
  const [alangulo, /* futbolibre, */ agenda18 /* , deporflix */] = await Promise.allSettled([
    metegolFetchText(
      METEGOL_ALANGULO_URL,
      {
        'User-Agent': METEGOL_USER_AGENT,
        Accept: 'text/html,application/xhtml+xml,*/*;q=0.8',
        Referer: METEGOL_ALANGULO_REFERER,
      },
      12000,
    ).then(metegolParseAlAngulo),
    // metegolFetchText(
    //   METEGOL_FUTBOLIBRE_URL,
    //   {
    //     'User-Agent': METEGOL_USER_AGENT,
    //     Accept: 'application/javascript, text/plain, */*',
    //     Referer: METEGOL_FUTBOLIBRE_REFERER,
    //   },
    //   12000,
    // ).then(metegolParseFutbolLibre),
    metegolFetchText(
      METEGOL_AGENDA18_URL,
      {
        'User-Agent': METEGOL_USER_AGENT,
        Accept: 'application/json, text/plain, */*',
        Referer: METEGOL_AGENDA18_REFERER,
      },
      15000,
    ).then((body) => metegolParseAgenda(JSON.parse(body))),
    // metegolFetchDeporflixEvents(),
  ]);
  const events = metegolMergeEvents(
    alangulo.status === 'fulfilled' ? alangulo.value : [],
    // futbolibre.status === 'fulfilled' ? futbolibre.value : [],
    agenda18.status === 'fulfilled' ? agenda18.value : [],
  );
  // metegolAddDeporflixStreams(
  //   events,
  //   deporflix.status === 'fulfilled' ? deporflix.value : [],
  // );
  const storage = metegolStorage();
  if (storage !== null) {
    try {
      storage.write(
        METEGOL_CACHE_KEY,
        JSON.stringify(events),
        METEGOL_CACHE_TTL_MS,
      );
    } catch (_) {
      // Storage is an optional cache; a refused write must not fail discovery.
    }
  }
  return events;
}

function metegolCachedEvents() {
  const storage = metegolStorage();
  if (storage === null) return null;
  for (const key of [METEGOL_CACHE_KEY, METEGOL_LEGACY_CACHE_KEY]) {
    let raw;
    try {
      raw = storage.read(key);
    } catch (_) {
      continue;
    }
    if (typeof raw !== 'string' || raw.length === 0) continue;
    try {
      const events = JSON.parse(raw);
      if (!Array.isArray(events) || events.length === 0) continue;
      const valid = events.every(
        (event) =>
          typeof event === 'object' &&
          event !== null &&
          typeof event.title === 'string' &&
          Array.isArray(event.streams),
      );
      if (valid) return events;
    } catch (_) {
      continue;
    }
  }
  return null;
}

let metegolEventsMemo = null;
let metegolBackgroundRefresh = null;

function metegolRefreshInBackground() {
  if (metegolBackgroundRefresh !== null) return;
  metegolBackgroundRefresh = metegolFetchEvents().then(
    (events) => {
      metegolBackgroundRefresh = null;
      metegolEventsMemo = {
        promise: Promise.resolve(events),
        fetchedAt: Date.now(),
      };
    },
    () => {
      metegolBackgroundRefresh = null;
    },
  );
}

function metegolFetchEventsMemo(nowMs) {
  const now = nowMs == null ? Date.now() : nowMs;
  if (metegolEventsMemo === null) {
    const cached = metegolCachedEvents();
    if (cached !== null) {
      metegolEventsMemo = {
        promise: Promise.resolve(cached),
        fetchedAt: now,
      };
      metegolRefreshInBackground();
      return metegolEventsMemo.promise;
    }
  }
  if (
    metegolEventsMemo === null ||
    now - metegolEventsMemo.fetchedAt >= METEGOL_EVENTS_TTL_MS
  ) {
    const promise = metegolFetchEvents().catch((error) => {
      metegolEventsMemo = null;
      throw error;
    });
    metegolEventsMemo = { promise, fetchedAt: now };
  }
  return metegolEventsMemo.promise;
}

function metegolCandidatesFrom(events) {
  const candidates = [];
  for (const event of events) {
    const teams = metegolTeamNames(event.title);
    if (teams.length !== 2) continue;
    candidates.push({
      teamA: teams[0],
      teamB: teams[1],
      startsAt: event.startUtc || null,
      event,
    });
  }
  return candidates;
}

function metegolEncodeSourceId(stream) {
  const json = JSON.stringify({
    u: stream.url,
    l: stream.label,
    s: stream.source || 'agenda18',
    r: stream.referer || METEGOL_AGENDA18_REFERER,
  });
  return host.codec
    .textToBase64(json)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function metegolDecodeSourceId(encoded) {
  const json = metegolDecodeBase64(encoded);
  if (json === null) throw new Error('Malformed MeteGol source id');
  const payload = JSON.parse(json);
  if (!payload || typeof payload.u !== 'string' || payload.u.length === 0) {
    throw new Error('MeteGol source id has no embed URL');
  }
  return payload;
}

// The four upstream sites pull from overlapping channel pools, so the same
// channel (e.g. "Disney+", "Universo") often shows up once per site under a
// slightly different URL and survives `metegolMergeStreams`' exact-URL dedupe
// as separate entries. Tagging the label with its real origin site — not a
// made-up quality — is the only way to tell those apart in the list.
const METEGOL_SOURCE_NAMES = {
  agenda18: 'Agenda18',
  alangulo: 'AlAngulo',
  futbollibre: 'FutbolLibre',
  deporflix: 'Deporflix',
};

function metegolSourcesForEvent(event) {
  return event.streams.map((stream) => {
    const label = metegolText(stream.label) || 'Stream';
    const siteName = METEGOL_SOURCE_NAMES[stream.source] || null;
    const taggedLabel =
      siteName === null || label.toLowerCase().includes(siteName.toLowerCase())
        ? label
        : `${label} · ${siteName}`;
    return {
      id: `${METEGOL_PROVIDER_KEY}:${metegolEncodeSourceId(stream)}`,
      label: taggedLabel,
      provider: 'Nimora',
      providerId: METEGOL_PROVIDER_ID,
    };
  });
}

function metegolExtractObfuscatedPlaybackUrl(html) {
  const pairs = [];
  const pairsRe = /\[(\d+),"([A-Za-z0-9+/=]+)"\]/g;
  let match;
  while ((match = pairsRe.exec(html)) !== null) {
    pairs.push([Number(match[1]), match[2]]);
  }
  if (pairs.length === 0) return null;
  const keyMatch =
    /var\s+k\s*=\s*(\w+)\(\)\s*\+\s*(\w+)\(\);[\s\S]*?function\s+\1\(\)\s*\{\s*return\s+(\d+);\}[\s\S]*?function\s+\2\(\)\s*\{\s*return\s+(\d+);\}/.exec(
      html,
    );
  if (keyMatch === null) return null;
  const key = Number(keyMatch[3]) + Number(keyMatch[4]);
  pairs.sort((left, right) => left[0] - right[0]);
  let url = '';
  for (const pair of pairs) {
    const decoded = metegolDecodeBase64(pair[1]);
    if (decoded === null) return null;
    const digits = decoded.replace(/\D/g, '');
    if (digits.length > 0) url += String.fromCharCode(Number(digits) - key);
  }
  return url.length === 0 ? null : url;
}

function metegolExtractPlaybackUrl(html) {
  const direct =
    /(?:playbackURL|playbackUrl|playback_url|playbackurl|var\s+url)\s*=\s*"([^"]+)"/i.exec(
      html,
    );
  if (direct !== null && direct[1]) {
    return direct[1].replace(/\\\//g, '/').replace(/\\/g, '');
  }
  const obfuscated = metegolExtractObfuscatedPlaybackUrl(html);
  if (obfuscated !== null) return obfuscated;
  const m3u8 = /https?:\\?\/\\?\/[^"'\s\\]+\.m3u8[^"'\s]*/i.exec(html);
  return m3u8 === null ? null : m3u8[0].replace(/\\\//g, '/');
}

async function metegolResolveSource(sourceId) {
  const prefix = `${METEGOL_PROVIDER_KEY}:`;
  const encoded = sourceId.startsWith(prefix)
    ? sourceId.slice(prefix.length)
    : sourceId;
  const payload = metegolDecodeSourceId(encoded);
  const html = await metegolFetchText(payload.u, {
    'User-Agent': METEGOL_USER_AGENT,
    Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    Referer: payload.r || METEGOL_AGENDA18_REFERER,
  });
  const url = metegolExtractPlaybackUrl(html);
  if (url === null || url.length === 0) {
    throw new Error('MeteGol embed has no playback URL');
  }
  return {
    url,
    headers: { Referer: payload.r || METEGOL_AGENDA18_REFERER },
    format: 'hls',
    label: payload.l || 'Agenda18',
  };
}

async function metegolSources(args) {
  const enabled = args.enabledProviders;
  if (
    enabled !== null &&
    enabled !== undefined &&
    enabled.indexOf(METEGOL_PROVIDER_ID) === -1
  ) {
    return { sources: [] };
  }
  const item = args.item || {};
  if (!Array.isArray(item.participants) || item.participants.length !== 2) {
    return { sources: [] };
  }

  let events;
  try {
    events = await metegolFetchEventsMemo();
  } catch (_) {
    return { sources: [] };
  }
  const candidates = metegolCandidatesFrom(events);
  if (candidates.length === 0) return { sources: [] };

  const result = host.match.resolve(
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
    { profile: FOOTBALL_PROFILE },
  );
  if (!result) return { sources: [] };
  return { sources: metegolSourcesForEvent(candidates[result.index].event) };
}

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: METEGOL_PROVIDER_KEY,
  sources: metegolSources,
  resolve: (sourceId) => metegolResolveSource(sourceId),
});

globalThis.__extension = globalThis.__extension || {};
if (!globalThis.__extension.sources) {
  globalThis.__extension.sources = async (args) => {
    const calls = globalThis.__streamProviders.map((provider) =>
      Promise.resolve()
        .then(() => provider.sources(args))
        .catch(() => ({ sources: [] })),
    );
    if (args.fast !== true) {
      const perProvider = await Promise.all(calls);
      return { sources: perProvider.flatMap((result) => result.sources) };
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
    const provider = globalThis.__streamProviders.find(
      (candidate) => candidate.providerKey === providerKey,
    );
    if (!provider) {
      throw new Error(`No stream provider registered for "${providerKey}"`);
    }
    return provider.resolve(sourceId);
  };
}
