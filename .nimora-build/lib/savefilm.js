// Savefilm21 NSFW catalogue.
//
// Savefilm pages provide both the NSFW catalogue and the player pages used to
// discover the site's HLS/MP4 sources. Catalogue items still use TMDB refs so
// the other movie/TV providers remain available as fallbacks.

const SAVEFILM_DEFAULT_BASE = 'https://new13.savefilm21info.com';
const SAVEFILM_DIRECTORY =
  globalThis.__savefilmDirectoryUrl ||
  'https://raw.githubusercontent.com/Asm0d3usX/CloudX/builds/Website.json';
const SAVEFILM_PROVIDER_KEY = 'savefilm';
const SAVEFILM_PROVIDER_ID = 'nimora.savefilm';
const SAVEFILM_NSFW_CATALOG_ID = 'savefilm_nsfw';
const SAVEFILM_ADULT_QUERY =
  's=&search=advanced&post_type=&index=&orderby=&genre=adult&movieyear=&country=&quality=';
const SAVEFILM_UA =
  'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/137.0.0.0 Mobile Safari/537.36';

let savefilmBase = globalThis.__savefilmBaseUrl || null;
const savefilmDetailUrlsByRef = new Map();

function savefilmHeaders(referer) {
  return {
    Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    Referer: referer || `${savefilmBase || SAVEFILM_DEFAULT_BASE}/`,
    'User-Agent': SAVEFILM_UA,
  };
}

async function savefilmGet(url, referer) {
  try {
    const response = await fetch(url, { headers: savefilmHeaders(referer) });
    return response.status >= 200 && response.status < 300 ? response : null;
  } catch (_) {
    return null;
  }
}

async function savefilmActiveBase() {
  if (savefilmBase) return savefilmBase;
  const response = await savefilmGet(SAVEFILM_DIRECTORY, SAVEFILM_DEFAULT_BASE);
  if (response != null) {
    try {
      const urls = JSON.parse(response.body).savefilm;
      if (Array.isArray(urls) && typeof urls[0] === 'string' && /^https?:\/\//i.test(urls[0])) {
        savefilmBase = urls[0].replace(/\/$/, '');
      }
    } catch (_) {}
  }
  return savefilmBase || SAVEFILM_DEFAULT_BASE;
}

function savefilmUrl(value, base) {
  if (typeof value !== 'string' || !value.trim()) return null;
  const raw = value.trim();
  if (/^https?:\/\//i.test(raw)) return raw;
  const root = (base || savefilmBase || SAVEFILM_DEFAULT_BASE).replace(/\/$/, '');
  if (raw.startsWith('//')) return `https:${raw}`;
  return raw.startsWith('/') ? `${root}${raw}` : `${root}/${raw}`;
}

function savefilmText(value) {
  const entities = {
    amp: '&', apos: "'", gt: '>', hellip: '…', lt: '<', mdash: '—',
    nbsp: ' ', ndash: '–', quot: '"', rsquo: '’', lsquo: '‘', ldquo: '“',
    rdquo: '”', copy: '©', reg: '®',
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

function savefilmAttr(attributes, name) {
  const match = new RegExp(`${name}\\s*=\\s*["']([^"']+)`, 'i').exec(attributes || '');
  return match == null ? null : match[1];
}

function savefilmMetaContent(html, name) {
  const match = new RegExp(
    `<meta\\b[^>]*(?:name|property)\\s*=\\s*["']${name}["'][^>]*>`, 'i',
  ).exec(html || '');
  return match == null ? null : savefilmAttr(match[0], 'content');
}

function savefilmNormalize(value) {
  return savefilmText(value)
    .replace(/[([]\s*(?:19|20)\d{2}\s*[)\]]/g, ' ')
    .replace(/\b(?:19|20)\d{2}\b/g, ' ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

function savefilmTitleAndYear(value) {
  const title = savefilmText(value);
  const year = /\b((?:19|20)\d{2})\b/.exec(title);
  return {
    title: title.replace(/\s*[-–—|:]?\s*\(?((?:19|20)\d{2})\)?\s*$/i, '').trim() || title,
    ...(year ? { year: Number(year[1]) } : {}),
  };
}

function savefilmParseArticles(html, base) {
  const results = [];
  const articles = /<article\b([^>]*\bclass\s*=\s*["'][^"']*\bitem-infinite\b[^"']*["'][^>]*)>([\s\S]*?)<\/article>/gi;
  let article;
  while ((article = articles.exec(html || '')) != null) {
    const body = article[2];
    const titleMatch = /<h2\b[^>]*\b(?:entry-title|headline)\b[^>]*>[\s\S]*?<a\b([^>]*)>([\s\S]*?)<\/a>/i.exec(body);
    if (!titleMatch) continue;
    const url = savefilmUrl(savefilmAttr(titleMatch[1], 'href'), base);
    const parsed = savefilmTitleAndYear(titleMatch[2]);
    if (!url || !parsed.title) continue;
    const image = /<img\b([^>]*)>/i.exec(body);
    const imageAttr = image == null ? null : (
      savefilmAttr(image[1], 'data-lazy-src') ||
      savefilmAttr(image[1], 'data-src') ||
      savefilmAttr(image[1], 'src')
    );
    const poster = savefilmUrl(
      imageAttr == null ? null : imageAttr.split(',')[0].trim().split(/\s+/)[0], base,
    );
    const ratingMatch = /<div\b[^>]*\bgmr-rating-item\b[^>]*>([\s\S]*?)<\/div>/i.exec(body);
    const rating = ratingMatch == null ? null : Number(/\d+(?:\.\d+)?/.exec(savefilmText(ratingMatch[1]))?.[0]);
    const epsMatch = /<div\b[^>]*\bgmr-numbeps\b[^>]*>[\s\S]*?<span[^>]*>(\d+)/i.exec(body);
    results.push({
      url,
      title: parsed.title,
      ...(parsed.year ? { year: parsed.year } : {}),
      ...(poster ? { poster } : {}),
      ...(Number.isFinite(rating) ? { rating } : {}),
      ...(epsMatch ? { episodes: Number(epsMatch[1]) } : {}),
    });
  }
  return results;
}

function savefilmEncode(value) {
  return host.codec.textToBase64(JSON.stringify(value))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function savefilmDecode(value) {
  let encoded = String(value || '').replace(/-/g, '+').replace(/_/g, '/');
  const remainder = encoded.length % 4;
  if (remainder) encoded += '='.repeat(4 - remainder);
  try { return JSON.parse(host.codec.base64ToText(encoded)); } catch (_) { return null; }
}

function savefilmTmdbYear(result) {
  const value = result && (result.release_date || result.first_air_date);
  const year = typeof value === 'string' ? Number(value.slice(0, 4)) : NaN;
  return Number.isInteger(year) && year > 0 ? year : null;
}

async function savefilmCatalogItem(result) {
  const mediaType = /\/tv\//i.test(result.url) ? 'tv' : 'movie';
  if (typeof tmdbSearchType !== 'function' || typeof tmdbToMediaItem !== 'function') {
    return null;
  }
  const matches = await tmdbSearchType(mediaType, result.title, 1, {
    include_adult: 'true',
  });
  const wanted = savefilmNormalize(result.title);
  const scored = matches.map((entry, index) => {
    const candidate = entry && entry.result;
    const candidateTitle = savefilmNormalize(candidate && (candidate.title || candidate.name));
    if (!candidate || candidate.id == null || !candidateTitle) return null;
    const exact = candidateTitle === wanted;
    const overlap = candidateTitle.includes(wanted) || wanted.includes(candidateTitle);
    if (!exact && !overlap) return null;
    const candidateYear = savefilmTmdbYear(candidate);
    const yearDelta = Number.isInteger(result.year) && candidateYear != null
      ? Math.abs(result.year - candidateYear) : 0;
    return {
      result: candidate,
      score: (exact ? 0 : 20) + yearDelta + index / 1000,
    };
  }).filter((entry) => entry != null).sort((a, b) => a.score - b.score);
  if (scored.length === 0) return null;

  const item = tmdbToMediaItem(scored[0].result, mediaType);
  if (!item || !item.ref || typeof item.ref.id !== 'string') return null;
  // The catalog owns the Savefilm title. Keep the TMDB ref for shared
  // providers, but do not replace the provider's shorter searchable title
  // with TMDB's often-expanded adult title.
  item.title = result.title;
  // Keep the provider-owned URL in the resolver process. MediaItemV2 is a
  // strict wire type, so provider-private fields cannot be added to the item.
  // The title-based lookup below remains the restart-safe fallback.
  savefilmDetailUrlsByRef.set(item.ref.id, result.url);
  if (!item.artwork && result.poster) {
    item.artwork = { portrait: { url: result.poster } };
  } else if (result.poster && !item.artwork.portrait) {
    item.artwork.portrait = { url: result.poster };
  }
  return item;
}

function savefilmAdultUrl(base, page) {
  const root = base.replace(/\/$/, '');
  return page > 1
    ? `${root}/page/${page}/?${SAVEFILM_ADULT_QUERY}`
    : `${root}/?${SAVEFILM_ADULT_QUERY}`;
}

function savefilmHasNextPage(html) {
  return /<a\b[^>]*\bclass\s*=\s*["'][^"']*\bnext\b[^"']*["'][^>]*>/i.test(html || '');
}

async function savefilmNsfwCatalog(query) {
  const base = await savefilmActiveBase();
  const requested = Number(query && query.page);
  const page = Number.isInteger(requested) && requested > 0 ? requested : 1;
  const url = savefilmAdultUrl(base, page);
  const response = await savefilmGet(url, `${base}/`);
  if (response == null) return { sections: [{ id: 'savefilm-adult', title: 'Savefilm Adult', items: [] }] };
  const results = savefilmParseArticles(response.body, base);
  const items = (await Promise.all(results.map(savefilmCatalogItem)))
    .filter((item) => item != null);
  const result = {
    sections: [{
      id: 'savefilm-adult',
      title: 'Savefilm Adult',
      items,
    }],
  };
  if (savefilmHasNextPage(response.body)) result.nextPage = String(page + 1);
  return result;
}

function savefilmRefPayload(ref) {
  const id = ref && typeof ref.id === 'string' ? ref.id : '';
  const prefix = `${SAVEFILM_PROVIDER_KEY}:`;
  if (!id.startsWith(prefix)) return null;
  return savefilmDecode(id.slice(prefix.length).replace(/^(?:catalog|episode|search):/, ''));
}

function savefilmItemDetailUrl(item) {
  const ref = item && item.ref && typeof item.ref.id === 'string' ? item.ref.id : null;
  const value = ref == null ? null : savefilmDetailUrlsByRef.get(ref);
  return typeof value === 'string' && /^https?:\/\/[^\s]+$/i.test(value)
    ? value : null;
}

function savefilmDescription(html) {
  const block = /<(?:div|p)\b[^>]*\b(?:itemprop\s*=\s*["']description["']|class\s*=\s*["'][^"']*entry-content-single[^"']*)[^>]*>([\s\S]*?)<\/(?:div|p)>/i.exec(html || '');
  return block ? savefilmText(block[1]) : savefilmText(savefilmMetaContent(html, 'description'));
}

function savefilmDetailYear(html) {
  const labelled = /<(?:div|span|p)\b[^>]*class\s*=\s*["'][^"']*gmr-moviedata[^"']*["'][^>]*>([\s\S]*?)<\/\w+>/gi;
  let row;
  while ((row = labelled.exec(html || '')) != null) {
    if (/(?:year|release|tahun)\s*:/i.test(savefilmText(row[1]))) {
      const year = /\b((?:19|20)\d{2})\b/.exec(savefilmText(row[1]));
      if (year) return Number(year[1]);
    }
  }
  const date = /datetime\s*=\s*["']((?:19|20)\d{2})/i.exec(html || '');
  return date ? Number(date[1]) : null;
}

function savefilmDetailRating(html) {
  const value = /itemprop\s*=\s*["']ratingValue["'][^>]*content\s*=\s*["']([^"']+)/i.exec(html || '')
    || /<div\b[^>]*\bgmr-rating-item\b[^>]*>([\s\S]*?)<\/div>/i.exec(html || '');
  const rating = value == null ? NaN : Number(/\d+(?:\.\d+)?/.exec(savefilmText(value[1]))?.[0]);
  return Number.isFinite(rating) ? rating : null;
}

function savefilmDetailItem(ref, html, fallbackUrl) {
  const titleMatch = /<h1\b[^>]*\bentry-title\b[^>]*>([\s\S]*?)<\/h1>/i.exec(html || '');
  const parsed = savefilmTitleAndYear(
    titleMatch ? titleMatch[1] : savefilmMetaContent(html, 'og:title') || 'Savefilm video',
  );
  const payload = savefilmRefPayload(ref);
  const url = payload && payload.u || fallbackUrl || '';
  const item = {
    ref,
    kind: /\/tv\//i.test(url) ? 'series' : 'video',
    title: parsed.title,
  };
  const image = savefilmMetaContent(html, 'og:image');
  if (image) item.artwork = { portrait: { url: savefilmUrl(image) } };
  const year = savefilmDetailYear(html) || parsed.year;
  if (Number.isInteger(year)) item.releaseYear = year;
  const rating = savefilmDetailRating(html);
  if (Number.isFinite(rating)) item.rating = rating;
  return item;
}

function savefilmEpisodeNumber(value) {
  const text = savefilmText(value);
  const match = /(?:s\d{1,2}\s*)?(?:e|eps?|episode)\s*[-_: ]*(\d+)/i.exec(text)
    || /(?:^|\D)(\d+)(?:\D|$)/.exec(text);
  return match ? Number(match[1]) : null;
}

function savefilmSeasonNumber(value) {
  const match = /(?:season|musim|s)\s*[-_: ]*(\d{1,2})/i.exec(savefilmText(value));
  return match ? Number(match[1]) : null;
}

function savefilmEpisodeGroups(html, parentRef, poster, base, parentUrl) {
  const groups = new Map();
  const links = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = links.exec(html || '')) != null) {
    const attributes = match[1];
    const href = savefilmAttr(attributes, 'href');
    const raw = `${savefilmAttr(attributes, 'title') || ''} ${match[2]}`;
    if (!href || !/(?:episode|eps?|\be\d+\b|season|musim)/i.test(raw)) continue;
    const position = savefilmEpisodeNumber(raw);
    if (!Number.isInteger(position) || position < 1) continue;
    const season = savefilmSeasonNumber(raw) || 1;
    const url = savefilmUrl(href, base);
    if (!url) continue;
    const groupId = `season:${season}`;
    const group = groups.get(groupId) || { id: groupId, title: `Season ${season}`, episodes: [] };
    const ref = {
      extensionId: 'nimora',
      providerId: SAVEFILM_PROVIDER_ID,
      id: `${SAVEFILM_PROVIDER_KEY}:episode:${savefilmEncode({ u: url, p: parentUrl, s: season, e: position })}`,
    };
    if (!group.episodes.some((episode) => episode.ref.id === ref.id)) {
      group.episodes.push({
        ref,
        title: `Episode ${position}`,
        position,
        ...(poster ? { artwork: { portrait: { url: poster } } } : {}),
      });
    }
    groups.set(groupId, group);
  }
  return [...groups.values()]
    .map((group) => ({
      ...group,
      episodes: group.episodes.sort((a, b) => a.position - b.position),
    }))
    .filter((group) => group.episodes.length > 0)
    .sort((a, b) => Number(a.id.split(':')[1]) - Number(b.id.split(':')[1]));
}

async function savefilmMeta(args) {
  const ref = args && args.ref;
  const payload = savefilmRefPayload(ref);
  if (!payload || typeof payload.u !== 'string') throw new Error('Malformed Savefilm media ref');
  const base = await savefilmActiveBase();
  const response = await savefilmGet(payload.u, `${base}/`);
  if (response == null) throw new Error('Savefilm detail request failed');
  const detail = { item: savefilmDetailItem(ref, response.body, payload.u) };
  const description = savefilmDescription(response.body);
  if (description) detail.description = description;
  const year = detail.item.releaseYear;
  if (Number.isInteger(year)) detail.facts = [{ label: 'Year', value: String(year) }];
  const poster = detail.item.artwork?.portrait?.url || null;
  if (/\/tv\//i.test(payload.u)) {
    const groups = savefilmEpisodeGroups(response.body, ref, poster, base, payload.u);
    if (groups.length > 0) {
      const last = groups[groups.length - 1];
      detail.episodeGuide = {
        groups,
        defaultEpisodeRef: last.episodes[last.episodes.length - 1].ref,
      };
    }
  }
  return detail;
}

function savefilmItemQuery(item) {
  const extra = item && item.extra && typeof item.extra === 'object' ? item.extra : {};
  const episode = item && item.episode && typeof item.episode === 'object' ? item.episode : null;
  const group = episode && typeof episode.groupId === 'string' ? episode.groupId : '';
  const season = /(?:^|:)season:(\d+)/i.exec(group);
  return {
    title: String(extra.seriesTitle || (episode && item.subtitle) || item && item.title || '').trim(),
    season: Number.isInteger(extra.season) ? extra.season : season ? Number(season[1]) : null,
    episode: Number.isInteger(extra.episode) ? extra.episode : episode && Number.isInteger(episode.position) ? episode.position : null,
    isEpisode: item && item.kind === 'episode',
  };
}

function savefilmSearchTitleVariants(title) {
  const raw = String(title || '').trim();
  const clean = raw.replace(/[([]\s*(?:19|20)\d{2}\s*[)\]]/g, ' ')
    .replace(/\b(?:19|20)\d{2}\b/g, ' ')
    .replace(/\s+/g, ' ').trim();
  return [raw, clean].filter((value, index, values) => value && values.indexOf(value) === index);
}

async function savefilmItemTitleVariants(item, fallback) {
  if (typeof globalThis.__animeTitleVariants !== 'function') return [fallback];
  try {
    const variants = await globalThis.__animeTitleVariants(item);
    return Array.isArray(variants) && variants.length > 0 ? variants : [fallback];
  } catch (_) {
    return [fallback];
  }
}

async function savefilmFindResult(title, base) {
  for (const variant of savefilmSearchTitleVariants(title)) {
    const url = `${base}/?s=${encodeURIComponent(variant)}&post_type[]=post&post_type[]=tv`;
    const response = await savefilmGet(url, `${base}/`);
    if (response == null) continue;
    const results = savefilmParseArticles(response.body, base);
    const wanted = savefilmNormalize(variant);
    const scored = results.map((result, index) => {
      const candidate = savefilmNormalize(result.title);
      if (!candidate) return null;
      const exact = candidate === wanted;
      const overlap = candidate.includes(wanted) || wanted.includes(candidate);
      return !exact && !overlap ? null : { result, score: (exact ? 0 : 10) + index / 1000 };
    }).filter((entry) => entry != null).sort((a, b) => a.score - b.score);
    if (scored.length > 0) return { result: scored[0].result, results };
  }
  return null;
}

function savefilmEpisodeUrl(html, season, episode, base) {
  const links = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = links.exec(html || '')) != null) {
    const raw = `${savefilmAttr(match[1], 'title') || ''} ${match[2]}`;
    const foundSeason = savefilmSeasonNumber(raw) || 1;
    const foundEpisode = savefilmEpisodeNumber(raw);
    if (foundSeason === season && foundEpisode === episode) return savefilmUrl(savefilmAttr(match[1], 'href'), base);
  }
  return null;
}

function savefilmPlayerPageUrls(html, detailUrl, base) {
  const urls = [detailUrl];
  const tabLists = /<ul\b[^>]*\bmuvipro-player-tabs\b[^>]*>([\s\S]*?)<\/ul>/gi;
  let tabList;
  while ((tabList = tabLists.exec(html || '')) != null) {
    const tabLinks = /<a\b([^>]*)>/gi;
    let tab;
    while ((tab = tabLinks.exec(tabList[1])) != null) {
      const tabUrl = savefilmPageUrl(savefilmAttr(tab[1], 'href'), detailUrl, base);
      if (tabUrl && !urls.includes(tabUrl)) urls.push(tabUrl);
    }
  }
  const tabs = /<a\b([^>]*)>/gi;
  let match;
  while ((match = tabs.exec(html || '')) != null) {
    const classes = savefilmAttr(match[1], 'class') || '';
    const href = savefilmAttr(match[1], 'href');
    if (!href || (!/muvipro-player-tabs|player-tab|server|turbovidhls\.com/i.test(classes + ' ' + href))) continue;
    const url = savefilmPageUrl(href, detailUrl, base);
    if (url && !urls.includes(url)) urls.push(url);
  }
  return urls;
}

function savefilmPageUrl(value, pageUrl, base) {
  if (typeof value !== 'string' || !value.trim()) return null;
  const raw = value.trim();
  if (/^https?:\/\//i.test(raw) || raw.startsWith('//')) return savefilmUrl(raw, base);
  const page = typeof pageUrl === 'string' && pageUrl
    ? pageUrl.split(/[?#]/, 1)[0] : null;
  if (raw.startsWith('?') && page) return `${page}${raw}`;
  if (raw.startsWith('#') && page) return `${page}${raw}`;
  if (raw.startsWith('/')) return savefilmUrl(raw, base);
  if (page) return savefilmUrl(raw, page.slice(0, page.lastIndexOf('/') + 1));
  return savefilmUrl(raw, base);
}

function savefilmIframeUrls(html, pageUrl) {
  const urls = [];
  const frames = /<iframe\b([^>]*)>/gi;
  let match;
  while ((match = frames.exec(html || '')) != null) {
    const value = savefilmAttr(match[1], 'data-litespeed-src') || savefilmAttr(match[1], 'src');
    const url = savefilmPageUrl(value, pageUrl, savefilmBase || SAVEFILM_DEFAULT_BASE);
    if (url && !urls.includes(url)) urls.push(url);
  }
  return urls;
}

// Some Savefilm-compatible hosts return a tiny HTML shell that forwards the
// request with window.location.replace(). CloudStream's loadExtractor follows
// that shell before handing the page to its extractor; do the same here while
// keeping the redirect depth bounded.
function savefilmPlayerRedirectUrl(html, pageUrl) {
  const match = /(?:window\.)?location(?:\.href)?\s*=\s*['"]([^'"]+)|(?:window\.)?location\.replace\(\s*['"]([^'"]+)['"]\s*\)/i.exec(html || '');
  const value = match && (match[1] || match[2]);
  return value ? savefilmPageUrl(value, pageUrl, savefilmBase) : null;
}

async function savefilmPlayerResponse(url, referer, depth = 0) {
  const response = await savefilmGet(url, referer);
  if (response == null) return null;
  if (depth >= 3) return { url, response };
  // Only follow a redirect from a small shell. Full player pages often have
  // ad/anti-frame location assignments that are not the media redirect.
  const redirected = response.body.length <= 2048
    ? savefilmPlayerRedirectUrl(response.body, url) : null;
  if (!redirected || redirected === url) return { url, response };
  return savefilmPlayerResponse(redirected, url, depth + 1);
}

// Abyss embeds its media as a binary string inside a Base64 JSON envelope.
// The browser player derives an ASCII MD5 key and decrypts that string with
// AES-256-CTR. Keep this small, deterministic implementation local to the
// provider so we never execute the remote player bundle.
function savefilmMd5HexBytes(input) {
  const bytes = Array.isArray(input)
    ? input.map((value) => Number(value) & 0xff)
    : [...String(input)].map((char) => char.charCodeAt(0) & 0xff);
  const bitLength = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  for (let shift = 0; shift < 8; shift += 1) bytes.push((bitLength / (2 ** (8 * shift))) & 0xff);
  let a = 0x67452301;
  let b = 0xefcdab89;
  let c = 0x98badcfe;
  let d = 0x10325476;
  const shifts = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  const constants = Array.from(
    { length: 64 }, (_, index) => Math.floor(Math.abs(Math.sin(index + 1)) * 0x100000000) >>> 0,
  );
  for (let offset = 0; offset < bytes.length; offset += 64) {
    const words = Array.from({ length: 16 }, (_, index) => {
      const position = offset + index * 4;
      return bytes[position] |
        (bytes[position + 1] << 8) |
        (bytes[position + 2] << 16) |
        (bytes[position + 3] << 24);
    });
    const original = [a, b, c, d];
    for (let index = 0; index < 64; index += 1) {
      let f;
      let g;
      if (index < 16) {
        f = (b & c) | (~b & d);
        g = index;
      } else if (index < 32) {
        f = (d & b) | (~d & c);
        g = (5 * index + 1) % 16;
      } else if (index < 48) {
        f = b ^ c ^ d;
        g = (3 * index + 5) % 16;
      } else {
        f = c ^ (b | ~d);
        g = (7 * index) % 16;
      }
      const next = d;
      const sum = (a + f + constants[index] + words[g]) >>> 0;
      d = c;
      c = b;
      b = (b + ((sum << shifts[index]) | (sum >>> (32 - shifts[index])))) >>> 0;
      a = next;
    }
    a = (a + original[0]) >>> 0;
    b = (b + original[1]) >>> 0;
    c = (c + original[2]) >>> 0;
    d = (d + original[3]) >>> 0;
  }
  const littleEndian = (word) => Array.from({ length: 4 }, (_, index) => (word >>> (8 * index)) & 0xff);
  return [...littleEndian(a), ...littleEndian(b), ...littleEndian(c), ...littleEndian(d)]
    .map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function savefilmMd5Hex(value) {
  return savefilmMd5HexBytes(value);
}

const SAVEFILM_AES_SBOX =
  ('637c777bf26b6fc53001672bfed7ab76' +
    'ca82c97dfa5947f0add4a2af9ca472c0' +
    'b7fd9326363ff7cc34a5e5f171d83115' +
    '04c723c31896059a071280e2eb27b275' +
    '09832c1a1b6e5aa0523bd6b329e32f84' +
    '53d100ed20fcb15b6acbbe394a4c58cf' +
    'd0efaa fb434d338545f9027f503c9fa8'.replace(/\s/g, '') +
    '51a3408f929d38f5bcb6da2110fff3d2' +
    'cd0c13ec5f974417c4a77e3d645d1973' +
    '60814fdc222a908846eeb814de5e0bdb' +
    'e0323a0a4906245cc2d3ac629195e479' +
    'e7c8376d8dd54ea96c56f4ea657aae08' +
    'ba78252e1ca6b4c6e8dd741f4bbd8b8a' +
    '703eb5664803f60e613557b986c11d9e' +
    'e1f8981169d98e949b1e87e9ce5528df' +
    '8ca1890dbfe6426841992d0fb054bb16')
    .match(/../g).map((value) => parseInt(value, 16));

function savefilmAesSubWord(word) {
  return (SAVEFILM_AES_SBOX[(word >>> 24) & 0xff] << 24) |
    (SAVEFILM_AES_SBOX[(word >>> 16) & 0xff] << 16) |
    (SAVEFILM_AES_SBOX[(word >>> 8) & 0xff] << 8) |
    SAVEFILM_AES_SBOX[word & 0xff];
}

function savefilmAesSchedule(key) {
  const words = new Array(60);
  for (let index = 0; index < 8; index += 1) {
    const offset = index * 4;
    words[index] = ((key[offset] << 24) | (key[offset + 1] << 16) |
      (key[offset + 2] << 8) | key[offset + 3]) >>> 0;
  }
  let rcon = 1;
  for (let index = 8; index < words.length; index += 1) {
    let previous = words[index - 1];
    if (index % 8 === 0) {
      previous = savefilmAesSubWord((previous << 8) | (previous >>> 24)) ^ (rcon << 24);
      rcon = (rcon << 1) ^ (rcon & 0x80 ? 0x11b : 0);
    } else if (index % 8 === 4) {
      previous = savefilmAesSubWord(previous);
    }
    words[index] = (words[index - 8] ^ previous) >>> 0;
  }
  return words;
}

function savefilmAesEncryptBlock(input, schedule) {
  const state = input.slice();
  const addRoundKey = (round) => {
    for (let column = 0; column < 4; column += 1) {
      const word = schedule[round * 4 + column];
      const offset = column * 4;
      state[offset] ^= word >>> 24;
      state[offset + 1] ^= (word >>> 16) & 0xff;
      state[offset + 2] ^= (word >>> 8) & 0xff;
      state[offset + 3] ^= word & 0xff;
    }
  };
  const subBytes = () => {
    for (let index = 0; index < 16; index += 1) state[index] = SAVEFILM_AES_SBOX[state[index]];
  };
  const shiftRows = () => {
    const copy = state.slice();
    for (let row = 0; row < 4; row += 1) {
      for (let column = 0; column < 4; column += 1) {
        state[column * 4 + row] = copy[((column + row) % 4) * 4 + row];
      }
    }
  };
  const mixColumns = () => {
    for (let column = 0; column < 4; column += 1) {
      const offset = column * 4;
      const a0 = state[offset];
      const a1 = state[offset + 1];
      const a2 = state[offset + 2];
      const a3 = state[offset + 3];
      const xtime = (value) => ((value << 1) ^ ((value & 0x80) ? 0x1b : 0)) & 0xff;
      state[offset] = xtime(a0) ^ (xtime(a1) ^ a1) ^ a2 ^ a3;
      state[offset + 1] = a0 ^ xtime(a1) ^ (xtime(a2) ^ a2) ^ a3;
      state[offset + 2] = a0 ^ a1 ^ xtime(a2) ^ (xtime(a3) ^ a3);
      state[offset + 3] = (xtime(a0) ^ a0) ^ a1 ^ a2 ^ xtime(a3);
    }
  };
  addRoundKey(0);
  for (let round = 1; round <= 14; round += 1) {
    subBytes();
    shiftRows();
    if (round !== 14) mixColumns();
    addRoundKey(round);
  }
  return state;
}

function savefilmAesCtrTransform(input, key, iv) {
  const schedule = savefilmAesSchedule(key);
  const counter = iv.slice(0, 16);
  const output = [];
  for (let offset = 0; offset < input.length; offset += 16) {
    const stream = savefilmAesEncryptBlock(counter, schedule);
    const length = Math.min(16, input.length - offset);
    for (let index = 0; index < length; index += 1) {
      output.push(input[offset + index] ^ stream[index]);
    }
    for (let index = 15; index >= 0; index -= 1) {
      counter[index] = (counter[index] + 1) & 0xff;
      if (counter[index] !== 0) break;
    }
  }
  return output;
}

function savefilmAesCtrDecrypt(value, seed) {
  const key = [...savefilmMd5Hex(seed)].map((char) => char.charCodeAt(0));
  const encrypted = [...String(value)].map((char) => char.charCodeAt(0) & 0xff);
  const plain = savefilmAesCtrTransform(encrypted, key, key);
  const hex = plain.map((byte) => byte.toString(16).padStart(2, '0')).join('');
  return host.codec.base64ToText(host.codec.hexToBase64(hex));
}

function savefilmUtf8Bytes(value) {
  const hex = host.codec.base64ToHex(host.codec.textToBase64(String(value)));
  const bytes = [];
  for (let index = 0; index < hex.length; index += 2) {
    bytes.push(parseInt(hex.slice(index, index + 2), 16));
  }
  return bytes;
}

function savefilmAsciiBytes(value) {
  return [...String(value)].map((char) => char.charCodeAt(0) & 0xff);
}

function savefilmAbyssDoubleBase64(bytes) {
  const hex = bytes.map((byte) => (Number(byte) & 0xff).toString(16).padStart(2, '0')).join('');
  const first = host.codec.hexToBase64(hex).replace(/=+$/g, '');
  return host.codec.textToBase64(first).replace(/=+$/g, '');
}

// CloudStream's AbyssplayerExtractor rebuilds the final `/sora` URL from the
// encrypted path. The rendition's `path` field is only the browser player's
// storage hint and is not directly playable by native clients.
function savefilmAbyssPathToken(path, size) {
  const sizeInput = [...String(size)].map((char) => char.charCodeAt(0) - 48);
  const digest = savefilmMd5HexBytes(sizeInput);
  const key = savefilmAsciiBytes(digest);
  const encrypted = savefilmAesCtrTransform(savefilmUtf8Bytes(path), key, key);
  return savefilmAbyssDoubleBase64(encrypted);
}

function savefilmBase64Binary(value) {
  const hex = host.codec.base64ToHex(value);
  let result = '';
  for (let index = 0; index < hex.length; index += 2) {
    result += String.fromCharCode(parseInt(hex.slice(index, index + 2), 16));
  }
  return result;
}

function savefilmAbyssQualityHeight(entry) {
  if (!entry || typeof entry !== 'object') return null;
  const value = entry.height || entry.quality || entry.type ||
    entry.label || entry.name || '';
  const match = /(?:^|[^0-9])(2160|1440|1080|720|480|360)\s*p?(?:[^0-9]|$)/i
    .exec(String(value));
  return match == null ? null : Number(match[1]);
}

function savefilmAbyssGeneratedUrl(entry, payload, media) {
  if (!entry || !payload || payload.md5_id == null || payload.slug == null ||
      entry.res_id == null || entry.size == null || typeof entry.sub !== 'string') {
    return null;
  }
  const domains = media && media.mp4 && media.mp4.domains;
  if (!Array.isArray(domains)) return null;
  const domain = domains.find((value) => String(value || '').includes(entry.sub));
  if (!domain) return null;
  const path = `/mp4/${payload.md5_id}/${entry.res_id}/${entry.size}?v=${payload.slug}`;
  const token = savefilmAbyssPathToken(path, entry.size);
  const host = String(domain).replace(/^https?:\/\//i, '').replace(/\/+$/, '');
  return /^[-a-z0-9.]+(?::\d+)?$/i.test(host)
    ? `https://${host}/sora/${entry.size}/${token}`
    : null;
}

function savefilmAbyssMediaUrls(html) {
  const match = /\b(?:const|let|var)\s+datas\s*=\s*["']([^"']+)["']/i.exec(html || '');
  if (!match) return [];
  try {
    const payload = JSON.parse(savefilmBase64Binary(match[1]));
    if (typeof payload.media !== 'string' || payload.slug == null || payload.md5_id == null || payload.user_id == null) return [];
    const media = JSON.parse(savefilmAesCtrDecrypt(
      payload.media,
      `${payload.user_id}:${payload.slug}:${payload.md5_id}`,
    ));
    const values = [];
    const generated = (Array.isArray(media.mp4?.sources)
      ? media.mp4.sources : [])
      .map((entry) => {
        if (String(entry && entry.codec || '').toLowerCase() === 'av1') return null;
        const url = savefilmAbyssGeneratedUrl(entry, payload, media);
        if (!url) return null;
        const height = savefilmAbyssQualityHeight(entry);
        return {
          id: height == null ? `mirror-${entry.res_id}` : `quality-${height}p`,
          url,
          format: 'mp4',
          label: String(entry.label || entry.quality ||
            (height == null ? `Mirror ${entry.res_id}` : `${height}p`)),
          ...(height == null ? {} : { height }),
        };
      })
      .filter((entry) => entry != null)
      .sort((left, right) => (left.height || Number.MAX_SAFE_INTEGER) -
        (right.height || Number.MAX_SAFE_INTEGER));
    if (generated.length > 0) {
      values.push({
        url: generated[0].url,
        format: 'mp4',
        label: 'Abyss',
        resolver: 'abyss',
        variants: generated,
      });
    }
    const add = (entry, format) => {
      const url = entry && typeof entry.url === 'string' ? entry.url.trim() : '';
      // Abyss `.fd` URLs are only the first chunk for its browser service
      // worker. They are not files that AVFoundation/ExoPlayer can open.
      if (format === 'mp4' && /\.fd(?:[?#]|$)/i.test(url)) return;
      if (!/^https?:\/\/[^\s]+$/i.test(url) || values.some((value) => value.url === url)) return;
      values.push({ url, format });
    };
    for (const entry of media.mp4?.fristDatas || []) add(entry, 'mp4');
    for (const entry of media.hls?.fristDatas || []) add(entry, 'hls');
    return values;
  } catch (_) {
    return [];
  }
}

// Several Savefilm players put the media URL in a Dean Edwards
// P.A.C.K.E.R.-wrapped JWPlayer configuration. Decode only the substitution
// table; never evaluate the upstream script.
function savefilmUnpack(script) {
  const packed = /}\(\s*'((?:\\.|[^'])*)'\s*,\s*(\d+)\s*,\s*\d+\s*,\s*'((?:\\.|[^'])*)'\.split\('\|'\)/i.exec(script || '');
  if (packed == null) return String(script || '');
  const payload = packed[1].replace(/\\'/g, "'").replace(/\\\\/g, '\\');
  const radix = Number(packed[2]);
  const words = packed[3].replace(/\\'/g, "'").split('|');
  if (!Number.isInteger(radix) || radix < 2 || words.length === 0) return String(script || '');
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
  for (let index = words.length - 1; index >= 0; index -= 1) {
    if (!words[index]) continue;
    const escapedToken = token(index).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    unpacked = unpacked.replace(new RegExp(`\\b${escapedToken}\\b`, 'g'), words[index]);
  }
  return unpacked;
}

function savefilmMediaUrls(html, base) {
  const values = [];
  const add = (value) => {
    const url = savefilmUrl(value, base);
    if (!url || !/\.(?:m3u8|mp4)(?:[?#]|$)/i.test(url) || values.some((entry) => entry.url === url)) return;
    values.push({
      url,
      format: /\.m3u8(?:[?#]|$)/i.test(url) ? 'hls' : 'mp4',
    });
  };
  const scripts = [String(html || ''), savefilmUnpack(html)]
    .map((script) => String(script || '').replace(/\\\//g, '/'));
  scripts.forEach((script) => {
    const assigned = /(?:data-hash|urlPlay|file|source)\s*[:=]\s*["']([^"']+\.(?:m3u8|mp4)(?:[?#][^"']*)?)/gi;
    let match;
    while ((match = assigned.exec(script)) != null) add(match[1]);
    // CloudX's Dingtezuni extractor accepts any quoted value containing a
    // media extension from a `links`/`sources` object, not only `file` or
    // `source` assignments. Restrict this fallback to URL-like values so a
    // page title ending in `.mp4` is never exposed as a stream.
    const cloudX = /:\s*["']((?:https?:\/\/|\/\/|\/)[^"']+\.(?:m3u8|mp4)(?:[?#][^"']*)?)["']/gi;
    while ((match = cloudX.exec(script)) != null) add(match[1]);
    const general = /(?:https?:\/\/|\/)[^"'\\\s<>]+\.(?:m3u8|mp4)(?:[?#][^"'\\\s<>]*)?/gi;
    while ((match = general.exec(script)) != null) add(match[0]);
  });
  return values;
}

// AceFile's default mirror is a public Google Drive object. Its page keeps
// the Drive file id and API key inside the same small P.A.C.K.E.R. script
// used to select the mirror. Build the media endpoint without evaluating the
// upstream script or relying on its iframe/service-worker logic.
function savefilmAcefileMediaUrls(html) {
  const script = savefilmUnpack(html).replace(/\\\//g, '/');
  const mirror = /var\s+DUAR\s*=\s*\[\s*\{[^}]*["']?\bcode["']?\s*:\s*["']([^"']+)["']/i.exec(script);
  const encodedQuery = /atob\(\s*["']([^"']+)["']\s*\)\s*\+\s*atob\(\s*DUAR\.code\s*\)\s*\+\s*atob\(\s*["']([^"']+)["']\s*\)/i.exec(script);
  if (!mirror || !encodedQuery) return [];
  try {
    const fileId = host.codec.base64ToText(mirror[1]).trim();
    const prefix = host.codec.base64ToText(encodedQuery[1]);
    const suffix = host.codec.base64ToText(encodedQuery[2]);
    if (!/^https:\/\/www\.googleapis\.com\/drive\/v3\/files\/$/i.test(prefix) ||
        !/^[A-Za-z0-9_-]{10,}$/.test(fileId) || !/^\?alt=json&fields=/i.test(suffix)) {
      return [];
    }
    const key = /(?:^|&)key=([^&]+)/i.exec(suffix)?.[1];
    if (!key) return [];
    return [{
      url: `${prefix}${fileId}?alt=media&key=${key}`,
      format: 'mp4',
    }];
  } catch (_) {
    return [];
  }
}

async function savefilmPlayerStreams(detailUrl) {
  const detail = await savefilmGet(detailUrl, `${savefilmBase || SAVEFILM_DEFAULT_BASE}/`);
  if (detail == null) return [];
  const playerPages = savefilmPlayerPageUrls(detail.body, detailUrl, savefilmBase);
  const streams = [];
  for (const pageUrl of playerPages) {
    const page = pageUrl === detailUrl ? detail : await savefilmGet(pageUrl, detailUrl);
    if (page == null) continue;
    for (const iframeUrl of savefilmIframeUrls(page.body, pageUrl)) {
      let media = savefilmMediaUrls(iframeUrl, pageUrl);
      if (media.length === 0) {
        const iframe = await savefilmPlayerResponse(iframeUrl, pageUrl);
        media = iframe == null ? [] : [
          ...savefilmMediaUrls(iframe.response.body, iframe.url),
          ...savefilmAbyssMediaUrls(iframe.response.body),
          ...savefilmAcefileMediaUrls(iframe.response.body),
        ];
      }
      for (const entry of media) {
        if (streams.some((stream) => stream.url === entry.url)) continue;
        streams.push({
          ...entry,
          referer: iframeUrl,
          ...(entry.resolver === 'abyss'
            ? { resolverUrl: iframeUrl, resolverReferer: pageUrl }
            : {}),
        });
      }
    }
  }
  return streams;
}

async function savefilmSources(args) {
  const enabled = args && args.enabledProviders;
  if (enabled != null && enabled.indexOf(SAVEFILM_PROVIDER_ID) === -1) return { sources: [] };
  const item = args && args.item;
  if (!item || (item.kind !== 'video' && item.kind !== 'episode')) return { sources: [] };
  const payload = savefilmRefPayload(item.ref);
  const query = savefilmItemQuery(item);
  const base = await savefilmActiveBase();
  let watchUrl = payload && typeof payload.u === 'string'
    ? payload.u : savefilmItemDetailUrl(item);
  if (!watchUrl) {
    if (!query.title || (query.isEpisode && !Number.isInteger(query.episode))) return { sources: [] };
    const titleVariants = await savefilmItemTitleVariants(item, query.title);
    let found = null;
    for (const title of titleVariants) {
      found = await savefilmFindResult(title, base);
      if (found != null) break;
    }
    if (found == null) return { sources: [] };
    watchUrl = found.result.url;
    if (query.isEpisode) {
      const detail = await savefilmGet(watchUrl, `${base}/`);
      if (detail == null) return { sources: [] };
      watchUrl = savefilmEpisodeUrl(detail.body, query.season || 1, query.episode, base);
      if (!watchUrl) return { sources: [] };
    }
  } else if (query.isEpisode && payload.e != null && Number(payload.e) !== query.episode) {
    return { sources: [] };
  }
  const streams = await savefilmPlayerStreams(watchUrl);
  return {
    sources: streams.map((stream, index) => ({
      id: `${SAVEFILM_PROVIDER_KEY}:${savefilmEncode(stream.resolverUrl
        ? { a: stream.resolverUrl, r: stream.resolverReferer }
        : { u: stream.url, r: stream.referer })}`,
      label: stream.label
        ? `Savefilm · ${stream.label}`
        : `Savefilm · ${stream.format === 'hls' ? 'HLS' : 'MP4'} ${index + 1}`,
      provider: 'Nimora',
      providerId: SAVEFILM_PROVIDER_ID,
    })),
  };
}

function savefilmResolvedStream(stream, referer) {
  const headers = {
    Referer: referer || `${savefilmBase || SAVEFILM_DEFAULT_BASE}/`,
    'User-Agent': SAVEFILM_UA,
  };
  const variants = (Array.isArray(stream.variants) ? stream.variants : [])
    .map((variant, index) => ({
      id: variant.id || `mirror-${index + 1}`,
      url: variant.url,
      format: variant.format === 'hls' ? 'hls' : 'other',
      headers,
      label: variant.label || `Mirror ${index + 1}`,
      ...(Number.isInteger(variant.height) ? { height: variant.height } : {}),
    }));
  return {
    url: stream.url,
    // The shared stream protocol has hls/dash/other, not mp4. Native
    // players still recognize a genuine MP4 by its response MIME type.
    format: stream.format === 'hls' ? 'hls' : 'other',
    headers,
    ...(variants.length === 0 ? {} : { variants }),
  };
}

async function savefilmResolveSource(sourceId) {
  const prefix = `${SAVEFILM_PROVIDER_KEY}:`;
  if (typeof sourceId !== 'string' || !sourceId.startsWith(prefix)) throw new Error('Invalid Savefilm source id');
  const payload = savefilmDecode(sourceId.slice(prefix.length));
  const isAbyss = typeof payload?.a === 'string' &&
    /^https?:\/\/[^\s]+$/i.test(payload.a);
  if (isAbyss) {
    const iframe = await savefilmPlayerResponse(payload.a, payload.r);
    const stream = iframe == null
      ? null
      : savefilmAbyssMediaUrls(iframe.response.body)
        .find((entry) => entry.resolver === 'abyss');
    if (stream == null) throw new Error('Savefilm Abyss player has no playable media');
    return savefilmResolvedStream(stream, iframe.url);
  }
  const isFile = typeof payload?.u === 'string' &&
    /^https?:\/\/[^\s]+\.(?:m3u8|mp4)(?:[?#].*)?$/i.test(payload.u);
  const isAcefile = typeof payload?.u === 'string' &&
    /^https:\/\/www\.googleapis\.com\/drive\/v3\/files\/[A-Za-z0-9_-]{10,}\?alt=media&key=[^\s&]+$/i.test(payload.u);
  if (!payload || typeof payload.u !== 'string' || (!isFile && !isAcefile)) {
    throw new Error('Malformed Savefilm source id');
  }
  return savefilmResolvedStream({
    url: payload.u,
    format: /\.m3u8(?:[?#]|$)/i.test(payload.u) ? 'hls' : 'mp4',
  }, payload.r);
}

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: SAVEFILM_PROVIDER_KEY,
  sources: savefilmSources,
  resolve: (sourceId) => savefilmResolveSource(sourceId),
});

globalThis.__catalogProviders = globalThis.__catalogProviders || [];
globalThis.__catalogProviders.push({
  catalogId: SAVEFILM_NSFW_CATALOG_ID,
  catalog: savefilmNsfwCatalog,
});
