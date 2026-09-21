// CDNLiveTV football event contributor and pure-JS HLS resolver.
//
// The upstream API exposes event metadata and a channel player page. The
// player page builds its playlist URL from base64-encoded chunks, so the
// bundle keeps only a stable event id and channel index in source ids. The
// playlist is decoded again on every resolve call.

const CDN_LIVE_TV_PROVIDER_ID = 'nimora.cdnlivetv';
const CDN_LIVE_TV_PROVIDER_KEY = 'cdnlivetv';
const CDN_LIVE_TV_API_URL =
  'https://api.cdnlivetv.tv/api/v1/events/sports/?user=cdnlivetv&plan=free';
const CDN_LIVE_TV_ORIGIN = 'https://cdnlivetv.tv';
const CDN_LIVE_TV_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36';
const CDN_LIVE_TV_UPCOMING_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
const CDN_LIVE_TV_RECENT_WINDOW_MS = 48 * 60 * 60 * 1000;
const CDN_LIVE_TV_EVENT_DURATION_MS = 3 * 60 * 60 * 1000;

const CDN_LIVE_TV_MATCH_PROFILE = {
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
    wolves: 'wolverhampton wanderers',
    'west brom': 'west bromwich albion',
    'west bromwich': 'west bromwich albion',
  },
  stopTokens: ['fc', 'afc', 'cf', 'sc', 'ac', 'cd', 'club'],
  ambiguousAlone: [
    'united', 'city', 'town', 'rovers', 'wanderers', 'albion', 'athletic',
    'county', 'real', 'atletico', 'sporting', 'dynamo', 'racing', 'olympique',
  ],
};

function cdnLiveTvText(value) {
  return value == null ? '' : String(value).trim();
}

function cdnLiveTvApiUrl() {
  return cdnLiveTvText(globalThis.__cdnlivetvApiUrl) || CDN_LIVE_TV_API_URL;
}

function cdnLiveTvNormalize(value) {
  let text = cdnLiveTvText(value).toLowerCase();
  try {
    text = text.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  } catch (_) {}
  return text.replace(/[^a-z0-9]+/g, ' ').replace(/\s+/g, ' ').trim();
}

function cdnLiveTvSlug(home, away) {
  return `${home}-vs-${away}`.toLowerCase().replace(/[^a-z0-9-]/g, '-');
}

function cdnLiveTvDate(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    const millis = value < 100000000000 ? value * 1000 : value;
    return Number.isFinite(millis) ? new Date(millis).toISOString() : null;
  }
  const text = cdnLiveTvText(value);
  if (!text) return null;
  const utcText = text.match(
    /^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}(?::\d{2})?)$/,
  );
  const timestamp = Date.parse(
    utcText ? `${utcText[1]}T${utcText[2]}Z` : text,
  );
  return Number.isFinite(timestamp) ? new Date(timestamp).toISOString() : null;
}

function cdnLiveTvStatus(value, startsAt, endsAt, nowMs) {
  const status = cdnLiveTvNormalize(value);
  if (/\b(live|in|playing|on air|on)\b/.test(status)) return 'live';
  if (/\b(end|ended|finished|complete|completed|closed)\b/.test(status)) {
    return 'ended';
  }
  const kickoff = Date.parse(startsAt);
  const end = Date.parse(endsAt);
  if (Number.isFinite(end) && nowMs >= end) return 'ended';
  if (Number.isFinite(kickoff) && nowMs - kickoff >= CDN_LIVE_TV_EVENT_DURATION_MS) {
    return 'ended';
  }
  return 'scheduled';
}

function cdnLiveTvEventId(item) {
  const gameId = cdnLiveTvText(item && item.gameID);
  if (gameId) return gameId;
  return cdnLiveTvSlug(
    cdnLiveTvText(item && item.homeTeam),
    cdnLiveTvText(item && item.awayTeam),
  );
}

function cdnLiveTvMapEvent(item) {
  if (item == null || typeof item !== 'object') return null;
  const home = cdnLiveTvText(item.homeTeam);
  const away = cdnLiveTvText(item.awayTeam);
  const startsAt = cdnLiveTvDate(item.start);
  const endsAt = cdnLiveTvDate(item.end);
  if (!home || !away || !startsAt) return null;
  const channels = Array.isArray(item.channels)
    ? item.channels
        .map((channel, index) => ({
          index,
          name: cdnLiveTvText(channel && (channel.channel_name || channel.name)),
          url: cdnLiveTvText(channel && channel.url),
        }))
        .filter((channel) => /^https?:\/\//i.test(channel.url))
    : [];
  if (channels.length === 0) return null;
  return {
    id: cdnLiveTvEventId(item),
    home,
    away,
    title: `${home} vs ${away}`,
    startsAt,
    endsAt,
    status: cdnLiveTvText(item.status),
    channels,
  };
}

function cdnLiveTvEvents(payload) {
  const sports = payload && payload['cdn-live-tv'];
  if (sports == null || typeof sports !== 'object') return [];
  const events = [];
  const seen = new Set();
  for (const category of ['Soccer', 'Football']) {
    const values = sports[category];
    if (!Array.isArray(values)) continue;
    for (const value of values) {
      const event = cdnLiveTvMapEvent(value);
      if (event == null || seen.has(event.id)) continue;
      seen.add(event.id);
      events.push(event);
    }
  }
  return events;
}

async function cdnLiveTvFetchJson() {
  const response = await fetch(cdnLiveTvApiUrl(), {
    headers: {
      Accept: 'application/json',
      'User-Agent': CDN_LIVE_TV_USER_AGENT,
    },
  });
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`CDNLiveTV API request failed: ${response.status}`);
  }
  const body = response && typeof response.body === 'string' ? response.body : '';
  return cdnLiveTvEvents(JSON.parse(body));
}

function cdnLiveTvRelevant(event, nowMs) {
  const startsAt = Date.parse(event.startsAt);
  return Number.isFinite(startsAt) &&
    startsAt - nowMs <= CDN_LIVE_TV_UPCOMING_WINDOW_MS &&
    nowMs - startsAt <= CDN_LIVE_TV_RECENT_WINDOW_MS;
}

function cdnLiveTvCatalogEntry(event, nowMs = Date.now()) {
  const state = cdnLiveTvStatus(event.status, event.startsAt, event.endsAt, nowMs);
  const item = {
    ref: {
      extensionId: globalThis.__nimoraExtensionId || 'nimora',
      providerId: 'nimora.matches',
      id: `cdnlivetv:${event.id}`,
    },
    kind: 'event',
    title: event.title,
    subtitle: 'Football',
    schedule: typeof eventSchedule === 'function'
      ? eventSchedule(
          Date.parse(event.startsAt),
          state,
          'Football',
          event.title,
          event.endsAt,
        )
      : {
          startsAt: event.startsAt,
          endsAt: event.endsAt || new Date(
            Date.parse(event.startsAt) + CDN_LIVE_TV_EVENT_DURATION_MS,
          ).toISOString(),
          state,
        },
    participants: [{ name: event.home }, { name: event.away }],
  };
  return {
    sportId: 'football',
    sportName: 'Football',
    live: state === 'live',
    item,
  };
}

async function cdnLiveTvSportEntries(nowMs = Date.now()) {
  try {
    return (await cdnLiveTvFetchJson())
      .filter((event) => cdnLiveTvRelevant(event, nowMs))
      .map((event) => cdnLiveTvCatalogEntry(event, nowMs));
  } catch (_) {
    return [];
  }
}

function cdnLiveTvSourceId(payload) {
  const encoded = host.codec.textToBase64(JSON.stringify(payload))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  return `${CDN_LIVE_TV_PROVIDER_KEY}:${encoded}`;
}

function cdnLiveTvFromSourceId(sourceId) {
  const prefix = `${CDN_LIVE_TV_PROVIDER_KEY}:`;
  const value = cdnLiveTvText(sourceId);
  if (!value.startsWith(prefix)) {
    throw new Error(`Invalid CDNLiveTV source id: ${sourceId}`);
  }
  let encoded = value.slice(prefix.length).replace(/-/g, '+').replace(/_/g, '/');
  while (encoded.length % 4) encoded += '=';
  const payload = JSON.parse(host.codec.base64ToText(encoded));
  if (payload == null || !payload.e || !Number.isInteger(payload.c)) {
    throw new Error('Invalid CDNLiveTV source payload');
  }
  return payload;
}

function cdnLiveTvFindEvent(events, item) {
  const itemId = cdnLiveTvText(item && item.ref && item.ref.id);
  if (itemId.startsWith('cdnlivetv:')) {
    const eventId = itemId.slice('cdnlivetv:'.length);
    const byId = events.find((event) => event.id === eventId);
    if (byId) return byId;
  }

  const participants = item && item.participants;
  if (Array.isArray(participants) && participants.length === 2) {
    try {
      const result = host.match.resolve(
        {
          teamA: participants[0].name,
          teamB: participants[1].name,
          teamAShort: participants[0].shortName || null,
          teamBShort: participants[1].shortName || null,
          kickoff: item.schedule ? item.schedule.startsAt : null,
        },
        events.map((event) => ({
          teamA: event.home,
          teamB: event.away,
          startsAt: event.startsAt,
        })),
        { profile: CDN_LIVE_TV_MATCH_PROFILE },
      );
      if (result && events[result.index]) return events[result.index];
    } catch (_) {}
  }

  const title = cdnLiveTvNormalize(item && item.title);
  return title
    ? events.find((event) => cdnLiveTvNormalize(event.title) === title)
    : null;
}

async function cdnLiveTvSources(args) {
  if (
    args.enabledProviders != null &&
    !args.enabledProviders.includes(CDN_LIVE_TV_PROVIDER_ID)
  ) {
    return { sources: [] };
  }
  const item = args.item || {};
  if (!item.ref || item.ref.providerId !== 'nimora.matches') {
    return { sources: [] };
  }
  let events;
  try {
    events = await cdnLiveTvFetchJson();
  } catch (_) {
    return { sources: [] };
  }
  const event = cdnLiveTvFindEvent(events, item);
  if (event == null) return { sources: [] };
  return {
    sources: event.channels.map((channel) => ({
      id: cdnLiveTvSourceId({ e: event.id, c: channel.index }),
      label: `CDNLiveTV · ${channel.name || `Stream ${channel.index + 1}`}`,
      provider: 'Nimora',
      providerId: CDN_LIVE_TV_PROVIDER_ID,
    })),
  };
}

function cdnLiveTvNormalizeBase64(value) {
  let encoded = cdnLiveTvText(value).replace(/-/g, '+').replace(/_/g, '/');
  while (encoded.length % 4) encoded += '=';
  return encoded;
}

function cdnLiveTvDecodeChunk(value) {
  try {
    return host.codec.base64ToText(cdnLiveTvNormalizeBase64(value));
  } catch (_) {
    return '';
  }
}

function cdnLiveTvAbsoluteUrl(value) {
  const url = cdnLiveTvText(value);
  if (/^https?:\/\//i.test(url)) return url;
  if (url.startsWith('//')) return `https:${url}`;
  return null;
}

function cdnLiveTvExtractPlaylist(html) {
  const body = cdnLiveTvText(html);
  const direct = body.match(
    /https?:\/\/[^"'<>\\\s]+\.m3u8(?:\?[^"'<>\\\s]*)?/i,
  );
  if (direct) return direct[0];

  const decoderMatch = body.match(
    /function\s+([a-zA-Z0-9_$]+)\s*\(\s*[a-zA-Z0-9_$]+\s*\)\s*\{[\s\S]*?\batob\b/i,
  );
  if (!decoderMatch) return null;
  const decoderName = decoderMatch[1];
  const concatRegex = new RegExp(
    `(?:var|let|const)\\s+([a-zA-Z0-9_$]+)\\s*=\\s*([^;]+);`,
    'g',
  );
  let concatMatch;
  let candidate;
  while ((candidate = concatRegex.exec(body)) != null) {
    if (new RegExp(`\\b${decoderName}\\s*\\(`).test(candidate[2])) {
      concatMatch = candidate;
      break;
    }
  }
  if (!concatMatch || !new RegExp(`\\b${decoderName}\\s*\\(`).test(concatMatch[2])) {
    return null;
  }

  const valueRegex = new RegExp(
    `(?:var|let|const)\\s+([a-zA-Z0-9_$]+)\\s*=\\s*(['\"])([^'\"]+)\\2`,
    'g',
  );
  const values = new Map();
  let valueMatch;
  while ((valueMatch = valueRegex.exec(body)) != null) {
    values.set(valueMatch[1], valueMatch[3]);
  }

  const chunkRegex = new RegExp(
    `\\b${decoderName}\\s*\\(\\s*([a-zA-Z0-9_$]+)\\s*\\)`,
    'g',
  );
  let playlist = '';
  let chunkMatch;
  while ((chunkMatch = chunkRegex.exec(concatMatch[2])) != null) {
    const encoded = values.get(chunkMatch[1]);
    if (!encoded) return null;
    playlist += cdnLiveTvDecodeChunk(encoded);
  }
  return playlist || null;
}

async function cdnLiveTvResolve(sourceId) {
  const payload = cdnLiveTvFromSourceId(sourceId);
  const events = await cdnLiveTvFetchJson();
  const event = events.find((candidate) => candidate.id === payload.e);
  if (!event || !event.channels[payload.c]) {
    throw new Error('CDNLiveTV event or channel changed; refresh sources');
  }

  const channel = event.channels[payload.c];
  const origin = CDN_LIVE_TV_ORIGIN;
  const referer = `${origin}/`;
  const headers = {
    Accept: '*/*',
    Origin: origin,
    Referer: referer,
    'User-Agent': CDN_LIVE_TV_USER_AGENT,
  };
  const player = await fetch(channel.url, {
    headers: {
      Accept: 'text/html,*/*;q=0.8',
      Referer: referer,
      'User-Agent': CDN_LIVE_TV_USER_AGENT,
    },
  });
  if (player.status < 200 || player.status >= 300) {
    throw new Error(`CDNLiveTV player request failed: ${player.status}`);
  }
  const url = cdnLiveTvAbsoluteUrl(
    cdnLiveTvExtractPlaylist(player.body),
  );
  if (!url) throw new Error('CDNLiveTV player has no direct HLS playlist');

  const playlist = await fetch(url, { headers });
  if (playlist.status < 200 || playlist.status >= 300 ||
      !cdnLiveTvText(playlist.body).startsWith('#EXTM3U')) {
    throw new Error('CDNLiveTV returned an invalid HLS playlist');
  }
  return {
    url,
    headers,
    format: 'hls',
    label: `CDNLiveTV · ${channel.name || `Stream ${payload.c + 1}`}`,
  };
}

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__cdnLiveTvSportEntries = cdnLiveTvSportEntries;
globalThis.__streamProviders.push({
  providerKey: CDN_LIVE_TV_PROVIDER_KEY,
  sources: cdnLiveTvSources,
  resolve: cdnLiveTvResolve,
});
