// League channel catalog.
//
// This is an editorial mapping of channel labels to the seven requested
// competitions. It is intentionally a catalog of upstream channel entries,
// not a claim about territorial broadcast rights or playback health. Source
// ids keep only provider paths and indexes; PlayZ/Cricfy links are fetched
// again when the user opens a channel.

const LEAGUE_CHANNELS_CATALOG_ID = 'league_channels';
const LEAGUE_CHANNELS_PROVIDER_ID = 'nimora.league_channels';
const LEAGUE_CHANNELS_PROVIDER_KEY = 'league_channels';
const LEAGUE_CHANNELS_CATEGORY = 'live';
const LEAGUE_CHANNELS_TTL_MS = 10 * 60 * 1000;
const LEAGUE_CHANNELS_MAX_CATEGORIES = 20;

const LEAGUE_CHANNEL_DEFINITIONS = [
  {
    id: 'premier-league',
    title: 'Premier League',
    patterns: [
      'premier league', 'sky sports premier', 'tnt sports', 'nbc sports',
      'bein sports', 'espn', 'arena sport', 'fox sports', 'dazn', 'fubo',
      'peacock', 'viaplay', 'canal+', 'super sport', 'astro',
    ],
  },
  {
    id: 'laliga',
    title: 'LaLiga',
    patterns: [
      'laliga', 'la liga', 'sky sports laliga', 'movistar', 'd sports',
      'espn', 'dazn', 'canal+', 'super sport', 'bein sports',
    ],
  },
  {
    id: 'serie-a',
    title: 'Serie A',
    patterns: [
      'serie a', 'sportitalia', 'espn', 'dazn', 'paramount', 'cbs sports',
      'bein sports', 'super sport', 'sport tv', 'arena sport', 'starzplay',
      'abu dhabi',
    ],
  },
  {
    id: 'bundesliga',
    title: 'Bundesliga',
    patterns: [
      'bundesliga', 'sky sport bundesliga', 'dazn', 'espn', 'bein sports',
      'sportdigital', 'onefootball', 'telemundo', 'peacock', 'usa network',
    ],
  },
  {
    id: 'ligue-1',
    title: 'Ligue 1',
    patterns: [
      'ligue 1', 'ligue1', 'bein sports', 'dazn', 'canal+', 'espn',
      'fox sports', 'caze', 'super sport', 'cctv', 'migu', 'ligue 1+',
    ],
  },
  {
    id: 'champions-league',
    title: 'Champions League',
    patterns: [
      'champions league', 'ucl', 'tnt', 'bein sports', 'paramount', 'dazn',
      'sky', 'canal+', 'espn', 'fox sports', 'arena sport', 'super sport',
      'stan', 'sony', 'sport tv', 'ziggo', 'viaplay', 'setanta', 'one soccer',
      'movistar',
    ],
  },
  {
    id: 'europa-league',
    title: 'Europa League',
    patterns: [
      'europa league', 'uel', 'tnt', 'bein sports', 'paramount', 'dazn',
      'sky', 'canal+', 'espn', 'fox sports', 'arena sport', 'super sport',
      'sport tv', 'ziggo', 'viaplay', 'setanta', 'one soccer', 'movistar',
    ],
  },
];

const LEAGUE_CHANNELS_PLAYZ_CATEGORY_NAMES = new Set([
  'sports', 'tnt', 'tnt sports', 'bein sports', 'tsn sports', 'premier sports',
  'fox sports', 'sportv', 'd sports', 'cbs sports', 'sportdigital',
  'sky sports', 'fubo sports', 'espn', 'dazn', 'euro sports', 'fs1',
  'arab sports', 'starzplay', 'general sports',
]);

// Collapse numbered/variant feeds into one user-facing broadcaster card. The
// match is intentionally conservative: unknown names remain separate instead
// of being merged merely because they happen to share a common word.
const LEAGUE_CHANNEL_BRANDS = [
  { key: 'sky-sports', title: 'Sky Sports', aliases: ['sky sports', 'sky sport'] },
  { key: 'tnt-sports', title: 'TNT Sports', aliases: ['tnt sports', 'tnt'] },
  { key: 'bein-sports', title: 'beIN Sports', aliases: ['bein sports', 'bein sport'] },
  { key: 'espn', title: 'ESPN', aliases: ['espn'] },
  { key: 'fox-sports', title: 'Fox Sports', aliases: ['fox sports', 'fox sport'] },
  { key: 'arena-sport', title: 'Arena Sport', aliases: ['arena sport'] },
  { key: 'dazn', title: 'DAZN', aliases: ['dazn'] },
  { key: 'movistar', title: 'Movistar', aliases: ['movistar liga de campeones', 'movistar'] },
  { key: 'paramount', title: 'Paramount+', aliases: ['paramount plus', 'paramount+'] },
  { key: 'super-sport', title: 'SuperSport', aliases: ['supersport', 'super sport'] },
  { key: 'peacock', title: 'Peacock', aliases: ['peacock'] },
  { key: 'viaplay', title: 'Viaplay', aliases: ['viaplay'] },
  { key: 'canal-plus', title: 'Canal+', aliases: ['canal plus', 'canal+'] },
  { key: 'sport-tv', title: 'Sport TV', aliases: ['sport tv'] },
  { key: 'setanta', title: 'Setanta Sports', aliases: ['setanta sports', 'setanta'] },
];

let leagueChannelsMemo = null;

function leagueChannelsText(value) {
  return value == null ? '' : String(value).trim();
}

function leagueChannelsNormalize(value) {
  return leagueChannelsText(value)
    .toLowerCase()
    .replace(/[+]/g, ' plus ')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function leagueChannelsJson(value) {
  try { return JSON.parse(String(value || '')); } catch (_) { return null; }
}

function leagueChannelsEncode(value) {
  return host.codec.textToBase64(JSON.stringify(value))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function leagueChannelsDecode(value) {
  let base64 = leagueChannelsText(value).replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4) base64 += '=';
  try { return JSON.parse(host.codec.base64ToText(base64)); } catch (_) { return null; }
}

function leagueChannelsUnwrap(value, key) {
  if (value == null || typeof value !== 'object') return null;
  const inner = value[key];
  if (typeof inner === 'string') return leagueChannelsJson(inner);
  return inner && typeof inner === 'object' ? inner : null;
}

function leagueChannelsCategoryName(value) {
  const parsed = leagueChannelsUnwrap(value, 'cat') || value;
  return leagueChannelsText(parsed && (parsed.name || parsed.title));
}

function leagueChannelsCategoryPath(value) {
  const parsed = leagueChannelsUnwrap(value, 'cat') || value;
  return leagueChannelsText(parsed && (parsed.api || parsed.path || parsed.url));
}

function leagueChannelsRows(value) {
  if (Array.isArray(value)) return value;
  if (value && typeof value === 'object') {
    for (const key of ['channels', 'items', 'rows', 'data', 'results', 'list']) {
      if (Array.isArray(value[key])) return value[key];
    }
    return [value];
  }
  return [];
}

function leagueChannelsParseRow(value, provider, locator, index) {
  let row = value;
  if (row && typeof row === 'object' && typeof row.channel === 'string') {
    row = leagueChannelsJson(row.channel);
  }
  if (!row || typeof row !== 'object' || Array.isArray(row)) return null;
  const name = leagueChannelsText(row.name || row.title || row.channel_name || row.channel);
  const visible = row.visible !== false && row.enabled !== false;
  const links = row.links || row.link || row.url || row.stream || row.tokenApi;
  if (!name || !visible || !leagueChannelsText(links)) return null;
  const linkNames = Array.isArray(row.link_names) ? row.link_names.map(leagueChannelsText) : [];
  return {
    provider,
    locator,
    index,
    name,
    normalizedName: leagueChannelsNormalize(name),
    logo: leagueChannelsText(row.logo || row.image || row.poster),
    links: leagueChannelsText(links),
    linkNames,
  };
}

function leagueChannelsParseM3u(text, provider, locator) {
  const lines = String(text || '').split(/\r?\n/);
  const rows = [];
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index].trim();
    if (!line.startsWith('#EXTINF')) continue;
    const comma = line.indexOf(',');
    const name = comma < 0 ? '' : line.slice(comma + 1).trim();
    const logoMatch = line.match(/\btvg-logo\s*=\s*["']([^"']+)["']/i);
    const logo = logoMatch == null ? '' : leagueChannelsText(logoMatch[1]);
    let linkIndex = index + 1;
    while (linkIndex < lines.length && lines[linkIndex].trim().startsWith('#')) linkIndex += 1;
    const link = linkIndex < lines.length ? lines[linkIndex].trim() : '';
    if (!name || !link) continue;
    rows.push({
      provider,
      locator,
      index: rows.length,
      name,
      normalizedName: leagueChannelsNormalize(name),
      logo,
      links: link,
      linkNames: [],
      m3u: true,
    });
  }
  return rows;
}

function leagueChannelsMatches(row, definition) {
  const haystack = leagueChannelsNormalize(
    `${row.name} ${(row.linkNames || []).join(' ')}`,
  );
  return definition.patterns.some((pattern) => haystack.includes(leagueChannelsNormalize(pattern)));
}

function leagueChannelsGroup(row) {
  const haystack = leagueChannelsNormalize(
    `${row.name} ${(row.linkNames || []).join(' ')}`,
  );
  const brand = LEAGUE_CHANNEL_BRANDS.find((candidate) =>
    candidate.aliases.some((alias) => haystack.includes(leagueChannelsNormalize(alias))),
  );
  if (brand != null) return { key: brand.key, title: brand.title };
  return { key: `channel:${row.normalizedName}`, title: row.name };
}

function leagueChannelsGroups(rows, definition) {
  const groups = new Map();
  rows.filter((row) => leagueChannelsMatches(row, definition)).forEach((row) => {
    const group = leagueChannelsGroup(row);
    let value = groups.get(group.key);
    if (value == null) {
      value = { key: group.key, title: group.title, rows: [] };
      groups.set(group.key, value);
    }
    value.rows.push(row);
  });
  return Array.from(groups.values());
}

function leagueChannelsDedupe(rows) {
  const seen = new Set();
  return rows.filter((row) => {
    const key = `${row.provider}:${row.locator}:${row.normalizedName}:${row.links}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

async function leagueChannelsLoadPlayz() {
  const testFeeds = globalThis.__leagueChannelsPlayzFeeds;
  const testCategories = globalThis.__leagueChannelsPlayzCategories;
  if (testFeeds && typeof testFeeds === 'object' && testCategories === undefined) {
    return Object.keys(testFeeds).flatMap((locator) =>
      leagueChannelsRows(testFeeds[locator]).map((row, index) =>
        leagueChannelsParseRow(row, 'playz', locator, index),
      ).filter((row) => row != null),
    );
  }
  let categories;
  try {
    categories = globalThis.__leagueChannelsPlayzCategories !== undefined
      ? leagueChannelsRows(globalThis.__leagueChannelsPlayzCategories)
      : leagueChannelsRows(await playzFetchJson('sports.txt'));
  } catch (_) { return []; }
  const selected = [];
  const seen = new Set();
  for (const category of categories) {
    const name = leagueChannelsNormalize(leagueChannelsCategoryName(category));
    const locator = leagueChannelsCategoryPath(category);
    if (!locator || (!LEAGUE_CHANNELS_PLAYZ_CATEGORY_NAMES.has(name) && name !== 'sports')) continue;
    if (seen.has(locator)) continue;
    seen.add(locator);
    selected.push(locator);
  }
  const rows = [];
  for (const locator of selected.slice(0, LEAGUE_CHANNELS_MAX_CATEGORIES)) {
    try {
      const data = testFeeds && typeof testFeeds === 'object'
        ? testFeeds[locator]
        : await playzFetchJson(locator);
      leagueChannelsRows(data).forEach((row, index) => {
        const parsed = leagueChannelsParseRow(row, 'playz', locator, index);
        if (parsed != null) rows.push(parsed);
      });
    } catch (_) {}
  }
  return rows;
}

async function leagueChannelsLoadCricfy() {
  const testFeeds = globalThis.__leagueChannelsCricfyFeeds;
  if (testFeeds && typeof testFeeds === 'object') {
    return Object.keys(testFeeds).flatMap((locator) => {
      const value = testFeeds[locator];
      return typeof value === 'string'
        ? leagueChannelsParseM3u(value, 'cricfy', locator)
        : leagueChannelsRows(value).map((row, index) => leagueChannelsParseRow(row, 'cricfy', locator, index)).filter((row) => row != null);
    });
  }
  let text;
  try { text = await cricfyFetchContent('v2/categories.txt'); } catch (_) { return []; }
  const categories = leagueChannelsRows(leagueChannelsJson(text));
  const selected = categories.filter((category) => {
    const name = leagueChannelsNormalize(category && category.name);
    const api = leagueChannelsText(category && category.api);
    return api && (name.includes('sport') || name.includes('world country') || name.includes('play tv'));
  }).slice(0, 6);
  const rows = [];
  await Promise.all(selected.map(async (category) => {
    const locator = leagueChannelsText(category.api);
    try {
      const body = /^https?:\/\//i.test(locator)
        ? await cricfyGetText(locator, cricfyDefaultHeaders(), CRICFY_CONTENT_TIMEOUT_MS)
        : await cricfyFetchContent(locator);
      const trimmed = leagueChannelsText(body);
      if (trimmed.startsWith('#EXTM3U') || trimmed.includes('#EXTINF')) {
        rows.push(...leagueChannelsParseM3u(trimmed, 'cricfy', locator));
      } else {
        leagueChannelsRows(leagueChannelsJson(trimmed)).forEach((row, index) => {
          const parsed = leagueChannelsParseRow(row, 'cricfy', locator, index);
          if (parsed != null) rows.push(parsed);
        });
      }
    } catch (_) {}
  }));
  return rows;
}

async function leagueChannelsLoad() {
  if (leagueChannelsMemo != null) {
    const age = Date.now() - leagueChannelsMemo.at;
    if (age < LEAGUE_CHANNELS_TTL_MS) return leagueChannelsMemo.rows;
  }
  const [playz, cricfy] = await Promise.all([
    leagueChannelsLoadPlayz(), leagueChannelsLoadCricfy(),
  ]);
  const rows = leagueChannelsDedupe(playz.concat(cricfy));
  leagueChannelsMemo = { at: Date.now(), rows };
  return rows;
}

function leagueChannelsItem(definition, group) {
  const id = leagueChannelsEncode({
    league: definition.id,
    channel: group.key,
  });
  const item = {
    ref: {
      extensionId: globalThis.__nimoraExtensionId || 'nimora',
      providerId: LEAGUE_CHANNELS_PROVIDER_ID,
      id: `${LEAGUE_CHANNELS_PROVIDER_KEY}:${id}`,
    },
    kind: 'channel',
    title: group.title,
    subtitle: definition.title,
  };
  const logo = group.rows
    .map((row) => row.logo)
    .find((value) => /^https?:\/\//i.test(value));
  if (logo != null) item.artwork = { portrait: { url: logo } };
  return item;
}

async function leagueChannelsCatalog(query) {
  if (!query || query.category !== LEAGUE_CHANNELS_CATEGORY) return { sections: [] };
  let rows;
  try { rows = await leagueChannelsLoad(); } catch (_) { return { sections: [] }; }
  return {
    sections: LEAGUE_CHANNEL_DEFINITIONS.map((definition) => ({
      id: `${LEAGUE_CHANNELS_CATALOG_ID}:${definition.id}`,
      title: definition.title,
      items: leagueChannelsGroups(rows, definition)
        .map((group) => leagueChannelsItem(definition, group)),
    })).filter((section) => section.items.length > 0),
  };
}

async function leagueChannelsSources(args) {
  const enabled = args && args.enabledProviders;
  if (enabled != null && !enabled.includes(LEAGUE_CHANNELS_PROVIDER_ID)) return { sources: [] };
  const item = args && args.item;
  if (!item || !item.ref || item.ref.providerId !== LEAGUE_CHANNELS_PROVIDER_ID) {
    return { sources: [] };
  }
  const rawId = leagueChannelsText(item.ref.id);
  const prefix = `${LEAGUE_CHANNELS_PROVIDER_KEY}:`;
  if (!rawId.startsWith(prefix)) return { sources: [] };
  const payload = leagueChannelsDecode(rawId.slice(prefix.length));
  if (!payload || !payload.league || !payload.channel) return { sources: [] };
  const definition = LEAGUE_CHANNEL_DEFINITIONS.find((entry) => entry.id === payload.league);
  if (definition == null) return { sources: [] };
  let rows;
  try { rows = await leagueChannelsLoad(); } catch (_) { return { sources: [] }; }
  const group = leagueChannelsGroups(rows, definition).find(
    (entry) => entry.key === payload.channel,
  );
  if (group == null) return { sources: [] };
  const sourceLists = await Promise.all(group.rows.map(async (row) => {
    try {
      if (row.provider === 'playz') {
        const testFeeds = globalThis.__leagueChannelsPlayzFeeds;
        const rawLinksValue = testFeeds && typeof testFeeds === 'object'
          ? testFeeds[row.links]
          : await playzFetchJson(row.links);
        return leagueChannelsRows(rawLinksValue).map((link, index) => ({
            id: `${LEAGUE_CHANNELS_PROVIDER_KEY}:${leagueChannelsEncode({
              provider: 'playz',
              links: row.links,
              index,
              names: row.linkNames,
            })}`,
            label: `PlayZTV · ${leagueChannelsText(link.name) || row.linkNames[index] || `${row.name} ${index + 1}`}`,
            provider: 'Nimora', providerId: LEAGUE_CHANNELS_PROVIDER_ID,
          }));
      } else if (row.provider === 'cricfy') {
        return [{
          id: `${LEAGUE_CHANNELS_PROVIDER_KEY}:${leagueChannelsEncode({
            provider: 'cricfy', locator: row.locator, index: row.index,
          })}`,
          label: `Cricfy · ${row.name}`,
          provider: 'Nimora', providerId: LEAGUE_CHANNELS_PROVIDER_ID,
        }];
      }
    } catch (_) {}
    return [];
  }));
  let links = sourceLists.flat();
  const seen = new Set();
  links = links.filter((link) => {
    if (seen.has(link.id)) return false;
    seen.add(link.id);
    return true;
  });
  return { sources: links };
}

async function leagueChannelsResolve(sourceId) {
  const prefix = `${LEAGUE_CHANNELS_PROVIDER_KEY}:`;
  if (!leagueChannelsText(sourceId).startsWith(prefix)) throw new Error('Invalid league channel source id');
  const payload = leagueChannelsDecode(sourceId.slice(prefix.length));
  if (!payload || !payload.provider) throw new Error('Malformed league channel source id');
  if (payload.provider === 'playz') {
    const playzId = playzSourceId({ p: payload.links, i: payload.index, n: payload.names || [] });
    return playzResolve(playzId);
  }
  if (payload.provider === 'cricfy') {
    const body = /^https?:\/\//i.test(payload.locator)
      ? await cricfyGetText(payload.locator, cricfyDefaultHeaders(), CRICFY_CONTENT_TIMEOUT_MS)
      : await cricfyFetchContent(payload.locator);
    const rows = leagueChannelsParseM3u(body, 'cricfy', payload.locator);
    const row = rows[payload.index];
    if (!row || !row.links) throw new Error('Cricfy channel is no longer offered');
    return {
      url: row.links,
      headers: { 'User-Agent': 'Mozilla/5.0' },
      format: cricfyStreamFormatFromUrl(row.links),
      drm: null,
      audioUrl: null,
      label: row.name,
    };
  }
  throw new Error('Unsupported league channel provider');
}

globalThis.__catalogProviders = globalThis.__catalogProviders || [];
globalThis.__catalogProviders.push({
  catalogId: LEAGUE_CHANNELS_CATALOG_ID,
  catalog: leagueChannelsCatalog,
});

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: LEAGUE_CHANNELS_PROVIDER_KEY,
  sources: leagueChannelsSources,
  resolve: leagueChannelsResolve,
});
