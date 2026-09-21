// LayarKaca stream discovery for TMDB-owned movie and episode items.
//
// TMDB remains Nimora's catalogue/detail source. This provider only searches
// LayarKaca at source time, refreshes the player page at resolve time, and
// follows the public CloudStream-style iframe/extractor chain.

const LAYARKACA_PROVIDER_KEY = 'layarkaca';
const LAYARKACA_PROVIDER_PREFIX = 'nimora.layarkaca';
const LAYARKACA_CATALOG_PROVIDER_ID = 'nimora.layarkaca.catalog';
const LAYARKACA_CATALOG_ID = 'layarkaca';
const LAYARKACA_SERVERS = [
  {
    key: 'hydrax',
    providerKey: 'layarkaca.hydrax',
    providerId: 'nimora.layarkaca.hydrax',
    name: 'LayarKaca · HYDRAX',
  },
  {
    key: 'p2p',
    providerKey: 'layarkaca.p2p',
    providerId: 'nimora.layarkaca.p2p',
    name: 'LayarKaca · P2P',
  },
  {
    key: 'turbovip',
    providerKey: 'layarkaca.turbovip',
    providerId: 'nimora.layarkaca.turbovip',
    name: 'LayarKaca · TURBOVIP',
  },
  {
    key: 'cast',
    providerKey: 'layarkaca.cast',
    providerId: 'nimora.layarkaca.cast',
    name: 'LayarKaca · CAST',
  },
];
const LAYARKACA_DEFAULT_BASE = 'https://tv12.lk21official.cc';
const LAYARKACA_DIRECTORY_BASE =
  globalThis.__layarkacaDirectoryBaseUrl || 'https://d21.team';
const LAYARKACA_DEFAULT_SERIES_BASE = 'https://tv9.nontondrama.my';
const LAYARKACA_DEFAULT_SEARCH_BASE = 'https://gudangvape.com';
const LAYARKACA_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:150.0) ' +
  'Gecko/20100101 Firefox/150.0';
const LAYARKACA_PLAYCDN_PREFIX = globalThis.__layarkacaPlaycdnPrefix || '';
const LAYARKACA_ABYSS_PREFIX = globalThis.__layarkacaAbyssPrefix || '';
const LAYARKACA_HOWNETWORK_PREFIX = globalThis.__layarkacaHownetworkPrefix || '';
const LAYARKACA_IFRAME_PREFIX = globalThis.__layarkacaIframePrefix || '';
const LAYARKACA_EMTURBOVID_PREFIX = globalThis.__layarkacaEmturbovidPrefix || '';
const LAYARKACA_FILEMOON_PREFIX = globalThis.__layarkacaFilemoonPrefix || '';
const LAYARKACA_F16_PREFIX = globalThis.__layarkacaF16Prefix || '';
const LAYARKACA_FILESIM_PREFIX = globalThis.__layarkacaFilesimPrefix || '';
const LAYARKACA_ABYSS_BASE_OVERRIDE =
  globalThis.__layarkacaAbyssBaseUrl || null;
const LAYARKACA_ABYSS_BASE =
  LAYARKACA_ABYSS_BASE_OVERRIDE || 'https://abyssplayer.com';
const LAYARKACA_ABYSS_DECODE_URL =
  globalThis.__layarkacaAbyssDecodeUrl || 'https://enc-dec.app/api/dec-abyss';

let layarkacaBase = globalThis.__layarkacaBaseUrl || LAYARKACA_DEFAULT_BASE;
const LAYARKACA_BASE_OVERRIDE = globalThis.__layarkacaBaseUrl || null;
let layarkacaSeriesBase =
  globalThis.__layarkacaSeriesBaseUrl || LAYARKACA_DEFAULT_SERIES_BASE;
const layarkacaSearchBase =
  globalThis.__layarkacaSearchBaseUrl || LAYARKACA_DEFAULT_SEARCH_BASE;
let layarkacaDiscoveryFlight = null;
let layarkacaBaseDiscoveryFlight = null;
const LAYARKACA_WATCH_PAGE_TTL_MS = 15000;
const layarkacaDiscoveryCache = new Map();
const layarkacaWatchPageCache = new Map();
const layarkacaWatchPageFlights = new Map();

function layarkacaWatchPageKey(query, detailUrl, watchUrl) {
  // Normalize null/omitted episode fields so discovery and source-id resolve
  // share the page, while different episodes on one series never collide.
  return JSON.stringify({
    detailUrl: detailUrl || null,
    watchUrl: watchUrl || null,
    title: query && query.title ? String(query.title) : null,
    year: query && Number.isInteger(query.year) ? query.year : null,
    isEpisode: query && query.isEpisode === true,
    season: query && Number.isInteger(query.season) ? query.season : null,
    episode: query && Number.isInteger(query.episode) ? query.episode : null,
  });
}

function layarkacaContentBaseCandidate(value) {
  const url = layarkacaUrl(value, `${LAYARKACA_DIRECTORY_BASE}/`);
  if (!url) return null;
  const origin = layarkacaOrigin(url);
  const testHost = globalThis.__layarkacaDirectoryAllowedHost;
  if (!origin ||
      (origin === layarkacaOrigin(LAYARKACA_DIRECTORY_BASE) &&
        typeof testHost !== 'string')) return null;
  const host = origin.replace(/^https?:\/\//i, '').toLowerCase();
  return /(?:^|[.-])lk21(?:[.-]|$)|lk21official|layarkaca/i.test(host) ||
    (typeof testHost === 'string' &&
      host.split(':')[0] === testHost.toLowerCase())
    ? origin
    : null;
}

async function layarkacaDiscoverCurrentBase() {
  const directory = LAYARKACA_DIRECTORY_BASE.replace(/\/$/, '');
  const response = await layarkacaFetch(`${directory}/`, directory + '/');
  if (response == null) return null;
  const candidates = [];
  const links = /<a\b([^>]*)>/gi;
  let link;
  while ((link = links.exec(response.body || '')) != null) {
    const candidate = layarkacaContentBaseCandidate(
      layarkacaAttr(link[1], 'href'),
    );
    if (candidate && !candidates.includes(candidate)) candidates.push(candidate);
  }
  for (const candidate of candidates) {
    const probe = await layarkacaFetchManual(candidate, directory + '/');
    if (probe == null) continue;
    if (probe.status < 200 || probe.status >= 400) continue;
    const location = layarkacaHeader(probe.headers, 'location');
    const redirected = location
      ? layarkacaOrigin(layarkacaUrl(location, candidate) || location)
      : layarkacaOrigin(probe.url || candidate);
    if (redirected && redirected !== layarkacaOrigin(directory)) return redirected;
  }
  return candidates[0] || null;
}

async function layarkacaEnsureBase() {
  if (LAYARKACA_BASE_OVERRIDE) return layarkacaBase;
  if (layarkacaBaseDiscoveryFlight) return layarkacaBaseDiscoveryFlight;
  layarkacaBaseDiscoveryFlight = (async () => {
    const discovered = await layarkacaDiscoverCurrentBase();
    if (discovered) layarkacaBase = discovered;
    return layarkacaBase;
  })();
  try {
    return await layarkacaBaseDiscoveryFlight;
  } finally {
    layarkacaBaseDiscoveryFlight = null;
  }
}

function layarkacaHeaders(referer, extra) {
  return {
    Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7',
    Referer: referer || `${layarkacaBase}/`,
    'User-Agent': LAYARKACA_UA,
    ...(extra || {}),
  };
}

async function layarkacaFetch(url, referer, options) {
  try {
    const requestOptions = {...(options || {})};
    const skipCloudflare = requestOptions.skipCloudflare === true;
    delete requestOptions.skipCloudflare;
    requestOptions.headers = {
      ...(requestOptions.headers || {}),
      ...(skipCloudflare ? {'X-QJSR-Disable-Cloudflare': '1'} : {}),
    };
    const response = await fetch(url, {
      ...requestOptions,
      headers: layarkacaHeaders(referer, requestOptions.headers),
    });
    if (response.status < 200 || response.status >= 300) return null;
    return response;
  } catch (_) {
    return null;
  }
}

async function layarkacaFetchManual(url, referer, options) {
  try {
    return await fetch(url, {
      redirect: 'manual',
      ...(options || {}),
      headers: layarkacaHeaders(referer, options && options.headers),
    });
  } catch (_) {
    return null;
  }
}

function layarkacaHeader(headers, name) {
  if (!headers) return null;
  const wanted = name.toLowerCase();
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === wanted) return headers[key];
  }
  return null;
}

function layarkacaOrigin(url) {
  const match = /^https?:\/\/[^/]+/i.exec(String(url || ''));
  return match == null ? null : match[0];
}

function layarkacaQueryParam(url, name) {
  const escaped = String(name).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = new RegExp(`[?&]${escaped}=([^&#]*)`, 'i').exec(String(url || ''));
  if (!match) return null;
  try { return decodeURIComponent(match[1].replace(/\+/g, ' ')); } catch (_) { return match[1]; }
}

function layarkacaUrl(value, base) {
  if (typeof value !== 'string' || !value.trim()) return null;
  const raw = value.trim();
  if (/^https?:\/\//i.test(raw)) return layarkacaIsHttpUrl(raw) ? raw : null;
  if (raw.startsWith('//')) return `https:${raw}`;
  const root = String(base || layarkacaBase).replace(/\/$/, '');
  if (raw.startsWith('/')) return `${layarkacaOrigin(root) || root}${raw}`;
  if (raw.startsWith('?')) {
    const clean = root.split(/[?#]/)[0];
    return `${clean}${raw}`;
  }
  const clean = root.split(/[?#]/)[0];
  return `${clean.slice(0, clean.lastIndexOf('/') + 1)}${raw}`;
}

function layarkacaIsHttpUrl(value) {
  // QuickJS deliberately exposes no browser `URL` global. Keep this
  // validation dependency-free: require a non-empty authority and reject
  // placeholders such as `https://` before they enter the resolver chain.
  return /^https?:\/\/[^/?#\s]+(?:[/?#]|$)/i.test(String(value || ''));
}

// Older Abyss/Filemoon pages use Dean Edwards' P.A.C.K.E.R. around their
// JWPlayer config. Decode only the substitution table; never evaluate the
// remote script. Keep this local so the LayarKaca source also works when it is
// loaded by itself during tests, before the generated bundle adds Savefilm.
function layarkacaUnpack(script) {
  const text = String(script || '');
  const patterns = [
    /}\(\s*'((?:\\.|[^'])*)'\s*,\s*(\d+)\s*,\s*\d+\s*,\s*'((?:\\.|[^'])*)'\.split\('\|'\)/i,
    /}\(\s*"((?:\\.|[^"])*)"\s*,\s*(\d+)\s*,\s*\d+\s*,\s*"((?:\\.|[^"])*)"\.split\("\|"\)/i,
  ];
  let match;
  let quote = "'";
  for (const pattern of patterns) {
    match = pattern.exec(text);
    if (match) {
      quote = pattern === patterns[1] ? '"' : "'";
      break;
    }
  }
  if (!match) return text;
  const payload = match[1]
    .replace(quote === "'" ? /\\'/g : /\\"/g, quote)
    .replace(/\\\\/g, '\\');
  const radix = Number(match[2]);
  const words = match[3]
    .replace(quote === "'" ? /\\'/g : /\\"/g, quote)
    .split('|');
  if (!Number.isInteger(radix) || radix < 2 || words.length === 0) return text;
  const digits = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const token = (index) => {
    let value = index;
    let result = '';
    do {
      result = digits[value % radix] + result;
      value = Math.floor(value / radix);
    } while (value > 0);
    return result;
  };
  let unpacked = payload;
  for (let index = words.length - 1; index >= 0; index--) {
    if (!words[index]) continue;
    const escaped = token(index).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    unpacked = unpacked.replace(new RegExp(`\\b${escaped}\\b`, 'g'), words[index]);
  }
  return unpacked;
}

function layarkacaAttr(attributes, name) {
  const match = new RegExp(`${name}\\s*=\\s*["']([^"']+)`, 'i')
    .exec(attributes || '');
  return match == null ? null : layarkacaText(match[1]);
}

function layarkacaText(value) {
  const entities = {
    amp: '&', apos: "'", gt: '>', hellip: '…', lt: '<', nbsp: ' ',
    ndash: '–', mdash: '—', quot: '"', rsquo: '’', lsquo: '‘',
    ldquo: '“', rdquo: '”',
  };
  return String(value || '')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&#(x[0-9a-f]+|[0-9]+);?/gi, (match, code) => {
      const point = code[0].toLowerCase() === 'x'
        ? parseInt(code.slice(1), 16) : parseInt(code, 10);
      return Number.isInteger(point) && point >= 0 && point <= 0x10ffff
        ? String.fromCodePoint(point) : match;
    })
    .replace(/&([a-z]+);/gi, (match, name) => entities[name.toLowerCase()] || match)
    .replace(/\s+/g, ' ')
    .trim();
}

function layarkacaNormalize(value) {
  return layarkacaText(value)
    .replace(/[([]\s*(?:19|20)\d{2}\s*[)\]]/g, ' ')
    .replace(/\b(?:19|20)\d{2}\b/g, ' ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function layarkacaYear(value) {
  const match = /\b((?:19|20)\d{2})\b/.exec(String(value || ''));
  return match == null ? null : Number(match[1]);
}

function layarkacaParseSearchResults(html, base) {
  const results = [];
  const articles = /<article\b[^>]*>([\s\S]*?)<\/article>/gi;
  let article;
  while ((article = articles.exec(html || '')) != null) {
    const body = article[1];
    const link = /<a\b([^>]*\bitemprop\s*=\s*["']url["'][^>]*)>/i.exec(body) ||
      /<a\b([^>]*)>/i.exec(body);
    if (!link) continue;
    const url = layarkacaUrl(layarkacaAttr(link[1], 'href'), base);
    const titleMatch = /<h[123]\b[^>]*>([\s\S]*?)<\/h[123]>/i.exec(body);
    const title = layarkacaText(
      titleMatch == null ? layarkacaAttr(link[1], 'title') : titleMatch[1],
    );
    if (!url || !title || !/^https?:\/\//i.test(url)) continue;
    results.push({url, title, year: layarkacaYear(`${title} ${url}`)});
  }
  // Some mirrors omit <article> while retaining the schema URL marker.
  if (results.length === 0) {
    const links = /<a\b([^>]*\bitemprop\s*=\s*["']url["'][^>]*)>([\s\S]*?)<\/a>/gi;
    let link;
    while ((link = links.exec(html || '')) != null) {
      const url = layarkacaUrl(layarkacaAttr(link[1], 'href'), base);
      const title = layarkacaText(link[2]);
      if (url && title) results.push({url, title, year: layarkacaYear(`${title} ${url}`)});
    }
  }
  return results;
}

function layarkacaCatalogPageUrl(base, category, page) {
  const path = category === 'tv' ? '/top-series-today' : '/latest';
  return page > 1 ? `${base}${path}/page/${page}` : `${base}${path}`;
}

function layarkacaCatalogTitle(value) {
  const text = layarkacaText(value);
  return text
    .replace(/\s*\(?((?:19|20)\d{2})\)?\s*$/i, '')
    .replace(/\s+/g, ' ')
    .trim() || text;
}

function layarkacaCatalogPoster(body, base) {
  const image = /<img\b([^>]*)>/i.exec(body || '');
  if (!image) return null;
  const raw = layarkacaAttr(image[1], 'data-lazy-src') ||
    layarkacaAttr(image[1], 'data-src') ||
    layarkacaAttr(image[1], 'data-original') ||
    layarkacaAttr(image[1], 'src');
  return layarkacaUrl(raw && raw.split(',')[0].trim().split(/\s+/)[0], base);
}

function layarkacaCatalogRating(body) {
  const itempropMatch = /<[^>]*\bitemprop\s*=\s*["']ratingValue["'][^>]*>([\s\S]*?)<\/[^>]+>/i.exec(body || '');
  if (itempropMatch) {
    const rating = Number(/\d+(?:\.\d+)?/.exec(layarkacaText(itempropMatch[1]))?.[0]);
    if (Number.isFinite(rating)) return rating;
  }
  const match = /(?:data-rating|ratingValue|gmr-rating-item)[^>]*[=:]\s*["']?([0-9]+(?:\.[0-9]+)?)/i.exec(body || '') ||
    /<[^>]*\b(?:rating|gmr-rating-item)\b[^>]*>([\s\S]*?)<\//i.exec(body || '');
  const rating = match == null ? NaN : Number(/\d+(?:\.\d+)?/.exec(layarkacaText(match[1]))?.[0]);
  return Number.isFinite(rating) ? rating : null;
}

function layarkacaParseCatalogResults(html, base, category) {
  const results = [];
  const articles = /<article\b[^>]*>([\s\S]*?)<\/article>/gi;
  let article;
  while ((article = articles.exec(html || '')) != null) {
    const body = article[1];
    const link = /<a\b([^>]*\bitemprop\s*=\s*["']url["'][^>]*)>/i.exec(body) ||
      /<a\b([^>]*)>/i.exec(body);
    if (!link) continue;
    const url = layarkacaUrl(layarkacaAttr(link[1], 'href'), base);
    const titleMatch = /<h[123]\b[^>]*>([\s\S]*?)<\/h[123]>/i.exec(body);
    const rawTitle = titleMatch == null
      ? layarkacaAttr(link[1], 'title') || layarkacaAttr(link[1], 'aria-label')
      : titleMatch[1];
    const title = layarkacaCatalogTitle(rawTitle);
    if (!url || !title || !/^https?:\/\//i.test(url)) continue;
    results.push({
      url,
      title,
      year: layarkacaYear(`${rawTitle || title} ${url}`),
      poster: layarkacaCatalogPoster(body, base),
      rating: layarkacaCatalogRating(body),
      category,
    });
  }
  // Some LK21 mirrors omit <article> but keep the schema.org itemprop link.
  if (results.length === 0) {
    const links = /<a\b([^>]*\bitemprop\s*=\s*["']url["'][^>]*)>([\s\S]*?)<\/a>/gi;
    let link;
    while ((link = links.exec(html || '')) != null) {
      const url = layarkacaUrl(layarkacaAttr(link[1], 'href'), base);
      const rawTitle = layarkacaAttr(link[1], 'title') || link[2];
      const title = layarkacaCatalogTitle(rawTitle);
      if (!url || !title) continue;
      results.push({
        url,
        title,
        year: layarkacaYear(`${rawTitle} ${url}`),
        category,
      });
    }
  }
  return results;
}

function layarkacaCatalogHasNextPage(html, currentPage = 1) {
  if (/<a\b[^>]*\b(?:class\s*=\s*["'][^"']*\bnext\b|rel\s*=\s*["']next)[^>]*>/i.test(html || '')) {
    return true;
  }
  const page = Number.isInteger(Number(currentPage)) && Number(currentPage) > 0
    ? Number(currentPage) : 1;
  const links = /<a\b([^>]*)>/gi;
  let link;
  while ((link = links.exec(html || '')) != null) {
    const href = layarkacaAttr(link[1], 'href');
    const pathPage = /\/page\/(\d+)(?:[/?#]|$)/i.exec(href || '');
    const queryPage = /[?&]page=(\d+)(?:[&#]|$)/i.exec(href || '');
    const linkedPage = Number((pathPage || queryPage || [])[1]);
    if (Number.isInteger(linkedPage) && linkedPage > page) return true;
  }
  return false;
}

function layarkacaCatalogItem(result) {
  const item = {
    ref: {
      extensionId: globalThis.__nimoraExtensionId || 'nimora',
      providerId: LAYARKACA_CATALOG_PROVIDER_ID,
      id: `${LAYARKACA_PROVIDER_KEY}:catalog:${layarkacaEncode({
        u: result.url,
        k: result.category === 'tv' ? 'series' : 'video',
        t: result.title,
        y: result.year,
      })}`,
    },
    kind: result.category === 'tv' ? 'series' : 'video',
    title: result.title,
  };
  if (Number.isInteger(result.year)) item.releaseYear = result.year;
  if (Number.isFinite(result.rating)) item.rating = result.rating;
  if (result.poster) item.artwork = {portrait: {url: result.poster}};
  return item;
}

async function layarkacaCatalog(query) {
  if (!query || query.category !== 'all') return {sections: []};
  const requestedPage = Number(query && query.page);
  const page = Number.isInteger(requestedPage) && requestedPage > 0 ? requestedPage : 1;
  const feeds = [
    {category: 'movie'},
    {category: 'tv'},
  ];
  const pages = await Promise.all(feeds.map((feed) =>
    layarkacaCatalogFeedPage(feed.category, page),
  ));
  const result = {
    sections: feeds.map((feed, index) => {
      const feedPage = pages[index];
      return {
        id: `${LAYARKACA_CATALOG_ID}-${feed.category}`,
        title: feed.category === 'tv' ? 'TV Series on LK21' : 'Movies on LK21',
        items: feedPage.items,
      };
    }),
  };
  if (pages.some((feedPage) => feedPage.nextPage != null)) {
    result.nextPage = String(page + 1);
  }
  return result;
}

async function layarkacaCatalogFeedPage(category, requestedPage) {
  const pageNumber = Number(requestedPage);
  const page = Number.isInteger(pageNumber) && pageNumber > 0 ? pageNumber : 1;
  await layarkacaEnsureBase();
  const base = (category === 'tv' ? layarkacaSeriesBase : layarkacaBase)
    .replace(/\/$/, '');
  const url = layarkacaCatalogPageUrl(base, category, page);
  const response = await layarkacaFetch(url, `${base}/`);
  if (response == null) return {items: []};
  const finalBase = layarkacaOrigin(response.url || url) || base;
  const results = layarkacaParseCatalogResults(response.body, finalBase, category);
  return {
    items: results.map(layarkacaCatalogItem),
    nextPage: layarkacaCatalogHasNextPage(response.body, page) ? String(page + 1) : null,
  };
}

function layarkacaParseSearchApi(body, query) {
  let data;
  try { data = JSON.parse(body || '{}'); } catch (_) { return []; }
  const entries = Array.isArray(data)
    ? data
    : (Array.isArray(data.data) ? data.data
      : (Array.isArray(data.items) ? data.items : (Array.isArray(data.results) ? data.results : [])));
  return entries.map((entry) => {
    if (!entry || typeof entry !== 'object') return null;
    const rawUrl = entry.url || entry.href || entry.link;
    const slug = entry.slug;
    const resultBase = query.isEpisode ? layarkacaSeriesBase : layarkacaBase;
    const url = layarkacaUrl(
      typeof rawUrl === 'string' ? rawUrl : (typeof slug === 'string' ? `/${slug}` : null),
      resultBase,
    );
    const title = layarkacaText(entry.title || entry.name || entry.label);
    if (!url || !title) return null;
    return {
      url,
      title,
      year: Number.isInteger(Number(entry.year))
        ? Number(entry.year) : layarkacaYear(`${title} ${url}`),
    };
  }).filter((entry) => entry != null);
}

function layarkacaItemQuery(item) {
  const ref = item && item.ref;
  if (!ref || (ref.providerId !== 'nimora.tmdb' &&
      ref.providerId !== LAYARKACA_CATALOG_PROVIDER_ID)) return null;
  const catalogPayload = ref.providerId === LAYARKACA_CATALOG_PROVIDER_ID
    ? layarkacaCatalogRefPayload(ref) : null;
  if (ref.providerId === LAYARKACA_CATALOG_PROVIDER_ID && catalogPayload == null) return null;
  const episode = item.kind === 'episode' ? (item.episode || {}) : null;
  const group = episode && typeof episode.groupId === 'string'
    ? /season:(\d+)/i.exec(episode.groupId) : null;
  const season = Number.isInteger(episode && episode.season)
    ? episode.season : (group ? Number(group[1]) : null);
  const episodeNumber = Number.isInteger(episode && episode.position)
    ? episode.position : (Number.isInteger(episode && episode.episode) ? episode.episode : null);
  const title = catalogPayload && catalogPayload.t
    ? catalogPayload.t
    : item.kind === 'episode' && item.subtitle
      ? item.subtitle : item.title;
  const availableAtYear = typeof item.availableAt === 'string'
    ? layarkacaYear(item.availableAt) : null;
  return {
    title: layarkacaText(title),
    year: Number.isInteger(item.releaseYear)
      ? item.releaseYear : (catalogPayload && Number.isInteger(catalogPayload.y)
        ? catalogPayload.y : availableAtYear),
    isEpisode: item.kind === 'episode',
    season,
    episode: episodeNumber,
    detailUrl: catalogPayload && typeof (catalogPayload.p || catalogPayload.u) === 'string'
      ? (catalogPayload.p || catalogPayload.u) : null,
    watchUrl: catalogPayload && typeof catalogPayload.w === 'string'
      ? catalogPayload.w : (catalogPayload && item.kind === 'episode' &&
        typeof catalogPayload.u === 'string' ? catalogPayload.u : null),
  };
}

async function layarkacaItemTitleVariants(item, fallback) {
  if (typeof globalThis.__animeTitleVariants !== 'function') return [fallback];
  try {
    const variants = await globalThis.__animeTitleVariants(item);
    return Array.isArray(variants) && variants.length > 0 ? variants : [fallback];
  } catch (_) {
    return [fallback];
  }
}

function layarkacaCatalogRefPayload(ref) {
  const id = ref && typeof ref.id === 'string' ? ref.id : '';
  const prefix = `${LAYARKACA_PROVIDER_KEY}:catalog:`;
  if (!id.startsWith(prefix)) return null;
  return layarkacaDecode(id.slice(prefix.length));
}

function layarkacaSearchScore(result, query, index) {
  const wanted = layarkacaNormalize(query.title);
  const candidate = layarkacaNormalize(result.title);
  if (!wanted || !candidate) return null;
  if (
    query.year != null &&
    result.year != null &&
    query.year !== result.year
  ) return null;
  const exact = wanted === candidate;
  // A movie substring is not a safe identity match: `Dreams` must not select
  // `Train Dreams` just because the site omitted the exact title from search.
  // Episodes retain the looser series-title matching used by the dedicated
  // series mirrors.
  if (!exact && !query.isEpisode) return null;
  const overlap = candidate.includes(wanted) || wanted.includes(candidate);
  if (!exact && !overlap) return null;
  const yearDelta = query.year != null && result.year != null
    ? Math.abs(query.year - result.year) : 0;
  return (exact ? 0 : 15) + yearDelta + index / 1000;
}

function layarkacaSlug(value, year) {
  const slug = layarkacaText(value)
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (!slug) return null;
  const suffix = Number.isInteger(year) && !new RegExp(`-${year}$`).test(slug)
    ? `-${year}` : '';
  return `${slug}${suffix}`;
}

async function layarkacaSlugFallback(query) {
  const titles = Array.isArray(query && query.titles) && query.titles.length > 0
    ? query.titles : [query && query.title];
  const slugs = [];
  const seen = new Set();
  for (const title of titles) {
    const slug = layarkacaSlug(title, query && query.year);
    if (!slug) continue;
    for (const candidate of [slug, slug.replace(/-(?:19|20)\d{2}$/, '')]) {
      if (!seen.has(candidate)) {
        seen.add(candidate);
        slugs.push({candidate, title});
      }
    }
  }
  if (slugs.length === 0) return null;
  const bases = query.isEpisode
    ? [layarkacaSeriesBase, layarkacaBase]
    : [layarkacaBase, layarkacaSeriesBase];
  for (const base of bases) {
    for (const entry of slugs) {
      const candidate = entry.candidate;
      const url = `${base.replace(/\/$/, '')}/${candidate}`;
      const response = await layarkacaFetch(url, `${base.replace(/\/$/, '')}/`);
      if (response == null) continue;
      const finalUrl = response.url || url;
      if (!new RegExp(`/${candidate}(?:[/?#]|$)`, 'i').test(finalUrl)) continue;
      if (!/<(?:script\b[^>]*id\s*=\s*["']season-data|h1\b|title\b)/i.test(response.body || '')) continue;
      return {url: finalUrl, title: entry.title || query.title, year: query.year};
    }
  }
  return null;
}

async function layarkacaSearch(query) {
  if (!query || !query.title) return null;
  await layarkacaEnsureBase();
  const requestedSeriesBase = layarkacaSeriesBase;
  const bases = query.isEpisode
    ? [requestedSeriesBase, layarkacaBase]
    : [layarkacaBase, layarkacaSeriesBase];
  const titleVariants = Array.isArray(query.titles) && query.titles.length > 0
    ? query.titles : [query.title];
  const variants = [];
  const seenVariants = new Set();
  for (const title of titleVariants) {
    const value = String(title || '').trim();
    const withoutYear = value.replace(/\s*\(?((?:19|20)\d{2})\)?\s*$/i, '').trim();
    for (const variant of [value, withoutYear]) {
      if (variant && !seenVariants.has(variant.toLowerCase())) {
        seenVariants.add(variant.toLowerCase());
        variants.push(variant);
      }
    }
  }
  let best = null;
  for (const base of bases) {
    for (const variant of variants) {
      const url = `${base.replace(/\/$/, '')}/search?s=${encodeURIComponent(variant)}`;
      const response = await layarkacaFetch(url, `${base.replace(/\/$/, '')}/`);
      if (response == null) continue;
      const finalOrigin = layarkacaOrigin(response.url || url);
      const results = layarkacaParseSearchResults(response.body, finalOrigin || base);
      const searchQuery = {...query, title: variant};
      results.forEach((result, index) => {
        const score = layarkacaSearchScore(result, searchQuery, index);
        if (score == null || (best != null && score >= best.score)) return;
        best = {result, score};
      });
    }
  }
  // The current site renders /search as an empty shell. Its page script calls
  // this JSON endpoint to populate the cards, so try the same contract before
  // relying on older server-rendered mirror markup.
  for (const variant of variants) {
    const apiUrl = `${layarkacaSearchBase.replace(/\/$/, '')}/search.php?s=${encodeURIComponent(variant)}&page=1`;
    const response = await layarkacaFetch(apiUrl, `${layarkacaBase}/`);
    if (response == null) continue;
    const searchQuery = {...query, title: variant};
    const results = layarkacaParseSearchApi(response.body, searchQuery);
    results.forEach((result, index) => {
      const score = layarkacaSearchScore(result, searchQuery, index);
      if (score == null || (best != null && score >= best.score)) return;
      best = {result, score};
    });
  }
  return best == null ? await layarkacaSlugFallback(query) : best.result;
}

function layarkacaSeasonData(html) {
  const match = /<script\b[^>]*\bid\s*=\s*["']season-data["'][^>]*>([\s\S]*?)<\/script>/i
    .exec(html || '');
  if (!match) return null;
  try { return JSON.parse(match[1].trim()); } catch (_) { return null; }
}

function layarkacaEpisodeUrl(html, pageUrl, season, episode) {
  const data = layarkacaSeasonData(html);
  if (!data || !Number.isInteger(season) || !Number.isInteger(episode)) return null;
  const seasonData = data[String(season)] || data[`season-${season}`] || data[season];
  const entries = Array.isArray(seasonData)
    ? seasonData : (seasonData && Array.isArray(seasonData.episodes) ? seasonData.episodes : []);
  const wanted = entries.find((entry) => {
    const number = Number(entry && (entry.episode_no ?? entry.episodeNumber ?? entry.episode));
    return number === episode;
  });
  if (!wanted) return null;
  return layarkacaUrl(wanted.slug || wanted.url || wanted.href, pageUrl);
}

function layarkacaCatalogEpisodeGuide(html, parentRef, parentTitle, poster, pageUrl, year) {
  const data = layarkacaSeasonData(html);
  if (!data || typeof data !== 'object') return null;
  const groups = [];
  for (const key of Object.keys(data)) {
    const seasonMatch = /(?:season[-_ ]?)?(\d+)/i.exec(key);
    const season = seasonMatch ? Number(seasonMatch[1]) : Number(key);
    const rawEntries = data[key];
    const entries = Array.isArray(rawEntries)
      ? rawEntries
      : (rawEntries && Array.isArray(rawEntries.episodes) ? rawEntries.episodes : []);
    if (!Number.isInteger(season) || season < 1 || entries.length === 0) continue;
    const episodes = [];
    for (const entry of entries) {
      const position = Number(entry && (entry.episode_no ?? entry.episodeNumber ?? entry.episode));
      const url = layarkacaUrl(
        entry && (entry.slug || entry.url || entry.href), pageUrl,
      );
      if (!Number.isInteger(position) || position < 1 || !url) continue;
      const title = layarkacaText(entry.title || entry.name) || `Episode ${position}`;
      const ref = {
        extensionId: globalThis.__nimoraExtensionId || 'nimora',
        providerId: LAYARKACA_CATALOG_PROVIDER_ID,
        id: `${LAYARKACA_PROVIDER_KEY}:catalog:${layarkacaEncode({
          u: url,
          p: pageUrl,
          t: parentTitle,
          y: year,
          s: season,
          e: position,
          k: 'episode',
          r: parentRef,
        })}`,
      };
      episodes.push({
        ref,
        title,
        position,
        ...(poster ? {artwork: {portrait: {url: poster}}} : {}),
      });
    }
    if (episodes.length === 0) continue;
    groups.push({
      id: `season:${season}`,
      title: `Season ${season}`,
      episodes: episodes.sort((a, b) => a.position - b.position),
    });
  }
  if (groups.length === 0) return null;
  groups.sort((a, b) => Number(a.id.split(':')[1]) - Number(b.id.split(':')[1]));
  const last = groups[groups.length - 1];
  return {
    groups,
    defaultEpisodeRef: last.episodes[last.episodes.length - 1].ref,
  };
}

function layarkacaCatalogDescription(html) {
  const meta = /<meta\b[^>]*(?:name|property)\s*=\s*["']description["'][^>]*>/i.exec(html || '');
  return meta ? layarkacaAttr(meta[0], 'content') : null;
}

async function layarkacaCatalogMeta(args) {
  const ref = args && args.ref;
  const payload = layarkacaCatalogRefPayload(ref);
  if (!payload || typeof payload.u !== 'string') {
    throw new Error('Malformed LayarKaca catalog ref');
  }
  const pageUrl = payload.u;
  const base = layarkacaOrigin(pageUrl) || layarkacaBase;
  const response = await layarkacaFetch(pageUrl, `${base}/`);
  if (response == null) throw new Error('LayarKaca detail request failed');
  const html = response.body || '';
  const titleMatch = /<h1\b[^>]*>([\s\S]*?)<\/h1>/i.exec(html);
  const title = layarkacaCatalogTitle(
    titleMatch ? titleMatch[1] : layarkacaAttr(
      /<meta\b[^>]*(?:property|name)\s*=\s*["']og:title["'][^>]*>/i.exec(html)?.[0],
      'content',
    ) || payload.t || 'LayarKaca video',
  );
  const item = payload.k === 'episode'
    ? {
      ref,
      kind: 'episode',
      title,
      subtitle: payload.t || null,
      episode: {
        parentRef: payload.r || ref,
        groupId: `season:${Number(payload.s) || 1}`,
        position: Number(payload.e) || 1,
      },
    }
    : {
      ref,
      kind: payload.k === 'series' ? 'series' : 'video',
      title,
    };
  const poster = layarkacaAttr(
    /<meta\b[^>]*(?:property|name)\s*=\s*["']og:image["'][^>]*>/i.exec(html)?.[0],
    'content',
  );
  if (poster) item.artwork = {portrait: {url: layarkacaUrl(poster, base)}};
  const year = Number.isInteger(payload.y) ? payload.y : layarkacaYear(`${title} ${pageUrl}`);
  if (Number.isInteger(year)) item.releaseYear = year;
  const rating = layarkacaCatalogRating(html);
  if (Number.isFinite(rating)) item.rating = rating;
  const detail = {item};
  const description = layarkacaCatalogDescription(html);
  if (description) detail.description = description;
  if (payload.k === 'series' || /season-data/i.test(html)) {
    const guide = layarkacaCatalogEpisodeGuide(
      html, ref, title, item.artwork?.portrait?.url || null,
      response.url || pageUrl, year,
    );
    if (guide) detail.episodeGuide = guide;
  }
  return detail;
}

function layarkacaPlayerUrls(html, pageUrl) {
  const urls = [];
  const add = (url, label) => {
    const absolute = layarkacaUrl(url, pageUrl);
    if (!absolute || !layarkacaIsHttpUrl(absolute) ||
        /https?:\/\/(?:www\.)?yellowishgather\.com\//i.test(absolute) ||
        /\/yellowishgather\//i.test(absolute) ||
        urls.some((item) => item.url === absolute)) return;
    urls.push({url: absolute, label: layarkacaText(label) || null});
  };
  const list = /<(?:ul|div)\b[^>]*\bid\s*=\s*["']player-list["'][^>]*>([\s\S]*?)<\/(?:ul|div)>/i
    .exec(html || '');
  const body = list == null ? html : list[1];
  const links = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
  let link;
  while ((link = links.exec(body || '')) != null) {
    add(
      layarkacaAttr(link[1], 'href') || layarkacaAttr(link[1], 'data-url'),
      layarkacaAttr(link[1], 'data-server') || link[2],
    );
  }
  const main = /<iframe\b([^>]*\bid\s*=\s*["']main-player["'][^>]*)>/i.exec(html || '');
  if (main) add(layarkacaAttr(main[1], 'src'), 'Main player');
  if (urls.length === 0) {
    const embedded = /<div\b[^>]*\bclass\s*=\s*["'][^"']*\bembed-container\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/i
      .exec(html || '');
    const iframe = embedded && /<iframe\b([^>]*)>/i.exec(embedded[1]);
    if (iframe) add(layarkacaAttr(iframe[1], 'src'), 'Player');
  }
  if (urls.length === 0) {
    const iframes = /<iframe\b([^>]*)>/gi;
    let iframe;
    while ((iframe = iframes.exec(html || '')) != null) add(layarkacaAttr(iframe[1], 'src'), 'Player');
  }
  return urls;
}

function layarkacaServerKey(label, index) {
  const key = layarkacaNormalize(label).replace(/\s+/g, '-');
  return key || `server-${index + 1}`;
}

function layarkacaEncode(value) {
  return host.codec.textToBase64(JSON.stringify(value))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function layarkacaDecode(value) {
  let encoded = String(value || '').replace(/-/g, '+').replace(/_/g, '/');
  const remainder = encoded.length % 4;
  if (remainder) encoded += '='.repeat(4 - remainder);
  try { return JSON.parse(host.codec.base64ToText(encoded)); } catch (_) { return null; }
}

async function layarkacaWatchPage(query, detailUrl, watchUrl) {
  const cacheKey = layarkacaWatchPageKey(query, detailUrl, watchUrl);
  const now = Date.now();
  const cached = layarkacaWatchPageCache.get(cacheKey);
  if (cached != null && now - cached.fetchedAt < LAYARKACA_WATCH_PAGE_TTL_MS) {
    return cached.page;
  }
  const inFlight = layarkacaWatchPageFlights.get(cacheKey);
  if (inFlight != null) return inFlight;

  const flight = (async () => {
    let detailResponse = detailUrl == null ? null :
      await layarkacaFetch(detailUrl, `${layarkacaBase}/`);
    let detailBody = detailResponse == null ? null : detailResponse.body;
    let resolvedDetailUrl = detailResponse == null ? detailUrl : (detailResponse.url || detailUrl);
    if (detailBody == null && query) {
      const found = await layarkacaSearch(query);
      if (found) {
        resolvedDetailUrl = found.url;
        detailResponse = await layarkacaFetch(found.url, `${layarkacaBase}/`);
        detailBody = detailResponse == null ? null : detailResponse.body;
      }
    }
    if (detailBody == null) return null;
    let resolvedWatchUrl = watchUrl || resolvedDetailUrl;
    if (query && query.isEpisode && !watchUrl) {
      resolvedWatchUrl = layarkacaEpisodeUrl(
        detailBody, resolvedDetailUrl, query.season, query.episode,
      );
      if (!resolvedWatchUrl) return null;
    }
    const page = await layarkacaFetch(resolvedWatchUrl, resolvedDetailUrl);
    if (page == null) return null;
    return {
      detailUrl: resolvedDetailUrl,
      watchUrl: page.url || resolvedWatchUrl,
      body: page.body,
      players: layarkacaPlayerUrls(page.body, page.url || resolvedWatchUrl),
    };
  })();
  layarkacaWatchPageFlights.set(cacheKey, flight);
  try {
    const page = await flight;
    if (page != null) {
      const fetchedAt = Date.now();
      const cacheEntry = {fetchedAt, page};
      layarkacaWatchPageCache.set(cacheKey, cacheEntry);
      // Discovery starts without a watch URL, while source resolution stores
      // the resolved watch URL in its restart-safe id. Reuse the fresh page
      // under both identities so resolving each server does not fetch the
      // same detail/watch document again.
      const resolvedKey = layarkacaWatchPageKey(
        query,
        page.detailUrl,
        page.watchUrl,
      );
      layarkacaWatchPageCache.set(resolvedKey, cacheEntry);
    }
    return page;
  } finally {
    if (layarkacaWatchPageFlights.get(cacheKey) === flight) {
      layarkacaWatchPageFlights.delete(cacheKey);
    }
  }
}

function layarkacaProviderEnabled(enabled, server) {
  return enabled == null ||
    enabled.indexOf(server.providerId) !== -1 ||
    enabled.indexOf(LAYARKACA_PROVIDER_PREFIX) !== -1;
}

async function layarkacaDiscover(item) {
  if (!item || (item.kind !== 'video' && item.kind !== 'episode')) return null;
  const query = layarkacaItemQuery(item);
  if (!query || (query.isEpisode && (!Number.isInteger(query.season) || !Number.isInteger(query.episode)))) {
    return null;
  }
  query.titles = await layarkacaItemTitleVariants(item, query.title);
  let found = query.detailUrl
    ? {url: query.detailUrl, title: query.title, year: query.year}
    : await layarkacaSearch(query);
  let page = found == null ? null : await layarkacaWatchPage(
    query, found.url, query.watchUrl,
  );
  // A movie mirror can return a matching redirect page for a series title.
  // Re-run the series slug on the dedicated NontonDrama base when that page
  // does not expose the requested season/episode players.
  if ((!page || page.players.length === 0) && query.isEpisode) {
    const seriesFound = await layarkacaSlugFallback(query);
    if (seriesFound && seriesFound.url !== (found && found.url)) {
      found = seriesFound;
      page = await layarkacaWatchPage(query, found.url, query.watchUrl);
    }
  }
  if (!found || !page || page.players.length === 0) return null;
  return {query, page};
}

async function layarkacaDiscoverForItem(item) {
  const key = JSON.stringify({
    ref: item && item.ref,
    kind: item && item.kind,
    title: item && item.title,
    subtitle: item && item.subtitle,
    year: item && item.year,
    episode: item && item.episode,
  });
  const now = Date.now();
  const cached = layarkacaDiscoveryCache.get(key);
  if (cached != null && now - cached.fetchedAt < LAYARKACA_WATCH_PAGE_TTL_MS) {
    return cached.value;
  }
  if (layarkacaDiscoveryFlight && layarkacaDiscoveryFlight.key === key) {
    return layarkacaDiscoveryFlight.promise;
  }
  const promise = (async () => {
    try {
      return await layarkacaDiscover(item);
    } finally {
      if (layarkacaDiscoveryFlight && layarkacaDiscoveryFlight.promise === promise) {
        layarkacaDiscoveryFlight = null;
      }
    }
  })();
  layarkacaDiscoveryFlight = {key, promise};
  try {
    const value = await promise;
    if (value != null) {
      layarkacaDiscoveryCache.set(key, {fetchedAt: Date.now(), value});
    }
    return value;
  } finally {
    if (layarkacaDiscoveryFlight && layarkacaDiscoveryFlight.promise === promise) {
      layarkacaDiscoveryFlight = null;
    }
  }
}

async function layarkacaSourcesForServer(args, server) {
  const enabled = args && args.enabledProviders;
  if (!layarkacaProviderEnabled(enabled, server)) return {sources: []};
  const discovered = await layarkacaDiscoverForItem(args && args.item);
  if (!discovered) return {sources: []};
  const {query, page} = discovered;
  const index = page.players.findIndex((player, playerIndex) =>
    layarkacaServerKey(player.label || `Player ${playerIndex + 1}`, playerIndex) === server.key);
  if (index < 0) return {sources: []};
  const player = page.players[index];
  return {
    sources: [{
      id: `${server.providerKey}:${layarkacaEncode({
        p: server.key,
        d: page.detailUrl,
        w: page.watchUrl,
        i: index,
        l: player.label,
        t: query.title,
        y: query.year,
        s: query.season,
        e: query.episode,
        k: query.isEpisode,
      })}`,
      label: server.name,
      provider: server.name,
      providerId: server.providerId,
    }],
  };
}

// Kept as an internal compatibility helper for focused resolver tests. The
// registered providers below call layarkacaSourcesForServer independently.
async function layarkacaSources(args) {
  const results = await Promise.all(
    LAYARKACA_SERVERS.map((server) => layarkacaSourcesForServer(args, server)),
  );
  return {sources: results.flatMap((result) => result.sources || [])};
}

function layarkacaMatches(url, prefix, hostPattern) {
  return (prefix && url.startsWith(prefix)) || hostPattern.test(url);
}

function layarkacaMediaFormat(url) {
  if (/\.m3u8(?:[?#]|$)/i.test(url)) return 'hls';
  // Abyss/Hydrax serves fixed MP4 renditions without a file extension.
  // Identifying the canonical `/sora/{size}/{token}` shape keeps it out of
  // the generic `other` bucket used for genuinely unknown media URLs.
  if (/\/sora\/\d+\/[^/?#]+(?:[?#]|$)/i.test(url)) return 'mp4';
  return 'other';
}

async function layarkacaValidateMedia(url, headers, label) {
  if (!/^https?:\/\//i.test(url)) return null;
  if (!/\.m3u8(?:[?#]|$)/i.test(url)) {
    return {url, format: layarkacaMediaFormat(url), headers: headers || {}, label};
  }
  const response = await layarkacaFetch(url, headers && headers.Referer, {headers});
  if (response == null || !/#EXTM3U/i.test(response.body || '')) return null;
  if (!/#EXT-X-(?:STREAM-INF|MEDIA|TARGETDURATION|ENDLIST)|#EXTINF/i.test(response.body || '')) return null;
  return {url, format: 'hls', headers: headers || {}, label};
}

async function layarkacaResolveIframe(
  url, referer, depth, seen, label, parentUrl,
) {
  // CloudStream's P2P extractor loads the player page through the normal
  // HTTP client first. That lets the Cloudflare layer handle a challenge and
  // exposes the nested iframe (usually /iframe3/p2p/...) to the extractor
  // chain. Skipping Cloudflare here incorrectly forced every blocked
  // Videonode page into the slower WebView path.
  const response = await layarkacaFetch(url, referer);
  if (response == null) {
    // Videonode /iframe3/ endpoints are browser-only shells. When the
    // extension still has the selected player URL, load the watch page and
    // ask the generic WebView host to select that iframe in its DOM.
    if (parentUrl && parentUrl !== url && /\/iframe3\//i.test(url)) {
      return layarkacaResolveWebViewCandidate(
        parentUrl, referer, depth, seen, label, true, url,
      );
    }
    const preferred = await layarkacaResolveWebViewCandidate(
      url, referer, depth, seen, label,
    );
    // Hydrax must stay on the Abyss chain. Falling back to the generic
    // Playcdn pattern returns a valid-looking single media playlist and
    // silently discards Hydrax's fixed quality payload.
    if (preferred || layarkacaPrefersAbyss(url, label)) return preferred;
    return layarkacaResolveWebViewCandidate(
      url, referer, depth, seen, null, false,
    );
  }
  const pageUrl = response.url || url;
  const requestedOrigin = layarkacaOrigin(url);
  const responseOrigin = layarkacaOrigin(pageUrl);
  const refererOrigin = layarkacaOrigin(referer);
  // A browser challenge can redirect a blocked player back to the parent
  // catalog homepage. That document is not the requested player and often
  // contains empty iframe placeholders such as `https://`, which must not
  // enter the resolver chain.
  if (requestedOrigin && responseOrigin && refererOrigin &&
      requestedOrigin !== refererOrigin && responseOrigin === refererOrigin) {
    return null;
  }
  // CloudStream first parses nested iframe/source URLs from the response and
  // only falls back to a browser when the document contains no usable child.
  // Do the same here: a 200 iframe3 response can already expose the Abyss
  // player, and sending it back to the parent WebView unconditionally turns a
  // playable Hydrax response into a 45-second parent-page timeout.
  const players = layarkacaPlayerUrls(response.body, pageUrl);
  for (const player of players) {
    const resolved = await layarkacaResolveUrl(
      player.url, pageUrl, depth + 1, seen, player.label || label,
    );
    if (resolved) return resolved;
  }
  // Non-P2P iframe3 servers can return a browser-only shell or a nested ad
  // wrapper whose final player is only created when the selected link is
  // clicked from the watch page. Retry through that parent before asking the
  // WebView to observe the already-detached shell; this is required by the
  // current TurboVIP -> EmTurbovid chain.
  if (parentUrl && parentUrl !== url && /\/iframe3\//i.test(url)) {
    const parentResolved = await layarkacaResolveWebViewCandidate(
      parentUrl, referer, depth, seen, label, true, url,
    );
    if (parentResolved) return parentResolved;
  }
  const preferred = await layarkacaResolveWebViewCandidate(
    pageUrl, referer, depth, seen, label,
  );
  if (preferred || layarkacaPrefersAbyss(pageUrl, label)) return preferred;
  return layarkacaResolveWebViewCandidate(
    pageUrl, referer, depth, seen, null, false,
  );
}

// The current upstream iframe is a browser-only shell: it loads a nested
// player frame and that frame later exposes the actual playlist. Capture
// both the final playlist and known nested player URLs so the normal
// extractor chain can continue in QuickJS. Capturing only m3u8 here loses the
// chain before Playcdn/Abyss gets a chance to resolve it.
const LAYARKACA_WEBVIEW_PATTERN =
  'm3u8|master\\.txt|playcdn\\.de/|emturbovid\\.com/|abyssplayer\\.com/';
const LAYARKACA_ABYSS_WEBVIEW_PATTERN =
  'abyssplayer\\.com/|abyss\\.to/|abysscdn\\.com/|hydraxcdn\\.biz/|embedplayabyss\\.top/';

function layarkacaPrefersAbyss(url, label) {
  const lowerUrl = String(url || '').toLowerCase();
  return /hydrax/i.test(String(label || '')) ||
    lowerUrl.includes('/iframe/hydrax/') ||
    lowerUrl.includes('/iframe3/hydrax/');
}

function layarkacaWebViewPattern(url, label, preferAbyss = true) {
  return preferAbyss && layarkacaPrefersAbyss(url, label)
    ? LAYARKACA_ABYSS_WEBVIEW_PATTERN
    : LAYARKACA_WEBVIEW_PATTERN;
}

async function layarkacaResolveWebViewCandidate(
  url, referer, depth, seen, label, preferAbyss = true, clickUrl,
) {
  const interceptPattern = layarkacaWebViewPattern(url, label, preferAbyss);
  try {
    const intercepted = await fetch(url, {
      headers: {
        Referer: referer || url,
        'X-QJSR-WebView-Pattern': interceptPattern,
        ...(clickUrl ? {'X-QJSR-WebView-Click-Url': clickUrl} : {}),
      },
    });
    const candidate = intercepted.url || '';
    if (intercepted.status !== 200 || !layarkacaIsHttpUrl(candidate)) return null;
    if (/(?:m3u8|master\\.txt)/i.test(candidate)) {
      return layarkacaValidateMedia(
        candidate,
        {Referer: referer || url, 'User-Agent': LAYARKACA_UA},
        'WebView',
      );
    }
    return layarkacaResolveUrl(
      candidate,
      url || referer,
      (depth || 0) + 1,
      seen || new Set(),
      label || 'WebView',
    );
  } catch (_) {
    return null;
  }
}

async function layarkacaResolveP2pApi(url, referer) {
  const id = layarkacaQueryParam(url, 'id');
  if (!id) return null;
  return layarkacaResolveP2pId(
    id,
    referer,
    layarkacaOrigin(url) || 'https://playcdn.de',
    url,
  );
}

async function layarkacaResolveP2pId(id, referer, apiOrigin, requestReferer) {
  const origin = apiOrigin || 'https://playcdn.de';
  const response = await layarkacaFetch(
    `${origin}/api2.php?id=${encodeURIComponent(id)}`,
    requestReferer || referer,
    {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Origin: origin,
      'X-Requested-With': 'XMLHttpRequest',
    },
    body: 'r=' + encodeURIComponent(referer || 'https://videonode.de/') +
      '&d=' + encodeURIComponent(origin.replace(/^https?:\/\//i, '')),
    },
  );
  if (response == null) return null;
  let data;
  try { data = JSON.parse(response.body || '{}'); } catch (_) { return null; }
  const entries = data && Array.isArray(data.data) ? data.data : [data];
  const headers = {
    Referer: `${origin}/`,
    'User-Agent': LAYARKACA_UA,
  };
  for (const entry of entries) {
    const media = entry && (entry.file || entry.link || entry.url || entry.videoSource);
    const resolved = await layarkacaValidateMedia(
      media,
      headers,
      entry && (entry.label || entry.quality || 'P2P'),
    );
    if (resolved) return resolved;
  }
  return null;
}

async function layarkacaResolveP2pIframe(url, referer) {
  const match = /\/iframe(?:3)?\/p2p\/([^/?#]+)/i.exec(String(url || ''));
  if (!match) return null;
  return layarkacaResolveP2pId(
    match[1],
    referer,
    layarkacaOrigin(LAYARKACA_PLAYCDN_PREFIX) || 'https://playcdn.de',
    url,
  );
}

async function layarkacaResolvePlaycdn(url, referer) {
  // The current Playcdn/Videonode contract uses api2.php?id=...; older
  // pages expose a token in HTML and use verify.php instead. Keep both paths
  // because LayarKaca rotates between these player generations.
  const apiResolved = await layarkacaResolveP2pApi(url, referer);
  if (apiResolved) return apiResolved;
  const response = await layarkacaFetch(url, referer);
  if (response == null) return null;
  const pageUrl = response.url || url;
  const origin = layarkacaOrigin(pageUrl) || 'https://playcdn.de';
  const dataMatch = /\bvar\s+data\s*=\s*(\{[\s\S]*?\})\s*;/i.exec(response.body || '');
  if (!dataMatch) {
    // The current Playcdn page resolves its path slug through a JSON GET
    // instead of embedding the legacy `var data` token in HTML.
    const slugMatch = /\/([^/?#]+)(?:[?#]|$)/i.exec(pageUrl);
    if (!slugMatch || !slugMatch[1] || slugMatch[1] === 'video.php') return null;
    const verified = await layarkacaFetch(
      `${origin}/verify/${encodeURIComponent(slugMatch[1])}`,
      pageUrl,
      {headers: {Referer: pageUrl, Origin: origin}},
    );
    if (verified == null) return null;
    let current;
    try { current = JSON.parse(verified.body || '{}'); } catch (_) { return null; }
    if (current.status !== 'success' || typeof current.fileUrl !== 'string') return null;
    return layarkacaValidateMedia(
      current.fileUrl,
      {Referer: pageUrl, 'User-Agent': LAYARKACA_UA},
      'P2P',
    );
  }
  let data;
  try { data = JSON.parse(dataMatch[1]); } catch (_) { return null; }
  if (!data || typeof data.token !== 'string' || !data.token) return null;
  const verified = await layarkacaFetch(`${origin}/verify.php`, pageUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Origin: origin,
      Referer: pageUrl,
    },
    body: JSON.stringify({token: data.token, is_ios: false}),
  });
  if (verified == null) return null;
  let result;
  try { result = JSON.parse(verified.body || '{}'); } catch (_) { return null; }
  if (result.status !== 'success' || typeof result.fileUrl !== 'string') return null;
  return layarkacaValidateMedia(
    result.fileUrl,
    {Referer: pageUrl, 'User-Agent': LAYARKACA_UA},
    'P2P',
  );
}

function layarkacaAbyssPageUrl(url) {
  const raw = String(url || '');
  const match = /^https?:\/\/([^/]+)\/([^?#]*)/i.exec(raw);
  if (!match) return null;
  const host = match[1].toLowerCase().replace(/^www\./, '');
  const mediaId = match[2].split('/').filter(Boolean)[0];
  if (!mediaId) return null;

  // Keep the local fixture override, but use ResolveURL's host-specific
  // normalization for production Abyss/Hydrax links.
  if (LAYARKACA_ABYSS_BASE_OVERRIDE) {
    return `${LAYARKACA_ABYSS_BASE_OVERRIDE.replace(/\/$/, '')}/${match[2]}`;
  }
  if (host === 'abyss.to') return raw;
  if (host === 'short.icu' || host === 'embedplayabyss.top') {
    return `https://abysscdn.com/?v=${encodeURIComponent(mediaId)}`;
  }
  if (host === 'abyssplayer.com') {
    return `https://abyssplayer.com/${mediaId}`;
  }
  if (host === 'abysscdn.com' || host === 'hydraxcdn.biz') {
    return `https://${host}/?v=${encodeURIComponent(mediaId)}`;
  }
  return `${LAYARKACA_ABYSS_BASE.replace(/\/$/, '')}/${match[2]}`;
}

function layarkacaAbyssDatas(html) {
  const match = /(?:const|var)\s+datas\s*=\s*["']([^"']+)["']/i.exec(html || '');
  if (!match) return null;
  const encoded = match[1].replace(/\\"/g, '"').trim();
  try {
    // Decode as bytes first. The encrypted `media` value may contain bytes
    // which are not valid UTF-8; replacing those bytes before AES decryption
    // corrupts the payload.
    const hex = host.codec.base64ToHex(encoded);
    let json = '';
    for (let index = 0; index < hex.length; index += 2) {
      json += String.fromCharCode(parseInt(hex.slice(index, index + 2), 16));
    }
    return JSON.parse(json);
  } catch (_) {
    try { return JSON.parse(host.codec.base64ToText(encoded)); } catch (_) { return null; }
  }
}

function layarkacaAbyssSourceUrl(value, pageUrl) {
  if (typeof value !== 'string' || !value.trim()) return null;
  const raw = value.trim();
  if (/^(?:https?:)?\/\//i.test(raw) || raw.startsWith('/') || raw.startsWith('./') ||
      /^[^\s]+\.(?:m3u8|mp4)(?:[?#]|$)/i.test(raw)) {
    return layarkacaUrl(raw, pageUrl);
  }
  return /^https?:\/\//i.test(raw) ? raw : null;
}

function layarkacaAbyssQualityHeight(entry) {
  if (!entry || typeof entry !== 'object') return null;
  const value = entry.height || entry.quality || entry.type || entry.label || entry.name || '';
  const match = /(?:^|[^0-9])(2160|1440|1080|720|480|360)\s*p?(?:[^0-9]|$)/i
    .exec(String(value));
  return match == null ? null : Number(match[1]);
}

function layarkacaAbyssGeneratedUrl(entry, payload, media) {
  if (!entry || !payload || payload.md5_id == null || payload.slug == null ||
      entry.res_id == null || entry.size == null || typeof entry.sub !== 'string' ||
      typeof savefilmAbyssPathToken !== 'function') return null;
  const domains = media && media.mp4 && media.mp4.domains;
  if (!Array.isArray(domains)) return null;
  const domain = domains.find((value) => String(value || '').includes(entry.sub));
  if (!domain) return null;
  const path = `/mp4/${payload.md5_id}/${entry.res_id}/${entry.size}?v=${payload.slug}`;
  const token = savefilmAbyssPathToken(path, entry.size);
  const host = String(domain).replace(/^https?:\/\//i, '').replace(/\/+$/, '');
  return `https://${host}/sora/${entry.size}/${token}`;
}

function layarkacaAbyssMediaEntries(media, pageUrl, payload) {
  if (!media || typeof media !== 'object') return [];
  const direct = (entry) => {
    if (!entry || typeof entry !== 'object') return null;
    const generated = layarkacaAbyssGeneratedUrl(entry, payload, media);
    if (generated) return generated;
    // Hydrax's current payload keeps the media host in `url` and the actual
    // rendition path in `path`. Returning the host root looks like a valid
    // HTTP URL but cannot play; join both parts before considering shortcuts.
    if (typeof entry.path === 'string' && entry.path.trim()) {
      const host = typeof entry.url === 'string' &&
          /^https?:\/\/[^/]+\/?$/i.test(entry.url.trim())
        ? entry.url.trim().replace(/\/$/, '')
        : pageUrl;
      const path = layarkacaUrl(
        `/${entry.path.trim().replace(/^\/+/, '')}`,
        host,
      );
      if (path) return path;
    }
    for (const key of ['file', 'url', 'master', 'src', 'source']) {
      const value = layarkacaAbyssSourceUrl(entry[key], pageUrl);
      if (!value) continue;
      // A source's `url` can be just its storage origin. It is only useful
      // when no separate path was supplied, or when it already names media.
      if (key === 'url' &&
          /^https?:\/\/[^/]+\/?$/i.test(value) &&
          !(entry.file || entry.master || entry.src || entry.source)) {
        continue;
      }
      return value;
    }
    return null;
  };
  const fromSources = (entries) => {
    if (!Array.isArray(entries)) return [];
    const sorted = entries.slice().sort((a, b) => {
      const left = Number(a && (a.size || a.height || a.quality ||
        layarkacaAbyssQualityHeight(a) || 0));
      const right = Number(b && (b.size || b.height || b.quality ||
        layarkacaAbyssQualityHeight(b) || 0));
      return (Number.isFinite(right) ? right : 0) -
        (Number.isFinite(left) ? left : 0);
    });
    return sorted.map((entry) => {
      if (entry && String(entry.codec || '').toLowerCase() === 'av1') return null;
      const generated = layarkacaAbyssGeneratedUrl(entry, payload, media);
      const value = generated || direct(entry);
      if (!value) return null;
      return {
        url: value,
        format: generated ? 'mp4' : layarkacaMediaFormat(value),
        label: String(entry && (entry.label || entry.quality || '') || ''),
        width: Number.isFinite(Number(entry && entry.width))
          ? Number(entry.width) : null,
        height: layarkacaAbyssQualityHeight(entry),
        bitrate: Number.isFinite(Number(entry && entry.bitrate))
          ? Number(entry.bitrate) : null,
      };
    }).filter((entry) => entry != null);
  };

  // Hydrax can expose both fixed MP4 renditions and adaptive HLS. Fixed
  // renditions are useful when the HLS URL is only a single media playlist;
  // use them when the payload really contains multiple quality entries.
  const mp4 = media.mp4;
  const mp4Entries = fromSources(mp4 && (mp4.sources || mp4.fristDatas));
  if (mp4Entries.length > 1) return mp4Entries;

  const hls = media.hls;
  const hlsUrl = direct(hls) ||
    fromSources(hls && (hls.sources || hls.fristDatas))[0]?.url;
  if (hlsUrl) {
    return [{
      url: hlsUrl,
      format: 'hls',
      label: 'Auto',
      width: null,
      height: null,
      bitrate: null,
    }];
  }
  if (mp4Entries.length > 0) return mp4Entries;
  const fallback = direct(media);
  return fallback ? [{
    url: fallback,
    format: layarkacaMediaFormat(fallback),
    label: '',
    width: null,
    height: null,
    bitrate: null,
  }] : [];
}

function layarkacaAbyssMediaUrl(media, pageUrl) {
  return layarkacaAbyssMediaEntries(media, pageUrl)[0]?.url || null;
}

async function layarkacaValidateAbyssEntries(entries, headers, fallbackLabel) {
  const valid = [];
  for (const entry of entries || []) {
    const resolved = await layarkacaValidateMedia(
      entry.url,
      headers,
      entry.label || fallbackLabel,
    );
    if (resolved) valid.push({...resolved, ...entry});
  }
  if (valid.length === 0) return null;
  const variants = [];
  const ids = new Set();
  for (const entry of valid) {
    if (!(entry.height > 0)) continue;
    const base = `quality-${entry.height}p`;
    let id = base;
    let suffix = 2;
    while (ids.has(id)) id = `${base}-${suffix++}`;
    ids.add(id);
    variants.push({
      id,
      url: entry.url,
      headers: entry.headers || headers || {},
      format: entry.format || layarkacaMediaFormat(entry.url),
      label: entry.label || `${entry.height}p`,
      width: entry.width || null,
      height: entry.height,
      bitrate: entry.bitrate || null,
    });
  }
  // Keep the quality picker in descending order, but make the provider's
  // default URL the highest validated rendition at or below 720p. The app
  // opens stream.url when Auto has no explicit preference, so this keeps
  // Hydrax Auto at 720p while leaving 1080p available for manual selection.
  const primary = valid.find((entry) => entry.height > 0 && entry.height <= 720) ||
    valid[valid.length - 1];
  return {
    url: primary.url,
    format: primary.format,
    headers: primary.headers,
    label: primary.label || fallbackLabel,
    ...(variants.length > 0 ? {variants} : {}),
  };
}

function layarkacaAbyssDecryptMedia(payload) {
  if (!payload || typeof payload.media !== 'string' ||
      payload.slug == null || payload.md5_id == null || payload.user_id == null ||
      typeof savefilmAesCtrDecrypt !== 'function') return null;
  try {
    const plain = savefilmAesCtrDecrypt(
      payload.media,
      `${payload.user_id}:${payload.slug}:${payload.md5_id}`,
    );
    return JSON.parse(plain);
  } catch (_) {
    return null;
  }
}

async function layarkacaResolveAbyss(url, referer, depth, seen) {
  const path = String(url).replace(/^https?:\/\/[^/]+/i, '').replace(/^\/+/, '');
  // Cs-Karma follows the short.icu redirect before invoking its extractor.
  // Keep that live redirect as the first attempt; the canonical Abyss URL is
  // still used for hosts that do not expose a usable redirect.
  const followsShortRedirect = /^https?:\/\/(?:www\.)?short\.icu\//i.test(url);
  const updatedUrl = (followsShortRedirect ? url : layarkacaAbyssPageUrl(url)) ||
    `${LAYARKACA_ABYSS_BASE.replace(/\/$/, '')}/${path}`;
  const baseHeaders = {
    'User-Agent': LAYARKACA_UA,
    Referer: `${layarkacaOrigin(updatedUrl) || LAYARKACA_ABYSS_BASE}/`,
  };
  const firstdoc = await layarkacaFetchManual(updatedUrl, referer, {
    headers: baseHeaders,
  });
  if (firstdoc == null || firstdoc.status < 200 || firstdoc.status >= 400) return null;
  const location = layarkacaHeader(firstdoc.headers, 'location');
  const pageUrl = location ? (layarkacaUrl(location, updatedUrl) || location) : updatedUrl;
  const response = location
    ? await layarkacaFetch(pageUrl, referer, {headers: baseHeaders})
    : (firstdoc.status >= 200 && firstdoc.status < 300
      ? firstdoc : await layarkacaFetch(pageUrl, referer, {headers: baseHeaders}));
  if (response == null) return null;
  const scriptData = response.body || '';

  // Older Abyss/Filemoon pages put a JWPlayer `file` URL in a Dean Edwards
  // packed script instead of the newer `datas` envelope. Match Nuvio's
  // extractFilemoon path without evaluating remote JavaScript. The local
  // unpacker and shared media assignment parser implement the safe subset.
  const unpacked = layarkacaUnpack(scriptData);
  for (const mediaUrl of layarkacaFilesimUrls(unpacked, pageUrl)) {
    const resolved = await layarkacaValidateMedia(
      mediaUrl,
      baseHeaders,
      'Abyss',
    );
    if (resolved) return resolved;
  }

  const encryptedMatch = /(?:const|let|var)\s+datas\s*=\s*["']([^"']+)["']/i.exec(scriptData);
  if (!encryptedMatch) return null;
  const encrypted = encryptedMatch[1].replace(/\\"/g, '"');

  // Current Abyss embeds a base64-encoded JSON object in `datas`. ResolveURL
  // extracts the playable URL from this object before attempting its legacy
  // encrypted-media path. Do the same locally so no WebView or decoder API is
  // needed for the normal HLS payload.
  const payload = layarkacaAbyssDatas(scriptData);
  const media = payload && (typeof payload.media === 'object'
    ? payload.media : layarkacaAbyssDecryptMedia(payload));
  const localEntries = media && typeof media === 'object'
    ? layarkacaAbyssMediaEntries(media, pageUrl, payload) : [];
  if (localEntries.length > 0) {
    const hasGeneratedAbyssUrl = localEntries.some((entry) => /\/sora\/\d+\//i.test(entry.url));
    const abyssHeaders = hasGeneratedAbyssUrl
      ? {...baseHeaders, Referer: pageUrl}
      : baseHeaders;
    const resolved = await layarkacaValidateAbyssEntries(
      localEntries,
      abyssHeaders,
      'Abyss',
    );
    if (resolved) return resolved;
  }

  // Preserve the existing Kotlin-compatible decoder as a fallback for older
  // pages or payloads whose `media` field is still encrypted.
  const decoded = await layarkacaFetch(LAYARKACA_ABYSS_DECODE_URL, pageUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Origin: 'https://enc-dec.app',
    },
    body: JSON.stringify({text: encrypted, agent: LAYARKACA_UA}),
  });
  if (decoded == null) return null;
  let data;
  try { data = JSON.parse(decoded.body || '{}'); } catch (_) { return null; }
  const sources = data && data.result && Array.isArray(data.result.sources)
    ? data.result.sources : [];
  const headers = {Referer: 'https://playhydrax.com/', 'User-Agent': LAYARKACA_UA};
  const fallbackEntries = sources
    .filter((source) => source && source.status !== false)
    .map((source) => {
      const sourceUrl = source.url || source.file;
      return {
        url: sourceUrl,
        format: layarkacaMediaFormat(sourceUrl),
        label: source.type || source.label || 'Abyss',
        width: null,
        height: layarkacaAbyssQualityHeight(source),
        bitrate: null,
      };
    })
    .filter((entry) => typeof entry.url === 'string');
  return layarkacaValidateAbyssEntries(fallbackEntries, headers, 'Abyss');
}

async function layarkacaResolveHownetwork(url, referer) {
  const id = layarkacaQueryParam(url, 'id');
  if (!id) return null;
  const origin = layarkacaOrigin(url) || 'https://cloud.hownetwork.xyz';
  const headers = {
    'Content-Type': 'application/x-www-form-urlencoded',
    Origin: origin,
    'X-Requested-With': 'XMLHttpRequest',
  };
  // Cs-Karma's Hownetwork sends r="" and d=<the extractor origin> to
  // api2.php. A newer LayarKaca extractor uses playeriframe/cloud instead.
  // Try both real upstream contracts, then its legacy api.php fallback.
  const attempts = [
    {endpoint: 'api2.php', r: '', d: origin},
    {
      endpoint: 'api2.php',
      r: 'https://playeriframe.sbs/',
      d: 'cloud.hownetwork.xyz',
    },
    {
      endpoint: 'api.php',
      r: 'https://playeriframe.sbs/',
      d: 'cloud.hownetwork.xyz',
    },
  ];
  for (const attempt of attempts) {
    const body = 'r=' + encodeURIComponent(attempt.r) +
      '&d=' + encodeURIComponent(attempt.d);
    const endpoint = `${origin}/${attempt.endpoint}?id=${encodeURIComponent(id)}`;
    const response = await layarkacaFetch(endpoint, url, {
      method: 'POST', headers, body,
    });
    if (response == null) continue;
    let data;
    try { data = JSON.parse(response.body || '{}'); } catch (_) { continue; }
    const sources = data && Array.isArray(data.data) ? data.data : [data];
    for (const source of sources) {
      const media = source && (source.file || source.link);
      const resolved = await layarkacaValidateMedia(
        media,
        {
          Referer: media,
          'User-Agent': LAYARKACA_UA,
          Accept: '*/*',
          'Accept-Language': 'en-US,en;q=0.5',
          'Cache-Control': 'no-cache',
          Pragma: 'no-cache',
          'Sec-Fetch-Dest': 'empty',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Site': 'same-origin',
        },
        source && source.label ? source.label : 'P2P',
      );
      if (resolved) return resolved;
    }
  }
  return null;
}

async function layarkacaResolveEmturbovid(url, referer) {
  const finalReferer = referer || 'https://emturbovid.com/';
  const response = await layarkacaFetch(url, finalReferer);
  if (response == null) return null;
  const match = /\bvar\s+urlPlay\s*=\s*["']([^"']+)["']/i.exec(response.body || '') ||
    /["'](.*?master\.m3u8.*?)["']/i.exec(response.body || '');
  if (!match) return null;
  return layarkacaValidateMedia(
    layarkacaUrl(match[1], response.url || url),
    {
      Referer: finalReferer,
      Origin: layarkacaOrigin(finalReferer) || 'https://emturbovid.com',
      'User-Agent': LAYARKACA_UA,
    },
    'Emturbovid',
  );
}

function layarkacaFilesimUrls(script, pageUrl) {
  const urls = [];
  const add = (value) => {
    const url = layarkacaUrl(String(value || '').replace(/\\\//g, '/'), pageUrl);
    if (url && /^https?:\/\//i.test(url) && !urls.includes(url)) urls.push(url);
  };
  // This is the same useful subset as JWPlayerHelper: explicit `file`
  // entries in `sources`, plus variable assignments for m3u8/master.txt.
  const file = /["']?file["']?\s*:\s*["']([^"']+)["']/gi;
  let match;
  while ((match = file.exec(script || '')) != null) add(match[1]);
  const playlist = /[:=]\s*["']([^"'\s]+(?:\.m3u8|master\.txt)[^"'\s]*)/gi;
  while ((match = playlist.exec(script || '')) != null) add(match[1]);
  return urls;
}

async function layarkacaResolveFilesim(url, referer, depth, seen) {
  const embedUrl = String(url).replace('/download/', '/e/');
  let response = await layarkacaFetch(embedUrl, referer, {skipCloudflare: true});
  if (response == null) return null;
  let pageUrl = response.url || embedUrl;
  const iframe = /<iframe\b([^>]*)>/i.exec(response.body || '');
  if (iframe) {
    const iframeUrl = layarkacaUrl(layarkacaAttr(iframe[1], 'src'), pageUrl);
    if (iframeUrl) {
      response = await layarkacaFetch(iframeUrl, pageUrl, {
        skipCloudflare: true,
        headers: {
          'Accept-Language': 'en-US,en;q=0.5',
          'Sec-Fetch-Dest': 'iframe',
        },
      });
      if (response == null) return null;
      pageUrl = response.url || iframeUrl;
    }
  }
  const raw = response.body || '';
  // Savefilm already carries a safe Dean-Edwards unpacker in the generated
  // bundle. Use it when available without evaluating the upstream script.
  const script = typeof savefilmUnpack === 'function' ? savefilmUnpack(raw) : raw;
  for (const media of layarkacaFilesimUrls(script, pageUrl)) {
    const resolved = await layarkacaValidateMedia(
      media,
      {Referer: pageUrl, 'User-Agent': LAYARKACA_UA},
      'Filesim',
    );
    if (resolved) return resolved;
  }

  return layarkacaResolveWebViewCandidate(
    pageUrl,
    referer || pageUrl,
    depth,
    seen,
  );
}

function layarkacaBase64Url(value) {
  let output = String(value || '').replace(/-/g, '+').replace(/_/g, '/');
  const remainder = output.length % 4;
  if (remainder) output += '='.repeat(4 - remainder);
  return output;
}

function layarkacaRandomHex(length) {
  let value = '';
  while (value.length < length) value += Math.floor(Math.random() * 16).toString(16);
  return value;
}

async function layarkacaResolveF16(url) {
  const match = /\/e\/([^/?#]+)/i.exec(url);
  if (!match) return null;
  const videoId = match[1];
  const origin = layarkacaOrigin(url) || 'https://f16px.com';
  const pageUrl = `${origin}/e/${videoId}`;
  const viewerId = layarkacaRandomHex(32);
  const deviceId = layarkacaRandomHex(32);
  const now = Math.floor(Date.now() / 1000);
  const payload = layarkacaBase64Url(host.codec.textToBase64(JSON.stringify({
    viewer_id: viewerId, device_id: deviceId, confidence: 0.91,
    iat: now, exp: now + 600,
  }))).replace(/=+$/g, '');
  const token =
    `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.${payload}.${layarkacaRandomHex(43)}`;
  const response = await layarkacaFetch(
    `${origin}/api/videos/${encodeURIComponent(videoId)}/embed/playback`, pageUrl,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Origin: origin,
        'x-embed-origin': 'playeriframe.sbs',
        'x-embed-parent': pageUrl,
        'x-embed-referer': 'https://playeriframe.sbs/',
      },
      body: JSON.stringify({
        fingerprint: {token, viewer_id: viewerId, device_id: deviceId, confidence: 0.91},
      }),
    },
  );
  if (response == null) return null;
  let playback;
  try { playback = JSON.parse(response.body || '{}').playback; } catch (_) { return null; }
  if (!playback || typeof playback.payload !== 'string' || typeof playback.iv !== 'string' ||
      !Array.isArray(playback.key_parts) || playback.key_parts.length < 2) return null;
  try {
    const keyHex = playback.key_parts.slice(0, 2)
      .map((part) => host.codec.base64ToHex(layarkacaBase64Url(part))).join('');
    const plaintext = host.crypto.aesGcmDecrypt(
      host.codec.hexToBase64(keyHex),
      layarkacaBase64Url(playback.iv),
      layarkacaBase64Url(playback.payload),
    );
    if (plaintext == null) return null;
    const decoded = JSON.parse(host.codec.base64ToText(plaintext));
    const sources = Array.isArray(decoded.sources) ? decoded.sources : [];
    for (const source of sources) {
      const resolved = await layarkacaValidateMedia(
        layarkacaUrl(source && source.url, pageUrl),
        {Referer: `${origin}/`, 'User-Agent': LAYARKACA_UA},
        source && source.label ? `CAST ${source.label}` : 'CAST',
      );
      if (resolved) return resolved;
    }
  } catch (_) {}
  return null;
}

async function layarkacaResolveUrl(
  url, referer, depth, seen, label, parentUrl,
) {
  if (!layarkacaIsHttpUrl(url) || depth > 4) return null;
  const visited = seen || new Set();
  if (visited.has(url)) return null;
  visited.add(url);
  if (/\.(?:m3u8|mp4)(?:[?#]|$)/i.test(url)) {
    return layarkacaValidateMedia(url, {Referer: referer || `${layarkacaBase}/`, 'User-Agent': LAYARKACA_UA}, label);
  }
  if (layarkacaMatches(url, LAYARKACA_PLAYCDN_PREFIX, /https?:\/\/(?:www\.)?playcdn\.de\//i)) {
    return layarkacaResolvePlaycdn(url, referer);
  }
  if (/(?:\/iframe(?:3)?\/p2p\/)/i.test(url)) {
    const p2p = await layarkacaResolveP2pIframe(url, referer);
    if (p2p) return p2p;
    // A failed P2P API can still resolve the selected player in a browser
    // context. Ask the host to select it in the parent page's DOM.
    if (parentUrl && parentUrl !== url) {
      return layarkacaResolveWebViewCandidate(
        parentUrl, referer, depth, seen, label, true, url,
      );
    }
    return layarkacaResolveWebViewCandidate(
      url, referer, depth, visited, label,
    );
  }
  if (layarkacaMatches(
    url,
    LAYARKACA_ABYSS_PREFIX,
    /https?:\/\/(?:www\.)?(?:abyssplayer\.com|abyss\.to|abysscdn\.com|hydraxcdn\.biz|short\.icu|short\.ink|embedplayabyss\.top)\//i,
  )) {
    return layarkacaResolveAbyss(url, referer, depth, visited);
  }
  if (layarkacaMatches(url, LAYARKACA_HOWNETWORK_PREFIX, /https?:\/\/(?:stream|cloud)\.hownetwork\.xyz\//i)) {
    return layarkacaResolveHownetwork(url, referer);
  }
  if (layarkacaMatches(url, LAYARKACA_EMTURBOVID_PREFIX, /https?:\/\/emturbovid\.com\//i)) {
    return layarkacaResolveEmturbovid(url, referer);
  }
  if (layarkacaMatches(
    url,
    LAYARKACA_FILESIM_PREFIX,
    /https?:\/\/(?:www\.)?(?:co4nxtrl\.com|furher\.in|723qrh1p\.fun|turbovidhls\.com)\//i,
  )) {
    return layarkacaResolveFilesim(url, referer, depth, visited);
  }
  if (layarkacaMatches(url, LAYARKACA_F16_PREFIX, /https?:\/\/(?:www\.)?f16px\.com\/e\//i)) {
    return layarkacaResolveF16(url);
  }
  if (layarkacaMatches(url, LAYARKACA_FILEMOON_PREFIX, /https?:\/\/filemoon\.sx\//i)) {
    return layarkacaResolveIframe(url, referer, depth, visited, label);
  }
  if (layarkacaMatches(url, LAYARKACA_IFRAME_PREFIX, /https?:\/\/playeriframe\.sbs\//i)) {
    return layarkacaResolveIframe(url, referer, depth, visited, label);
  }
  return layarkacaResolveIframe(
    url, referer, depth, visited, label, parentUrl,
  );
}

async function layarkacaResolveServerSource(sourceId, server) {
  const prefix = `${server.providerKey}:`;
  if (typeof sourceId !== 'string' || !sourceId.startsWith(prefix)) {
    throw new Error(`Invalid ${server.name} source id`);
  }
  const payload = layarkacaDecode(sourceId.slice(prefix.length));
  if (!payload || payload.p !== server.key || typeof payload.d !== 'string' || !Number.isInteger(payload.i)) {
    throw new Error(`Malformed ${server.name} source id`);
  }
  const query = {
    title: payload.t,
    year: Number.isInteger(payload.y) ? payload.y : null,
    isEpisode: payload.k === true,
    season: Number.isInteger(payload.s) ? payload.s : null,
    episode: Number.isInteger(payload.e) ? payload.e : null,
  };
  const page = await layarkacaWatchPage(query, payload.d, payload.w || null);
  if (!page || !page.players[payload.i]) throw new Error('LayarKaca player is unavailable');
  const player = page.players[payload.i];
  const playerReferer = page.watchUrl || page.detailUrl;
  // Match LayarKacaProvider: dispatch the selected URL through the extractor
  // chain. In particular, /iframe3/p2p/ must reach the P2P api2.php path
  // instead of being parsed as an ad-bearing HTML shell.
  let resolved = await layarkacaResolveUrl(
    player.url,
    playerReferer,
    0,
    new Set(),
    player.label || server.name,
    page.watchUrl,
  );
  // The /iframe3/ endpoint is a browser-only shell. In a real page it creates
  // a second iframe (for example an Abyss player) after the parent watch page
  // has established the embedding context. If the direct request is blocked
  // or empty, let the generic WebView resolver observe that parent navigation
  // and return the nested extractor URL. The app still knows nothing about
  // this provider-specific chain; only this extension supplies the pattern.
  if (!resolved && page.watchUrl && page.watchUrl !== player.url &&
      !/\/iframe3\//i.test(player.url)) {
    resolved = await layarkacaResolveWebViewCandidate(
      page.watchUrl,
      playerReferer,
      0,
      new Set(),
      player.label || server.name,
    );
  }
  if (!resolved) throw new Error('LayarKaca extractor returned no playable media');
  return resolved;
}

async function layarkacaResolveSource(sourceId) {
  if (typeof sourceId !== 'string') throw new Error('Invalid LayarKaca source id');
  const separator = sourceId.indexOf(':');
  const provider = LAYARKACA_SERVERS.find(
    (server) => server.providerKey === sourceId.slice(0, separator),
  );
  if (!provider) throw new Error('Invalid LayarKaca source id');
  return layarkacaResolveServerSource(sourceId, provider);
}

globalThis.__streamProviders = globalThis.__streamProviders || [];
for (const server of LAYARKACA_SERVERS) {
  globalThis.__streamProviders.push({
    providerKey: server.providerKey,
    fanoutGroup: LAYARKACA_PROVIDER_PREFIX,
    sources: (args) => layarkacaSourcesForServer(args, server),
    resolve: (sourceId) => layarkacaResolveServerSource(sourceId, server),
  });
}

globalThis.__layarkacaHighlightPage = (category, page) => {
  if (category !== 'movie' && category !== 'tv') return {items: []};
  return layarkacaCatalogFeedPage(category, page);
};

globalThis.__metaProviders = globalThis.__metaProviders || [];
globalThis.__metaProviders.push({
  providerId: LAYARKACA_CATALOG_PROVIDER_ID,
  meta: layarkacaCatalogMeta,
});

globalThis.__extension = globalThis.__extension || {};
if (!globalThis.__extension.sources) {
  globalThis.__extension.sources = async (args) => {
    const grouped = new Map();
    const calls = [];
    for (const provider of globalThis.__streamProviders) {
      const groupKey = provider.fanoutGroup || `provider:${provider.providerKey}`;
      if (!grouped.has(groupKey)) grouped.set(groupKey, []);
      grouped.get(groupKey).push(provider);
    }
    for (const providers of grouped.values()) {
      calls.push(Promise.all(providers.map((provider) =>
        Promise.resolve().then(() => provider.sources(args)).catch(() => ({sources: []})),
      )).then((results) => ({
        sources: results.flatMap((result) => result.sources || []),
      })));
    }
    if (args.fast !== true) {
      const results = await Promise.all(calls);
      return {sources: results.flatMap((result) => result.sources || [])};
    }
    return new Promise((resolve) => {
      let remaining = calls.length;
      let returned = false;
      for (const call of calls) call.then((result) => {
        if (returned) return;
        const sources = Array.isArray(result.sources) ? result.sources : [];
        if (sources.length > 0) { returned = true; resolve({sources}); return; }
        remaining -= 1;
        if (remaining === 0) resolve({sources: []});
      });
    });
  };
  globalThis.__extension.resolve = async (args) => {
    const sourceId = args.sourceId;
    const separator = sourceId.indexOf(':');
    if (separator < 0) throw new Error(`Malformed source id: ${sourceId}`);
    const provider = globalThis.__streamProviders.find(
      (entry) => entry.providerKey === sourceId.slice(0, separator));
    if (!provider) throw new Error(`No stream provider registered for "${sourceId.slice(0, separator)}"`);
    return provider.resolve(sourceId);
  };
}
