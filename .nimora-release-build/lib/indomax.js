// Indomax VOD streams.  Indomax is a WordPress catalogue whose active domain
// is published in CloudX's Website.json.  Its player pages hand off to
// ImaxStreams; this file owns both the discovery path and that extractor.

const INDOMAX_DEFAULT_BASE = 'https://idmxl.ink';
const INDOMAX_CATALOG_FALLBACK_BASES = Array.from(
  { length: 10 },
  (_, index) => `https://akses${index + 1}.indomax21.xyz`,
);
const INDOMAX_DIRECTORY =
  globalThis.__indomaxDirectoryUrl ||
  'https://raw.githubusercontent.com/Asm0d3usX/CloudX/builds/Website.json';
const INDOMAX_PROVIDER_KEY = 'indomax';
const INDOMAX_PROVIDER_ID = 'nimora.indomax';
const INDOMAX_FIRE_BASE =
  globalThis.__indomaxFireBaseUrl || 'https://embedpyrox.xyz';
const INDOMAX_NSFW_CATALOG_ID = 'nsfw';
const INDOMAX_NSFW_SUBCATEGORIES = [
  { id: 'jav', name: 'JAV' },
  { id: 'asia-m', name: 'Asia M' },
  { id: 'vivamax', name: 'Vivamax' },
  { id: 'kelas-bintang', name: 'Kelas Bintang' },
  { id: 'hentai', name: 'Hentai' },
  { id: 'semi-barat', name: 'Semi Barat' },
  { id: 'bokep-indo', name: 'Bokep Indo' },
  { id: 'bokep-vietnam', name: 'Bokep Vietnam' },
];
const IMAX_BASE = globalThis.__imaxStreamsBaseUrl || 'https://imaxstreams.net';
const INDOMAX_UA =
  'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/137.0.0.0 Mobile Safari/537.36';

let indomaxBase = globalThis.__indomaxBaseUrl || null;

function indomaxHeaders(referer) {
  return {
    Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    Referer: referer || `${indomaxBase || INDOMAX_DEFAULT_BASE}/`,
    'User-Agent': INDOMAX_UA,
  };
}

function imaxHeaders(base) {
  const playerBase = base || IMAX_BASE;
  return {
    'Sec-Fetch-Dest': 'empty',
    'Sec-Fetch-Mode': 'cors',
    'Sec-Fetch-Site': 'cross-site',
    Origin: playerBase,
    Referer: `${playerBase}/`,
    'User-Agent': INDOMAX_UA,
  };
}

function indomaxUrl(path, base) {
  if (typeof path !== 'string' || !path) return null;
  if (/^https?:\/\//i.test(path)) return path;
  const root = (base || indomaxBase || INDOMAX_DEFAULT_BASE).replace(/\/$/, '');
  return path.startsWith('/') ? `${root}${path}` : `${root}/${path}`;
}

function indomaxText(value) {
  const namedEntities = {
    amp: '&',
    apos: "'",
    gt: '>',
    hellip: '…',
    lt: '<',
    mdash: '—',
    nbsp: ' ',
    ndash: '–',
    quot: '"',
  };
  return String(value || '')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&#(x[0-9a-f]+|[0-9]+);?/gi, (match, value) => {
      const codePoint = value[0].toLowerCase() === 'x'
        ? parseInt(value.slice(1), 16)
        : parseInt(value, 10);
      return Number.isInteger(codePoint) && codePoint >= 0 && codePoint <= 0x10ffff
        ? String.fromCodePoint(codePoint)
        : match;
    })
    .replace(/&([a-z]+);/gi, (match, name) => {
      const decoded = namedEntities[name.toLowerCase()];
      return decoded == null ? match : decoded;
    })
    .replace(/\s+/g, ' ')
    .trim();
}

function indomaxNormalize(value) {
  return indomaxText(value)
    // Search results commonly append the release year, while AniList gives
    // the bare anime title. Treat that year as metadata so a movie such as
    // "One Piece Heroine (2026)" cannot outrank the actual series
    // "One Piece (1999)".
    .replace(/\s*[([]?\s*(?:19|20)\d{2}\s*[)\]]?\s*$/i, '')
    .replace(/\s*(subtitle\s+indonesia|indo)\s*$/i, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .toLowerCase();
}

function indomaxAttribute(attributes, name) {
  const match = new RegExp(`${name}\\s*=\\s*["']([^"']+)["']`, 'i')
    .exec(attributes || '');
  return match == null ? null : match[1];
}

function indomaxMetaContent(html, name) {
  const tag = new RegExp(
    `<meta\\b[^>]*(?:name|property)\\s*=\\s*["']${name}["'][^>]*>`,
    'i',
  ).exec(html || '');
  return tag == null ? null : indomaxAttribute(tag[0], 'content');
}

function indomaxDivBlocks(html, classPattern) {
  const blocks = [];
  const stack = [];
  const tags = /<div\b([^>]*)>|<\/div\s*>/gi;
  let match;
  while ((match = tags.exec(html || '')) != null) {
    if (match[1] != null) {
      stack.push({
        start: tags.lastIndex,
        matched: classPattern.test(indomaxAttribute(match[1], 'class') || ''),
      });
      continue;
    }
    const block = stack.pop();
    if (block != null && block.matched) {
      blocks.push((html || '').slice(block.start, match.index));
    }
  }
  return blocks;
}

function indomaxMetaRows(html) {
  return indomaxDivBlocks(html, /\bgmr-moviedata\b/i)
    .map((row) => ({ html: row, text: indomaxText(row) }));
}

function indomaxMetaRow(html, pattern) {
  return indomaxMetaRows(html).find((row) => pattern.test(row.text)) || null;
}

function indomaxRowLinks(row) {
  if (row == null) return [];
  const values = [];
  const links = /<a\b[^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = links.exec(row.html || '')) != null) {
    const value = indomaxText(match[1]);
    if (value) values.push(value);
  }
  return values.filter((value, index) => values.indexOf(value) === index);
}

function indomaxDetailDescription(html) {
  const block = /<div\b[^>]*\bitemprop\s*=\s*["']description["'][^>]*>([\s\S]*?)<\/div>/i.exec(html || '');
  if (block != null) {
    const paragraph = /<p\b[^>]*>([\s\S]*?)<\/p>/i.exec(block[1]);
    const value = indomaxText(paragraph == null ? block[1] : paragraph[1]);
    if (value) return value;
  }
  const description = indomaxMetaContent(html, 'description');
  return description ? indomaxText(description) : null;
}

function indomaxDetailRating(html) {
  const bar = /<div\b[^>]*\bgmr-rating-bar\b[^>]*>([\s\S]*?)<\/div>/i.exec(html || '');
  const width = bar == null
    ? null
    : /style\s*=\s*["'][^"']*width\s*:\s*([0-9.]+)%/i.exec(bar[1]);
  if (width != null) {
    const value = Number(width[1]) / 10;
    if (Number.isFinite(value)) return value;
  }
  const ratingMatch = /itemprop\s*=\s*["']ratingValue["'][^>]*content\s*=\s*["']([^"']+)/i.exec(html || '')
    || /gmr-rating-item\b[^>]*>([\s\S]*?)<\/div>/i.exec(html || '');
  if (ratingMatch == null) return null;
  const value = Number(/\d+(?:\.\d+)?/.exec(indomaxText(ratingMatch[1]))?.[0]);
  return Number.isFinite(value) ? value : null;
}

function indomaxDetailActors(html) {
  const actors = [];
  const blocks = /<span\b[^>]*\bitemprop\s*=\s*["']actors?["'][^>]*>([\s\S]*?)<\/span>/gi;
  let block;
  while ((block = blocks.exec(html || '')) != null) {
    const links = /<a\b[^>]*>([\s\S]*?)<\/a>/gi;
    let link;
    while ((link = links.exec(block[1])) != null) {
      const name = indomaxText(link[1]);
      if (name) actors.push(name);
    }
  }
  return actors.filter((name, index) => actors.indexOf(name) === index);
}

function indomaxDetailTrailer(html) {
  const match = /<a\b([^>]*\bgmr-trailer-popup\b[^>]*)>/i.exec(html || '');
  const url = match == null ? null : indomaxUrl(indomaxAttribute(match[1], 'href'));
  if (!url) return null;
  const site = /(?:youtube\.com|youtu\.be)/i.test(url) ? 'YouTube' : null;
  return { title: 'Trailer', url, ...(site ? { site } : {}) };
}

async function indomaxTmdbRecommendations(title, detailUrl) {
  if (typeof tmdbSearchType !== 'function' || typeof tmdbRecommendationsOf !== 'function') return [];
  const mediaType = /\/tv\//i.test(detailUrl) ? 'tv' : 'movie';
  const extraParams = mediaType === 'movie' ? { region: 'US' } : {};
  const searchResults = await tmdbSearchType(mediaType, title, 1, extraParams);
  const wanted = indomaxNormalize(title);
  const matches = searchResults
    .map((entry, index) => {
      const result = entry && entry.result;
      const candidate = indomaxNormalize(result && (result.title || result.name));
      if (!result || result.id == null || !candidate) return null;
      const exact = candidate === wanted;
      const overlap = candidate.includes(wanted) || wanted.includes(candidate);
      if (!exact && !overlap) return null;
      return {
        id: result.id,
        score: (exact ? 0 : 10) - Number(result.popularity || 0) / 100000 + index / 1000000,
      };
    })
    .filter((entry) => entry != null)
    .sort((a, b) => a.score - b.score);
  if (matches.length === 0) return [];
  return tmdbRecommendationsOf(String(matches[0].id), mediaType);
}

function indomaxSeasonNumber(value) {
  const text = indomaxText(value);
  const compact = /\bs(\d{1,2})e\d+\b/i.exec(text);
  if (compact != null) return Number(compact[1]);
  const named = /\b(?:season|musim)\s*[-_: ]*([0-9]{1,2})\b/i.exec(text);
  return named == null ? null : Number(named[1]);
}

function indomaxEpisodeNumber(value) {
  const text = indomaxText(value);
  const compact = /\bs\d{1,2}e(\d+)\b/i.exec(text);
  if (compact != null) return Number(compact[1]);
  const named = /\bepisode\s*(\d+)\b/i.exec(text);
  if (named != null) return Number(named[1]);
  const short = /\be\s*(\d+)\b/i.exec(text);
  if (short != null) return Number(short[1]);
  const last = /(?:^|\D)(\d+)(?:\D|$)/.exec(text);
  return last == null ? null : Number(last[1]);
}

function indomaxEpisodeRef(parentRef, url, position, season) {
  return {
    extensionId: parentRef.extensionId,
    providerId: parentRef.providerId,
    id: `${INDOMAX_PROVIDER_KEY}:episode:${encodeIndomaxSource({
      u: url,
      p: parentRef.id,
      e: position,
      s: season,
    })}`,
  };
}

function indomaxDetailEpisodeGroups(html, parentRef, poster, base) {
  const groups = new Map();
  const containers = indomaxDivBlocks(html, /\b(?:vid-episodes|gmr-listseries)\b/i);
  containers.forEach((container, containerIndex) => {
    const containerSeason = indomaxSeasonNumber(container) || containerIndex + 1;
    const groupId = `season:${containerSeason}`;
    const group = groups.get(groupId) || {
      id: groupId,
      title: `Season ${containerSeason}`,
      episodes: [],
    };
    const links = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
    let link;
    while ((link = links.exec(container)) != null) {
      const url = indomaxUrl(indomaxAttribute(link[1], 'href'), base);
      if (!url) continue;
      const rawTitle = indomaxAttribute(link[1], 'title') || indomaxText(link[2]);
      const cleanTitle = indomaxText(rawTitle).replace(/^Permalink ke\s*/i, '').trim();
      const season = indomaxSeasonNumber(cleanTitle) || containerSeason;
      const position = indomaxEpisodeNumber(cleanTitle);
      if (!Number.isInteger(position) || position < 1) continue;
      const episodeGroupId = `season:${season}`;
      const episodeGroup = groups.get(episodeGroupId) || {
        id: episodeGroupId,
        title: `Season ${season}`,
        episodes: [],
      };
      episodeGroup.episodes.push({
        ref: indomaxEpisodeRef(parentRef, url, position, season),
        title: `Episode ${position}`,
        position,
        ...(poster ? { artwork: { portrait: { url: poster } } } : {}),
      });
      groups.set(episodeGroupId, episodeGroup);
    }
    if (!groups.has(groupId)) groups.set(groupId, group);
  });
  return [...groups.values()]
    .map((group) => ({
      ...group,
      episodes: group.episodes
        .filter((episode, index, entries) => entries.findIndex((other) => other.ref.id === episode.ref.id) === index)
        .sort((a, b) => a.position - b.position),
    }))
    .filter((group) => group.episodes.length > 0)
    .sort((a, b) => Number(a.id.split(':')[1]) - Number(b.id.split(':')[1]));
}

async function indomaxGet(url, referer) {
  try {
    const response = await fetch(url, { headers: indomaxHeaders(referer) });
    if (response.status < 200 || response.status >= 300) return null;
    if (typeof response.url === 'string') {
      const finalBase = /^(https?:\/\/[^/]+)/i.exec(response.url)?.[1];
      if (finalBase) indomaxBase = finalBase;
    }
    return response;
  } catch (_) {
    return null;
  }
}

async function indomaxActiveBase() {
  if (indomaxBase) return indomaxBase;
  const response = await indomaxGet(INDOMAX_DIRECTORY, INDOMAX_DEFAULT_BASE);
  if (response != null) {
    try {
      const urls = JSON.parse(response.body).indomax;
      if (Array.isArray(urls) && typeof urls[0] === 'string' && /^https?:\/\//i.test(urls[0])) {
        indomaxBase = urls[0].replace(/\/$/, '');
      }
    } catch (_) {}
  }
  return indomaxBase || INDOMAX_DEFAULT_BASE;
}

function indomaxSearchResults(html, base) {
  const results = [];
  const article = /<article\b([^>]*\bclass\s*=\s*["'][^"']*\bitem-infinite\b[^"']*["'][^>]*)>([\s\S]*?)<\/article>/gi;
  let match;
  while ((match = article.exec(html || '')) != null) {
    const titleMatch = /<h2\b[^>]*\bentry-title\b[^>]*>[\s\S]*?<a\b([^>]*)>([\s\S]*?)<\/a>/i.exec(match[2]);
    if (titleMatch == null) continue;
    const url = indomaxUrl(indomaxAttribute(titleMatch[1], 'href'), base);
    const title = indomaxText(titleMatch[2]);
    const imageMatch = /<img\b([^>]*)>/i.exec(match[2]);
    const poster = imageMatch == null
      ? null
      : indomaxAttribute(imageMatch[1], 'src');
    const ratingMatch = /<div\b[^>]*\bgmr-rating-item\b[^>]*>([\s\S]*?)<\/div>/i.exec(match[2]);
    const ratingValue = ratingMatch == null
      ? null
      : Number(/\d+(?:\.\d+)?/.exec(indomaxText(ratingMatch[1]))?.[0]);
    if (url && title) {
      const season = indomaxSeasonNumber(title);
      const hasEpisodeLabel = /\b(?:s\d{1,2}e\d+|episode\s*\d+|eps?\s*\d+|e\s*\d+)\b/i.test(title);
      const episode = hasEpisodeLabel ? indomaxEpisodeNumber(title) : null;
      results.push({
        title,
        url,
        ...(Number.isInteger(season) ? { season } : {}),
        ...(Number.isInteger(episode) ? { episode } : {}),
        ...(poster ? { poster: indomaxUrl(poster, base) } : {}),
        ...(Number.isFinite(ratingValue) ? { rating: ratingValue } : {}),
      });
    }
  }
  return results;
}

function indomaxNsfwCategory(categoryId) {
  return INDOMAX_NSFW_SUBCATEGORIES.find((category) => category.id === categoryId)
    || INDOMAX_NSFW_SUBCATEGORIES[0];
}

function indomaxCategoryUrl(base, categoryId, page) {
  const path = `/category/${indomaxNsfwCategory(categoryId).id}/`;
  return page > 1 ? `${base}${path}page/${page}/` : `${base}${path}`;
}

function indomaxHasNextPage(html) {
  return /<a\b[^>]*\bclass\s*=\s*["'][^"']*\bnext\b[^"']*["'][^>]*>/i.test(html || '');
}

function indomaxCatalogItem(result, categoryId) {
  const item = {
    ref: {
      extensionId: 'nimora',
      providerId: INDOMAX_PROVIDER_ID,
      id: `${INDOMAX_PROVIDER_KEY}:catalog:${encodeIndomaxSource({
        u: result.url,
        c: categoryId,
      })}`,
    },
    kind: /\/tv\//i.test(result.url) ? 'series' : 'video',
    title: result.title,
  };
  if (result.poster) item.artwork = { portrait: { url: result.poster } };
  if (Number.isFinite(result.rating)) item.rating = result.rating;
  return item;
}

async function indomaxCategoryCatalog(query, categoryId, title, subCategories) {
  const base = await indomaxActiveBase();
  const selectedCategoryId = categoryId === INDOMAX_NSFW_CATALOG_ID
    ? indomaxNsfwCategory(query && query.subCategory).id
    : categoryId;
  const requestedPage = Number(query && query.page);
  const page = Number.isInteger(requestedPage) && requestedPage > 0 ? requestedPage : 1;
  const candidates = [
    base,
    ...INDOMAX_CATALOG_FALLBACK_BASES.filter((candidate) => candidate !== base),
  ];
  let response = null;
  let activeBase = base;
  for (const candidate of candidates) {
    const url = indomaxCategoryUrl(candidate, selectedCategoryId, page);
    response = await indomaxGet(url, `${candidate}/`);
    if (response != null) {
      activeBase = candidate;
      break;
    }
  }
  if (response == null) {
    return { sections: [], subCategories };
  }
  indomaxBase = activeBase;
  const results = indomaxSearchResults(response.body, activeBase);
  const result = {
    sections: [{
      id: selectedCategoryId,
      title,
      items: results.map((item) => indomaxCatalogItem(item, selectedCategoryId)),
    }],
    subCategories,
  };
  if (indomaxHasNextPage(response.body)) result.nextPage = String(page + 1);
  return result;
}

async function indomaxNsfwCatalog(query) {
  const requestedSubCategory = query && query.subCategory;
  if (typeof requestedSubCategory === 'string' && requestedSubCategory) {
    const category = indomaxNsfwCategory(requestedSubCategory);
    return indomaxCategoryCatalog(
      query,
      INDOMAX_NSFW_CATALOG_ID,
      category.name,
      INDOMAX_NSFW_SUBCATEGORIES,
    );
  }

  const request = query && typeof query === 'object' ? query : {};
  const pages = await Promise.all(
    INDOMAX_NSFW_SUBCATEGORIES.map((category) => indomaxCategoryCatalog(
      { ...request, subCategory: category.id },
      INDOMAX_NSFW_CATALOG_ID,
      category.name,
      [],
    )),
  );
  const sections = pages
    .flatMap((page) => Array.isArray(page.sections) ? page.sections : [])
    .filter((section) => Array.isArray(section.items) && section.items.length > 0);
  const result = {
    sections,
    subCategories: INDOMAX_NSFW_SUBCATEGORIES,
  };
  if (pages.some((page) => page.nextPage != null)) {
    result.nextPage = String(Number(request.page || 1) + 1);
  }
  return result;
}

function indomaxSearchItem(result) {
  const yearMatch = /^(.*?)(?:\s*\((\d{4})\))?$/.exec(result.title);
  const title = (yearMatch == null ? result.title : yearMatch[1]).trim();
  const year = yearMatch == null || yearMatch[2] == null ? null : Number(yearMatch[2]);
  return {
    ref: {
      extensionId: 'nimora',
      providerId: INDOMAX_PROVIDER_ID,
      id: `${INDOMAX_PROVIDER_KEY}:search:${encodeIndomaxSource({ u: result.url })}`,
    },
    kind: /\/tv\//i.test(result.url) ? 'series' : 'video',
    title: title || result.title,
    ...(Number.isInteger(year) ? { releaseYear: year } : {}),
  };
}

function indomaxRefPayload(ref) {
  const id = ref && typeof ref.id === 'string' ? ref.id : '';
  const prefix = `${INDOMAX_PROVIDER_KEY}:`;
  if (!id.startsWith(prefix)) return null;
  const encoded = id.slice(prefix.length).replace(/^(?:catalog|search|detail|episode):/, '');
  return decodeIndomaxSource(encoded);
}

function indomaxDetailItem(ref, html) {
  const titleMatch = /<h1\b[^>]*\bentry-title\b[^>]*>([\s\S]*?)<\/h1>/i.exec(html || '');
  const title = indomaxText(
    titleMatch == null
      ? indomaxMetaContent(html, 'og:title') || 'Indomax video'
      : titleMatch[1],
  ).replace(/\s+Subtitle Indonesia(?:\s*-\s*INDOMAX21)?$/i, '').trim();
  const image = indomaxMetaContent(html, 'og:image');
  const yearRow = indomaxMetaRow(html, /(?:^|\s)(?:tahun|release)\s*:/i);
  const yearMatch = yearRow == null ? null : /\b(\d{4})\b/.exec(yearRow.text);
  const year = yearMatch == null ? null : Number(yearMatch[1]);
  const rating = indomaxDetailRating(html);
  const item = {
    ref,
    kind: /\/tv\//i.test(indomaxRefPayload(ref)?.u || '') ? 'series' : 'video',
    title,
  };
  if (image) item.artwork = { portrait: { url: indomaxUrl(image) } };
  if (Number.isInteger(year)) item.releaseYear = year;
  if (Number.isFinite(rating)) item.rating = rating;
  return item;
}

async function indomaxMeta(args) {
  const ref = args && args.ref;
  const payload = indomaxRefPayload(ref);
  if (!payload || typeof payload.u !== 'string') {
    throw new Error('Malformed Indomax media ref');
  }
  const base = await indomaxActiveBase();
  const response = await indomaxGet(payload.u, `${base}/`);
  if (response == null) throw new Error('Indomax detail request failed');
  const detail = { item: indomaxDetailItem(ref, response.body) };
  const description = indomaxDetailDescription(response.body);
  if (description) detail.description = indomaxText(description);
  const genreRow = indomaxMetaRow(response.body, /(?:^|\s)genre\s*:/i);
  const tags = indomaxRowLinks(genreRow);
  if (tags.length > 0) detail.tags = tags;
  const yearRow = indomaxMetaRow(response.body, /(?:^|\s)(?:tahun|release)\s*:/i);
  const year = yearRow == null ? null : /\b(\d{4})\b/.exec(yearRow.text)?.[1];
  const durationRow = indomaxMetaRow(response.body, /(?:^|\s)(?:durasi|duration)\s*:/i);
  const duration = durationRow == null ? null : /\b(\d+)\s*(?:min|minutes?)?\b/i.exec(durationRow.text)?.[1];
  const facts = [];
  if (year) facts.push({ label: 'Year', value: year });
  if (duration) facts.push({ label: 'Duration', value: `${duration} min` });
  if (facts.length > 0) detail.facts = facts;
  const actors = indomaxDetailActors(response.body);
  if (actors.length > 0) detail.credits = actors.map((name) => ({ name, role: 'Actor' }));
  const trailer = indomaxDetailTrailer(response.body);
  if (trailer != null) detail.trailers = [trailer];
  const recommendations = await indomaxTmdbRecommendations(detail.item.title, payload.u);
  if (recommendations.length > 0) detail.recommendations = recommendations;
  if (/\/tv\//i.test(payload.u)) {
    const poster = detail.item.artwork?.portrait?.url || null;
    const groups = indomaxDetailEpisodeGroups(response.body, ref, poster, base);
    if (groups.length > 0) {
      const lastGroup = groups[groups.length - 1];
      const defaultEpisodeRef = lastGroup.episodes[lastGroup.episodes.length - 1].ref;
      detail.episodeGuide = {
        groups,
        defaultEpisodeRef,
      };
    }
  }
  return detail;
}

async function indomaxSearch(args) {
  const query = String(args && args.query || '').trim();
  if (!query) return { sections: [] };
  const base = await indomaxActiveBase();
  const searchUrl = `${base}/?s=${encodeURIComponent(query)}&post_type[]=post&post_type[]=tv`;
  const response = await indomaxGet(searchUrl, `${base}/`);
  if (response == null) return { sections: [] };
  const items = indomaxSearchResults(response.body, base).map(indomaxSearchItem);
  return { sections: [{ id: 'indomax-results', items }] };
}

function indomaxPickResult(results, title, isEpisode) {
  const wanted = indomaxNormalize(title);
  if (!wanted) return null;
  const scored = results.map((result, index) => {
    const candidate = indomaxNormalize(result.title);
    if (!candidate) return null;
    const exact = candidate === wanted;
    const overlap = candidate.includes(wanted) || wanted.includes(candidate);
    if (!exact && !overlap) return null;
    // An episode request needs a series page. A same-title movie or a title
    // that merely contains the anime name cannot expose the episode links
    // that the next resolver step requires.
    const seriesBias = isEpisode ? (/\/tv\//i.test(result.url) ? -5 : 5) : 0;
    return { result, score: (exact ? 0 : 10) + seriesBias + index / 1000 };
  }).filter((entry) => entry != null).sort((a, b) => a.score - b.score);
  return scored.length ? scored[0].result : null;
}

function indomaxSearchTitleVariants(title) {
  const original = String(title || '').trim();
  const withoutYear = original
    .replace(/[([]\s*(?:19|20)\d{2}\s*[)\]]/g, ' ')
    .replace(/\b(?:19|20)\d{2}\b/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return [original, withoutYear]
    .filter((value, index, values) => value && values.indexOf(value) === index);
}

async function indomaxItemTitleVariants(item, fallback) {
  if (typeof globalThis.__animeTitleVariants !== 'function') return [fallback];
  try {
    const variants = await globalThis.__animeTitleVariants(item);
    return Array.isArray(variants) && variants.length > 0 ? variants : [fallback];
  } catch (_) {
    return [fallback];
  }
}

async function indomaxFindResult(title, base, isEpisode) {
  for (const searchTitle of indomaxSearchTitleVariants(title)) {
    const searchUrl = `${base}/?s=${encodeURIComponent(searchTitle)}&post_type[]=post&post_type[]=tv`;
    const search = await indomaxGet(searchUrl, `${base}/`);
    if (search == null) continue;
    const results = indomaxSearchResults(search.body, base);
    const result = indomaxPickResult(results, searchTitle, isEpisode);
    if (result != null) return { result, results, searchUrl, searchTitle };
  }
  return null;
}

function indomaxItemQuery(item) {
  const extra = item && item.extra && typeof item.extra === 'object' ? item.extra : {};
  const episode = item && item.episode && typeof item.episode === 'object' ? item.episode : null;
  const group = episode && typeof episode.groupId === 'string' ? episode.groupId : '';
  const season = /(?:^|:)season:(\d+)/i.exec(group);
  return {
    title: String(extra.seriesTitle || (episode && item.subtitle) || (item && item.title) || '').trim(),
    episode: Number.isInteger(extra.episode) ? extra.episode : (episode && Number.isInteger(episode.position) ? episode.position : null),
    season: Number.isInteger(extra.season) ? extra.season : (season == null ? null : Number(season[1])),
    isEpisode: item && item.kind === 'episode',
  };
}

function indomaxSearchEpisodeUrl(results, title, season, episode) {
  if (!Number.isInteger(season) || !Number.isInteger(episode)) return null;
  const wanted = indomaxNormalize(title);
  const candidates = results
    .filter((result) => result.season != null && result.episode != null)
    .filter((result) => {
      const candidate = indomaxNormalize(result.title);
      return candidate.includes(wanted) || wanted.includes(candidate);
    });
  const exact = candidates.find(
    (result) => result.season === season && result.episode === episode,
  );
  if (exact != null) return exact.url;

  // When a provider starts a new season/cour, its episode number often resets
  // while TMDB continues the season. Infer that transition from the nearest
  // known episode on each side instead of baking a provider-specific offset.
  const previous = candidates
    .filter((result) => result.season === season && result.episode < episode)
    .sort((a, b) => b.episode - a.episode)[0];
  if (previous == null) return null;
  const providerEpisode = episode - previous.episode;
  const next = candidates.find(
    (result) => result.season > season && result.episode === providerEpisode,
  );
  if (next != null) return next.url;

  // If the desired episode is newer than the search page, retain the same
  // provider URL shape as the first episode of the new group and let the
  // normal HTTP check decide whether that episode is published.
  const groupStart = candidates.find(
    (result) => result.season > season && result.episode === 1,
  );
  if (groupStart == null) return null;
  return groupStart.url.replace(
    new RegExp(`(episode[-_]?)${groupStart.episode}(?=[/?#]|$)`, 'i'),
    (_, prefix) => `${prefix}${providerEpisode}`,
  );
}

function indomaxEpisodeUrl(html, wanted, base, season) {
  if (!Number.isInteger(wanted) || wanted < 1) return null;
  const containers = indomaxDivBlocks(html, /\b(?:vid-episodes|gmr-listseries)\b/i);
  if (containers.length > 0) {
    for (const [containerIndex, container] of containers.entries()) {
      const containerSeason = indomaxSeasonNumber(container) || containerIndex + 1;
      if (Number.isInteger(season) && containerSeason !== season) continue;
      const links = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
      let match;
      while ((match = links.exec(container)) != null) {
        const href = indomaxAttribute(match[1], 'href');
        if (!href) continue;
        const label = `${indomaxAttribute(match[1], 'title') || ''} ${indomaxText(match[2])}`;
        const number = /episode\s*(\d+)/i.exec(label) || /(?:^|\D)(\d+)(?:\D|$)/.exec(label);
        if (number != null && Number(number[1]) === wanted) return indomaxUrl(href, base);
      }
    }
    // Do not fall through to another season when the detail page exposes
    // explicit episode groups but the requested season is unavailable.
    return null;
  }
  const links = /<a\b([^>]*)>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = links.exec(html || '')) != null) {
    const href = indomaxAttribute(match[1], 'href');
    if (!href) continue;
    const label = `${indomaxAttribute(match[1], 'title') || ''} ${indomaxText(match[2])}`;
    const number = /episode\s*(\d+)/i.exec(label) || /(?:^|\D)(\d+)(?:\D|$)/.exec(label);
    if (number != null && Number(number[1]) === wanted) return indomaxUrl(href, base);
  }
  return null;
}

function indomaxImaxSourceUrl(value, base) {
  const url = indomaxUrl(value, base);
  if (!url) return null;
  if (/^https?:\/\/embedpyrox\.xyz\/video\//i.test(url)) return url;
  const configuredBase = String(base || IMAX_BASE).replace(/\/$/, '');
  const isImaxHost = url.startsWith(configuredBase) ||
    /^https?:\/\/(?:[^./]+\.)?imaxstreams\.(?:net|com)(?:\/|$)/i.test(url);
  return isImaxHost && /\/(?:d|download|file|f|embed)\//i.test(url) ? url : null;
}

function indomaxPlayerSourceUrl(value, base) {
  const url = indomaxImaxSourceUrl(value, base);
  if (url) return url;
  // These two player tabs are present on current Indomax NSFW pages. Their
  // download URLs use different paths, so only accept the actual embed paths
  // while scanning a page for playable sources.
  if (/^https?:\/\/peytonepre\.com\/embed\//i.test(url || '')) return url;
  if (/^https?:\/\/iplayerhls\.com\/e\//i.test(url || '')) return url;
  const absolute = indomaxUrl(value, base);
  if (/^https?:\/\/peytonepre\.com\/embed\//i.test(absolute || '')) return absolute;
  if (/^https?:\/\/iplayerhls\.com\/e\//i.test(absolute || '')) return absolute;
  return null;
}

function indomaxPlayerUrls(html, base) {
  const urls = [];
  const iframe = /<iframe\b([^>]*)>/gi;
  let match;
  while ((match = iframe.exec(html || '')) != null) {
    const url = indomaxPlayerSourceUrl(
      indomaxAttribute(match[1], 'data-litespeed-src') || indomaxAttribute(match[1], 'src'),
      base,
    );
    if (url) urls.push(url);
  }
  const anchor = /<a\b([^>]*)>/gi;
  while ((match = anchor.exec(html || '')) != null) {
    const url = indomaxPlayerSourceUrl(indomaxAttribute(match[1], 'href'), base);
    if (url) urls.push(url);
  }
  return urls.filter((url, index) => urls.indexOf(url) === index);
}

function indomaxPlayerTabUrls(html, base) {
  const tabs = [];
  const block = /<ul\b[^>]*\bmuvipro-player-tabs\b[^>]*>([\s\S]*?)<\/ul>/i.exec(html || '');
  if (block == null) return tabs;
  const anchors = /<a\b([^>]*)>/gi;
  let match;
  while ((match = anchors.exec(block[1])) != null) {
    const url = indomaxUrl(indomaxAttribute(match[1], 'href'), base);
    if (url && tabs.indexOf(url) === -1) tabs.push(url);
  }
  return tabs;
}

async function indomaxPlayerCandidates(html, pageUrl, base) {
  const candidates = [];
  const add = (url, referer) => {
    if (!url || candidates.some((candidate) => candidate.url === url)) return;
    candidates.push({ url, referer });
  };
  indomaxPlayerUrls(html, base).forEach((url) => add(url, pageUrl));
  const tabs = indomaxPlayerTabUrls(html, base)
    .filter((url) => url !== pageUrl);
  const pages = await Promise.all(
    tabs.map(async (tabUrl) => ({
      url: tabUrl,
      response: await indomaxGet(tabUrl, pageUrl),
    })),
  );
  pages.forEach((page) => {
    if (page.response == null) return;
    indomaxPlayerUrls(page.response.body, base)
      .forEach((url) => add(url, page.url));
  });
  return candidates;
}

function indomaxPlayerSourceDescriptors(candidates) {
  return candidates.map((candidate, index) => {
    const host = /^https?:\/\/([^/?#]+)/i.exec(candidate.url)?.[1] || '';
    const label = /(?:embedpyrox|imaxstreams)/i.test(host)
      ? `ImaxStreams ${index + 1}`
      : `${host} ${index + 1}`;
    const id = `${INDOMAX_PROVIDER_KEY}:${encodeIndomaxSource({
      u: candidate.url,
      r: candidate.referer,
    })}`;
    return {
      id,
      label,
      provider: 'Nimora',
      providerId: INDOMAX_PROVIDER_ID,
    };
  });
}

function encodeIndomaxSource(payload) {
  return host.codec.textToBase64(JSON.stringify(payload))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function decodeIndomaxSource(value) {
  let base64 = String(value || '').replace(/-/g, '+').replace(/_/g, '/');
  const remaining = base64.length % 4;
  if (remaining) base64 += '='.repeat(4 - remaining);
  try { return JSON.parse(host.codec.base64ToText(base64)); } catch (_) { return null; }
}

async function indomaxSources(args) {
  const enabled = args && args.enabledProviders;
  if (enabled != null && enabled.indexOf(INDOMAX_PROVIDER_ID) === -1) return { sources: [] };
  const item = args && args.item;
  if (!item || (item.kind !== 'video' && item.kind !== 'episode')) return { sources: [] };
  const query = indomaxItemQuery(item);
  if (!query.title || (query.isEpisode && !query.episode)) return { sources: [] };
  const base = await indomaxActiveBase();
  const searchUrl = `${base}/?s=${encodeURIComponent(query.title)}&post_type[]=post&post_type[]=tv`;
  const refPayload = indomaxRefPayload(item.ref);
  const directEpisodeUrl = query.isEpisode && refPayload && Number(refPayload.e) === query.episode &&
      (query.season == null || refPayload.s == null || Number(refPayload.s) === query.season)
    ? refPayload.u
    : null;
  let result = refPayload && typeof refPayload.u === 'string'
    ? { title: query.title, url: refPayload.u }
    : null;
  let detailReferer = searchUrl;
  if (result == null) {
    const titleVariants = await indomaxItemTitleVariants(item, query.title);
    let found = null;
    for (const title of titleVariants) {
      found = await indomaxFindResult(title, base, query.isEpisode);
      if (found != null) break;
    }
    if (found == null) return { sources: [] };
    result = found.result;
    detailReferer = found.searchUrl;
    if (query.isEpisode) {
      const searchedEpisodeUrl = indomaxSearchEpisodeUrl(
        found.results || [],
        found.searchTitle || query.title,
        query.season,
        query.episode,
      );
      if (searchedEpisodeUrl != null) {
        const searchedEpisode = await indomaxGet(searchedEpisodeUrl, result.url);
        if (searchedEpisode == null) return { sources: [] };
        return {
          sources: indomaxPlayerSourceDescriptors(
            await indomaxPlayerCandidates(
              searchedEpisode.body,
              searchedEpisodeUrl,
              base,
            ),
          ),
        };
      }
    }
  } else {
    detailReferer = `${base}/`;
  }
  const detail = await indomaxGet(result.url, detailReferer);
  if (detail == null) return { sources: [] };
  const watchUrl = query.isEpisode
    ? directEpisodeUrl || indomaxEpisodeUrl(detail.body, query.episode, base, query.season)
    : result.url;
  if (watchUrl == null) return { sources: [] };
  const watch = watchUrl === result.url ? detail : await indomaxGet(watchUrl, result.url);
  if (watch == null) return { sources: [] };
  return {
    sources: indomaxPlayerSourceDescriptors(
      await indomaxPlayerCandidates(watch.body, watchUrl, base),
    ),
  };
}

function imaxEmbedUrl(url) {
  if (/\/embed\//i.test(url)) return url;
  const playerPath = /imaxstreams\.com/i.test(url) ? '/embed/' : '/e/';
  return url.replace(/\/(?:d|download|file|f)\//i, playerPath);
}

function imaxBaseUrl(url) {
  return /imaxstreams\.com/i.test(url) ? 'https://imaxstreams.com' : IMAX_BASE;
}

function indomaxFireId(url) {
  const match = /^https?:\/\/embedpyrox\.xyz\/video\/([^/?#]+)/i.exec(url || '');
  return match == null ? null : match[1];
}

async function indomaxFirePlaylists(url, referer) {
  const id = indomaxFireId(url);
  if (id == null) return null;
  const endpoint = `${INDOMAX_FIRE_BASE}/player/index.php?data=${encodeURIComponent(id)}&do=getVideo`;
  let response;
  try {
    response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        ...indomaxHeaders(referer),
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: `hash=${encodeURIComponent(id)}&r=${encodeURIComponent(referer || url)}`,
    });
  } catch (_) {
    return null;
  }
  if (response.status < 200 || response.status >= 300) return null;
  try {
    const data = JSON.parse(response.body);
    const playlists = [];
    const addPlaylist = (candidate) => {
      if (typeof candidate !== 'string') return;
      const normalized = candidate.replace(/\\\//g, '/');
      if (!/\.m3u8(?:[?#]|$)/i.test(normalized)) return;
      const resolved = indomaxUrl(normalized, INDOMAX_FIRE_BASE);
      if (resolved && playlists.indexOf(resolved) === -1) playlists.push(resolved);
    };
    const directLinks = [data.securedLink, data.videoSource];
    directLinks.forEach(addPlaylist);
    const candidates = Array.isArray(data.videoSources) ? data.videoSources : [];
    for (const candidate of candidates) {
      addPlaylist(candidate && candidate.file);
    }
    return playlists;
  } catch (_) {}
  return [];
}

function indomaxGenericEmbed(url) {
  return /^https?:\/\/(?:peytonepre\.com\/embed|iplayerhls\.com\/e)\//i.test(url || '');
}

function indomaxOrigin(url) {
  return /^(https?:\/\/[^/?#]+)/i.exec(url || '')?.[1] || null;
}

async function indomaxGenericPlaylists(url, referer) {
  if (!indomaxGenericEmbed(url)) return null;
  const origin = indomaxOrigin(url);
  if (!origin) return [];
  let response;
  try {
    response = await fetch(url, {
      headers: {
        ...indomaxHeaders(referer || `${origin}/`),
        Referer: referer || `${origin}/`,
      },
    });
  } catch (_) {
    return [];
  }
  if (response.status < 200 || response.status >= 300) return [];
  const scripts = [response.body, imaxUnpack(response.body)];
  const playlists = scripts
    .flatMap((script) => imaxPlaylistUrls(script))
    .map((playlist) => indomaxResolveRelativeUrl(playlist, url) || playlist)
    .filter((playlist, index, entries) => playlist && entries.indexOf(playlist) === index);
  return { playlists, headers: { ...indomaxHeaders(`${origin}/`), Origin: origin, Referer: `${origin}/` } };
}

function imaxPlaylistUrls(script) {
  const urls = [];
  const regex = /:\s*["']([^"']*\.m3u8[^"']*)["']/gi;
  let match;
  while ((match = regex.exec(script || '')) != null) urls.push(match[1].replace(/\\\//g, '/'));
  return urls.filter((url, index) => urls.indexOf(url) === index);
}

function indomaxResolveRelativeUrl(value, base) {
  if (typeof value !== 'string' || !value.trim() || typeof base !== 'string') return null;
  const raw = value.trim();
  if (/^https?:\/\//i.test(raw)) return raw;
  const baseMatch = /^(https?:\/\/[^/]+)(\/[^?#]*)?(?:[?#].*)?$/i.exec(base);
  if (baseMatch == null) return null;
  if (raw.startsWith('//')) return `${baseMatch[1].split(':')[0]}:${raw}`;
  const suffixIndex = raw.search(/[?#]/);
  const rawPath = suffixIndex === -1 ? raw : raw.slice(0, suffixIndex);
  const suffix = suffixIndex === -1 ? '' : raw.slice(suffixIndex);
  const basePath = baseMatch[2] || '/';
  let path;
  if (rawPath.startsWith('/')) {
    path = rawPath;
  } else if (!rawPath) {
    path = basePath;
  } else {
    const directory = basePath.slice(0, basePath.lastIndexOf('/') + 1);
    path = `${directory}${rawPath}`;
  }
  const parts = path.split('/');
  const normalized = [];
  for (const part of parts) {
    if (!part || part === '.') continue;
    if (part === '..') {
      if (normalized.length > 0) normalized.pop();
      continue;
    }
    normalized.push(part);
  }
  return `${baseMatch[1]}/${normalized.join('/')}${suffix}`;
}

function indomaxResponseHeader(response, name) {
  const headers = response && response.headers;
  if (headers == null || typeof headers !== 'object') return '';
  const wanted = String(name).toLowerCase();
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === wanted) return String(headers[key] || '');
  }
  return '';
}

function indomaxPlaylistFirstUri(body) {
  const lines = String(body || '').replace(/^\uFEFF/, '').split(/\r?\n/);
  for (const line of lines) {
    const value = line.trim();
    if (value && !value.startsWith('#')) return value;
  }
  return null;
}

function indomaxRejectMediaUri(url) {
  return /(?:(?:^|[./_-])ad-site(?:[./_-]|$)|\.image(?:[?#]|$)|(?:^|[./_-])advert(?:isement)?(?:[./_-]|$))/i.test(url || '');
}

function indomaxMediaResponseIsPlayable(response, url) {
  if (response == null || response.status < 200 || response.status >= 300) return false;
  if (indomaxRejectMediaUri(url)) return false;
  const body = String(response.body || '');
  if (!body) return false;
  if (/^GIF8|^\u0000?PNG/i.test(body)) return false;
  // Some valid FirePlayer segments are mislabeled as .js/.css. A transport
  // signature is stronger evidence than the extension or content type.
  if (body.charCodeAt(0) === 0x47 || body.slice(4, 8) === 'ftyp' || body.indexOf('moof') === 4) return true;
  const contentType = indomaxResponseHeader(response, 'content-type').toLowerCase();
  if (!contentType || /(?:text\/html|text\/css|javascript|font\/|image\/|application\/json)/i.test(contentType)) return false;
  return /(?:^|\/)(?:video|audio)\//i.test(contentType) ||
    /(?:mpeg|mp4|octet-stream|x-mpegurl|vnd\.apple\.mpegurl)/i.test(contentType);
}

async function indomaxHlsHasPlayableMedia(url, headers) {
  let response;
  try {
    response = await fetch(url, { headers });
  } catch (_) {
    return false;
  }
  if (response.status < 200 || response.status >= 300) return false;
  const masterBody = String(response.body || '').replace(/^\uFEFF/, '').trimStart();
  if (!masterBody.startsWith('#EXTM3U')) return false;
  let playlistUrl = url;
  let playlistBody = masterBody;
  if (/#EXT-X-STREAM-INF\b/i.test(playlistBody)) {
    const variant = indomaxPlaylistFirstUri(playlistBody);
    playlistUrl = indomaxResolveRelativeUrl(variant, playlistUrl);
    if (!playlistUrl || indomaxRejectMediaUri(playlistUrl)) return false;
    try {
      response = await fetch(playlistUrl, { headers });
    } catch (_) {
      return false;
    }
    if (response.status < 200 || response.status >= 300) return false;
    playlistBody = String(response.body || '').replace(/^\uFEFF/, '').trimStart();
    if (!playlistBody.startsWith('#EXTM3U')) return false;
  }
  const mediaUri = indomaxPlaylistFirstUri(playlistBody);
  const mediaUrl = indomaxResolveRelativeUrl(mediaUri, playlistUrl);
  if (!mediaUrl || indomaxRejectMediaUri(mediaUrl)) return false;
  try {
    const media = await fetch(mediaUrl, { headers });
    return indomaxMediaResponseIsPlayable(media, mediaUrl);
  } catch (_) {
    return false;
  }
}

// ImaxStreams commonly wraps `var links` in Dean Edwards' P.A.C.K.E.R.
// This decodes only that data substitution format; it never evaluates the
// upstream script. Plain `sources:` pages continue through unchanged.
function imaxUnpack(script) {
  const packed = /}\(\s*'((?:\\.|[^'])*)'\s*,\s*(\d+)\s*,\s*\d+\s*,\s*'((?:\\.|[^'])*)'\.split\('\|'\)/i.exec(script || '');
  if (packed == null) return String(script || '');
  const payload = packed[1]
    .replace(/\\'/g, "'")
    .replace(/\\\\/g, '\\');
  const radix = Number(packed[2]);
  const words = packed[3].replace(/\\'/g, "'").split('|');
  if (!Number.isInteger(radix) || radix < 2 || words.length === 0) return String(script || '');
  const digits = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const token = (index) => {
    if (radix <= 36) return index.toString(radix);
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
    unpacked = unpacked.replace(
      new RegExp(`\\b${escapedToken}\\b`, 'g'),
      words[index],
    );
  }
  return unpacked;
}

async function indomaxResolveSource(sourceId) {
  const prefix = `${INDOMAX_PROVIDER_KEY}:`;
  if (typeof sourceId !== 'string' || !sourceId.startsWith(prefix)) throw new Error('Invalid Indomax source id');
  const payload = decodeIndomaxSource(sourceId.slice(prefix.length));
  if (!payload || typeof payload.u !== 'string' || !/^https?:\/\//i.test(payload.u)) throw new Error('Malformed Indomax source id');
  const firePlaylists = await indomaxFirePlaylists(payload.u, payload.r);
  if (firePlaylists != null) {
    const fireHeaders = {
      ...indomaxHeaders(payload.r || INDOMAX_FIRE_BASE),
      Origin: INDOMAX_FIRE_BASE,
    };
    for (const firePlaylist of firePlaylists) {
      if (await indomaxHlsHasPlayableMedia(firePlaylist, fireHeaders)) {
        return { url: firePlaylist, format: 'hls', headers: fireHeaders };
      }
    }
    throw new Error('ImaxStreams playlist has no playable media');
  }
  const generic = await indomaxGenericPlaylists(payload.u, payload.r);
  if (generic != null) {
    for (const playlist of generic.playlists) {
      if (await indomaxHlsHasPlayableMedia(playlist, generic.headers)) {
        return { url: playlist, format: 'hls', headers: generic.headers };
      }
    }
    throw new Error('Indomax fallback player has no playable media');
  }
  const embed = imaxEmbedUrl(payload.u);
  const playerBase = imaxBaseUrl(payload.u);
  let response;
  try { response = await fetch(embed, { headers: indomaxHeaders(payload.r) }); } catch (_) { throw new Error('ImaxStreams embed request failed'); }
  if (response.status < 200 || response.status >= 300) throw new Error(`ImaxStreams returned HTTP ${response.status}`);
  const playlistCandidates = [
    ...imaxPlaylistUrls(response.body),
    ...imaxPlaylistUrls(imaxUnpack(response.body)),
  ].filter((url, index, entries) => entries.indexOf(url) === index);
  const playbackHeaders = imaxHeaders(playerBase);
  for (const playlist of playlistCandidates) {
    const playlistUrl = indomaxResolveRelativeUrl(playlist, embed) || indomaxUrl(playlist, playerBase);
    if (playlistUrl && await indomaxHlsHasPlayableMedia(playlistUrl, playbackHeaders)) {
      return { url: playlistUrl, format: 'hls', headers: playbackHeaders };
    }
  }
  if (playlistCandidates.length === 0) throw new Error('No HLS playlist in ImaxStreams embed');
  throw new Error('ImaxStreams playlist has no playable media');
}

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: INDOMAX_PROVIDER_KEY,
  sources: indomaxSources,
  resolve: (sourceId) => indomaxResolveSource(sourceId),
});

globalThis.__metaProviders = globalThis.__metaProviders || [];
globalThis.__metaProviders.push({
  providerId: INDOMAX_PROVIDER_ID,
  meta: indomaxMeta,
});

globalThis.__catalogProviders = globalThis.__catalogProviders || [];
globalThis.__catalogProviders.push({
  catalogId: INDOMAX_NSFW_CATALOG_ID,
  catalog: indomaxNsfwCatalog,
});

globalThis.__extension = globalThis.__extension || {};
const indomaxPreviousSearch = globalThis.__extension.search;
globalThis.__extension.search = async (args) => {
  let existing = { sections: [] };
  try {
    if (typeof indomaxPreviousSearch === 'function') {
      existing = await indomaxPreviousSearch(args);
    }
  } catch (_) {}
  const existingSections = Array.isArray(existing.sections) ? existing.sections : [];
  const hasExistingItems = existingSections.some(
    (section) => section != null && Array.isArray(section.items) && section.items.length > 0,
  );
  if (hasExistingItems) return existing;

  let indomax = { sections: [] };
  try {
    indomax = await indomaxSearch(args);
  } catch (_) {}
  const indomaxSections = Array.isArray(indomax.sections) ? indomax.sections : [];
  const hasIndomaxItems = indomaxSections.some(
    (section) => section != null && Array.isArray(section.items) && section.items.length > 0,
  );
  return hasIndomaxItems ? indomax : existing;
};
