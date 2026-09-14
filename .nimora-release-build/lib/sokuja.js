// Sokuja anime catalog and streams. The catalog reads Sokuja's public anime
// pages and its embedded ranking payload; streams still resolve through the
// site's mirror endpoint for Nimora's VOD items.
//
// Sokuja's CloudStream implementation delegates mirror extraction to the
// CloudStream extractor framework. The app has no extractor runtime, so this
// provider follows Sokuja's own JSON mirror endpoint and only returns mirrors
// that already contain a direct media URL.

// Sokuja rotates its streaming domain every few weeks. Two landing hosts
// announce the current one and have stayed put across rotations: sokuja.net
// 302s straight to the live mirror, and sokuja.id links it behind its primary
// button. A mirror pinned in the bundle means the provider dies silently on
// every rotation, so the base is discovered at runtime and the pin below is
// only the last resort.
const SOKUJA_FALLBACK_BASE = 'https://x6.sokuja.uk';
const SOKUJA_LANDING_URLS =
  Array.isArray(globalThis.__sokujaLandingUrls) &&
    globalThis.__sokujaLandingUrls.length > 0
    ? globalThis.__sokujaLandingUrls.map(String)
    : ['https://sokuja.net/', 'https://sokuja.id/'];
// Links the landing page carries that are never the mirror.
const SOKUJA_LINK_DENYLIST = [
  't.me',
  'telegram.me',
  'telegram.org',
  'facebook.com',
  'youtube.com',
  'youtu.be',
  'instagram.com',
  'twitter.com',
  'x.com',
  'discord.gg',
  'discord.com',
  'schema.org',
];
// An explicit base opts out of discovery entirely, with no request spent on
// it: that is what the tests pin, and what a host override would mean.
const SOKUJA_BASE_OVERRIDE =
  typeof globalThis.__sokujaBaseUrl === 'string' && globalThis.__sokujaBaseUrl
    ? globalThis.__sokujaBaseUrl
    : null;
let sokujaActiveBase = SOKUJA_BASE_OVERRIDE || SOKUJA_FALLBACK_BASE;
let sokujaBasePending = null;
// Distinguishes "the mirror did not answer" from "the mirror has no such
// anime". Only the former is worth re-running discovery for.
const SOKUJA_UNREACHABLE = { unreachable: true };
const SOKUJA_TMDB_BASE =
  globalThis.__sokujaTmdbBaseUrl || 'https://api.themoviedb.org/3';
const SOKUJA_TMDB_API_KEY = '8476a7ab80ad76f0936744df0430e67c';
const SOKUJA_PROVIDER_KEY = 'sokuja';
const SOKUJA_PROVIDER_ID = 'nimora.sokuja';
const SOKUJA_CATALOG_ID = 'sokuja';
const SOKUJA_ANIME_CATEGORY = 'anime';
const SOKUJA_CATALOG_ORDERS = [
  { id: 'update', name: 'Latest Updates', order: 'update' },
  { id: 'top', name: 'Top Rated', order: 'score' },
  { id: 'popular', name: 'Most Popular', order: 'popular' },
];
const SOKUJA_CATALOG_PER_PAGE = 24;
const SOKUJA_RANKING_PATH = '/anime/?order=popular';
let sokujaRankingPending = null;
const SOKUJA_USER_AGENT =
  'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/137.0.0.0 Mobile Safari/537.36';

function sokujaHeaders(referer) {
  return {
    Accept: 'text/html,application/json;q=0.9,*/*;q=0.8',
    Referer: referer || `${sokujaActiveBase}/`,
    'User-Agent': SOKUJA_USER_AGENT,
  };
}

function sokujaUrl(path) {
  if (typeof path !== 'string' || path.length === 0) return null;
  if (/^https?:\/\//i.test(path)) return path;
  if (path.startsWith('/')) return `${sokujaActiveBase}${path}`;
  return `${sokujaActiveBase}/${path}`;
}

function sokujaDecodeHtml(value) {
  return String(value || '')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
    .replace(/\s+/g, ' ')
    .trim();
}

function sokujaAttribute(attributes, name) {
  const pattern = new RegExp(
    `${name}\\s*=\\s*[\\\"']([^\\\"']+)[\\\"']`,
    'i',
  );
  const match = pattern.exec(attributes || '');
  return match == null ? null : sokujaDecodeHtml(match[1]);
}

function sokujaTagText(html, tag) {
  const match = new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i').exec(html);
  return match == null ? '' : sokujaDecodeHtml(match[1]);
}

function sokujaNormalizeTitle(title) {
  return String(title || '')
    .replace(/\s*subtitle\s+indonesia\s*$/i, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .toLowerCase();
}

function sokujaSeasonTitleMatch(title, wanted, season) {
  if (!Number.isInteger(season) || season < 1) return false;
  const normalized = sokujaNormalizeTitle(title);
  const base = sokujaNormalizeTitle(wanted);
  return normalized === `${base} season ${season}` ||
    normalized === `${base} s${season}`;
}

function sokujaSearchResults(html) {
  const results = [];
  const cardPattern =
    /<a\b([^>]*class\s*=\s*[\"'][^\"']*\bgroup\b[^\"']*[\"'][^>]*)>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = cardPattern.exec(html || '')) != null) {
    const href = sokujaUrl(sokujaAttribute(match[1], 'href'));
    if (href == null) continue;
    const card = match[2];
    const title = sokujaTagText(card, 'h3') || sokujaTagText(card, 'p');
    if (!title) continue;
    const imageTag = /<img\b([^>]*)>/i.exec(card);
    const poster = imageTag == null
      ? null
      : sokujaUrl(
          sokujaAttribute(imageTag[1], 'src') ||
            sokujaAttribute(imageTag[1], 'data-src'),
        );
    const text = sokujaDecodeHtml(card);
    const typeMatch = /\b(TV|Movie|OVA|ONA|Special)\b/i.exec(text);
    const ratingMatch = /★\s*([0-9]+(?:\.[0-9]+)?)/.exec(text);
    const yearMatch = /\b((?:19|20)\d{2})\b/.exec(text);
    results.push({
      title,
      url: href,
      poster,
      type: typeMatch == null ? null : typeMatch[1].toLowerCase(),
      rating: ratingMatch == null ? null : Number(ratingMatch[1]),
      releaseYear: yearMatch == null ? null : Number(yearMatch[1]),
    });
  }
  return results;
}

function sokujaRscArray(html, key) {
  const normalized = String(html || '').replace(/\\"/g, '"');
  const marker = `"${key}"`;
  const markerStart = normalized.lastIndexOf(marker);
  if (markerStart < 0) return [];
  const arrayStart = normalized.indexOf('[', markerStart + marker.length);
  if (arrayStart < 0) return [];
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = arrayStart; index < normalized.length; index += 1) {
    const character = normalized[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (character === '\\') {
        escaped = true;
      } else if (character === '"') {
        inString = false;
      }
      continue;
    }
    if (character === '"') {
      inString = true;
    } else if (character === '[') {
      depth += 1;
    } else if (character === ']') {
      depth -= 1;
      if (depth === 0) {
        try {
          const value = JSON.parse(normalized.slice(arrayStart, index + 1));
          return Array.isArray(value) ? value : [];
        } catch (_) {
          return [];
        }
      }
    }
  }
  return [];
}

function sokujaSearchCandidates(results, title, season) {
  const wanted = sokujaNormalizeTitle(title);
  if (!wanted) return [];
  const candidates = results
    .map((result, index) => {
      const normalized = sokujaNormalizeTitle(result.title);
      if (!normalized) return null;
      const exact = normalized === wanted;
      const seasonExact = sokujaSeasonTitleMatch(result.title, wanted, season);
      const startsWith = normalized.startsWith(wanted);
      if (!exact && !startsWith) return null;
      const seasonMatch = season != null &&
        new RegExp(`(?:season\\s*${season}|\\bs${season}\\b)`, 'i')
          .test(result.title);
      return {
        result,
        score: (seasonExact ? -4 : exact ? 0 : 10) +
          (seasonMatch ? -2 : 0) + index / 1000,
        seasonExact,
      };
    })
    .filter((entry) => entry != null)
    .sort((a, b) => a.score - b.score);
  return candidates;
}

function sokujaSearchPick(results, title, season) {
  const candidates = sokujaSearchCandidates(results, title, season);
  return candidates.length === 0 ? null : candidates[0].result;
}

function sokujaDateKey(value) {
  const match = /(?:^|[^0-9])(\d{4}-\d{2}-\d{2})(?:[^0-9]|$)/.exec(
    String(value || ''),
  );
  return match == null ? null : match[1];
}

async function sokujaGet(url, options) {
  try {
    const response = await fetch(url, options);
    if (response.status < 200 || response.status >= 300) return null;
    return response;
  } catch (_) {
    return null;
  }
}

function sokujaHostOf(url) {
  const match = /^https?:\/\/([^/?#]+)/i.exec(String(url || ''));
  if (match == null) return null;
  const host = match[1].toLowerCase().replace(/:\d+$/, '');
  return host.startsWith('www.') ? host.slice(4) : host;
}

function sokujaOriginOf(url) {
  const match = /^(https?:\/\/[^/?#]+)/i.exec(String(url || ''));
  return match == null ? null : match[1];
}

// A landing host names the mirror; it is never the mirror itself, and neither
// is any of the social links it sits next to. Excluding by origin rather than
// by host keeps the check honest when two origins share a host.
function sokujaIsMirrorOrigin(origin) {
  if (origin == null) return false;
  if (SOKUJA_LANDING_URLS.some((url) => sokujaOriginOf(url) === origin)) {
    return false;
  }
  const host = sokujaHostOf(origin);
  if (host == null || host.indexOf('.') === -1) return false;
  return !SOKUJA_LINK_DENYLIST.some(
    (denied) => host === denied || host.endsWith(`.${denied}`),
  );
}

// The landing page marks the mirror with `button-default` and every other
// button is a social link. Falling back to the first non-social absolute link
// keeps this working if that class is renamed, which is the part of the page
// most likely to change.
function sokujaMirrorLink(html) {
  const anchors = /<a\b([^>]*)>/gi;
  let fallback = null;
  let match;
  while ((match = anchors.exec(html || '')) != null) {
    const origin = sokujaOriginOf(sokujaAttribute(match[1], 'href'));
    if (!sokujaIsMirrorOrigin(origin)) continue;
    if (/button-default/i.test(match[1])) return origin;
    if (fallback == null) fallback = origin;
  }
  return fallback;
}

async function sokujaProbeLanding(landingUrl) {
  const response = await sokujaGet(
    landingUrl,
    { headers: sokujaHeaders(landingUrl) },
  );
  if (response == null) return null;
  // `fetch` follows the Location chain itself and reports where it landed, so
  // a redirecting landing host has already named the mirror.
  const redirected = sokujaOriginOf(response.url);
  if (sokujaIsMirrorOrigin(redirected)) return redirected;
  return sokujaMirrorLink(response.body);
}

async function sokujaResolveBase() {
  for (const landing of SOKUJA_LANDING_URLS) {
    const base = await sokujaProbeLanding(landing);
    if (base != null) {
      sokujaActiveBase = base;
      return base;
    }
  }
  // Both landing hosts unreachable — an outage, or an ISP block on them
  // specifically. Keep the base we already have rather than giving up: it is
  // stale at worst, and often still serving.
  return sokujaActiveBase;
}

// Memoised on the promise rather than the value: one `sources()` fan-out can
// issue several Sokuja lookups at once, and they must share one discovery.
function sokujaEnsureBase() {
  if (SOKUJA_BASE_OVERRIDE != null) return Promise.resolve(SOKUJA_BASE_OVERRIDE);
  if (sokujaBasePending == null) {
    sokujaBasePending = sokujaResolveBase().catch(() => sokujaActiveBase);
  }
  return sokujaBasePending;
}

function sokujaForgetBase() {
  if (SOKUJA_BASE_OVERRIDE == null) sokujaBasePending = null;
}

async function sokujaFindAnime(title, season, availableAt) {
  const searchUrl =
    `${sokujaActiveBase}/?s=${encodeURIComponent(title)}&page=1`;
  const response = await sokujaGet(searchUrl, { headers: sokujaHeaders(searchUrl) });
  if (response == null) return SOKUJA_UNREACHABLE;
  const candidates = sokujaSearchCandidates(
    sokujaSearchResults(response.body),
    title,
    season,
  );
  if (candidates.length === 0) return null;
  const wanted = sokujaNormalizeTitle(title);
  const wantedDate = sokujaDateKey(availableAt);
  if (wantedDate != null) {
    let exactMatch = null;
    for (const candidate of candidates) {
      const detail = await sokujaGet(
        candidate.result.url,
        { headers: sokujaHeaders(searchUrl) },
      );
      if (detail == null) continue;
      const episode = sokujaEpisodes(detail.body).find(
        (entry) => sokujaDateKey(entry && entry.createdAt) === wantedDate,
      );
      if (episode != null && typeof episode.slug === 'string') {
        return {
          result: candidate.result,
          detailBody: detail.body,
          episodeNumber: Number(episode.episodeNumber),
          matchedByDate: true,
        };
      }
      if (exactMatch == null &&
          (sokujaNormalizeTitle(candidate.result.title) === wanted ||
            candidate.seasonExact)) {
        exactMatch = { result: candidate.result, detailBody: detail.body };
      }
    }
    // `createdAt` is when Sokuja uploaded the episode, not when it aired, so a
    // series it posted years after broadcast can never match by date — One
    // Piece episode 1 aired in 1999 and was uploaded in 2017. Only a loose
    // title match is a split-cour risk worth refusing; an exact one is the
    // series itself, and falls back to matching by episode number.
    return exactMatch;
  }
  const selected = candidates[0];
  const detail = await sokujaGet(
    selected.result.url,
    { headers: sokujaHeaders(searchUrl) },
  );
  if (detail == null) return null;
  // A loose title match with dated episodes is a split-cour candidate. Without
  // an aired date, refusing it is safer than silently playing another cour.
  // A title qualified with the requested season is not loose: Sokuja uses that
  // form for the exact AniList cour when AniList does not provide an episode
  // air date.
  const hasDatedEpisodes = sokujaEpisodes(detail.body).some(
    (entry) => sokujaDateKey(entry && entry.createdAt) != null,
  );
  const exact = sokujaNormalizeTitle(selected.result.title) === wanted;
  if (!exact && !selected.seasonExact && hasDatedEpisodes) return null;
  return { result: selected.result, detailBody: detail.body };
}

// Next.js renders the episode list inside an escaped JSON payload. The same
// shape is also present in the older HTML used by the original extension.
function sokujaEpisodes(html) {
  const normalized = String(html || '')
    .replace(/\\"/g, '"')
    .replace(/\\u0026/g, '&');
  const match = /"episodes"\s*:\s*\[([\s\S]*?)\]\s*,\s*"episodesTotal"/.exec(normalized);
  if (match == null) return [];
  try {
    const episodes = JSON.parse(`[${match[1]}]`);
    return Array.isArray(episodes) ? episodes : [];
  } catch (_) {
    return [];
  }
}

function sokujaEpisodeUrl(html, episodeNumber, availableAt) {
  const wanted = Number(episodeNumber);
  if (!Number.isInteger(wanted) || wanted < 1) return null;
  const episodes = sokujaEpisodes(html);
  const airedDate = sokujaDateKey(availableAt);
  const datedEpisodes = episodes.filter(
    (entry) => sokujaDateKey(entry && entry.createdAt) != null,
  );
  const dateMatch = airedDate == null
    ? null
    : datedEpisodes.find((entry) => sokujaDateKey(entry && entry.createdAt) === airedDate);
  // A numbered fallback is unsafe when Sokuja exposes dated episodes: a
  // partial title match can otherwise play episode 1 from another split-cour.
  if (airedDate != null && datedEpisodes.length > 0) {
    return dateMatch && typeof dateMatch.slug === 'string'
      ? sokujaUrl(`/${dateMatch.slug}/`)
      : null;
  }
  const numberMatch = episodes.find(
    (entry) => Number(entry && entry.episodeNumber) === wanted,
  );
  const episode = dateMatch || numberMatch;
  if (episode && typeof episode.slug === 'string') return sokujaUrl(`/${episode.slug}/`);

  const pattern = new RegExp(
    `href=[\"']([^\"']*episode-${wanted}[^\"']*)[\"']`,
    'i',
  );
  const fallback = pattern.exec(html || '');
  return fallback == null ? null : sokujaUrl(fallback[1]);
}

function sokujaHighestEpisodeNumber(html) {
  return sokujaEpisodes(html).reduce((highest, entry) => {
    const number = Number(entry && entry.episodeNumber);
    return Number.isInteger(number) && number > highest ? number : highest;
  }, 0);
}

// TMDB splits a long-running anime into arc-sized seasons while Sokuja numbers
// the whole run straight through: One Piece season 2 episode 1 is episode 62
// there. Asking such a page for episode 1 would quietly play the wrong episode
// — worse than offering no source — so the season-relative number is used only
// for entries whose own list never reaches the absolute one. Those are the
// per-cour pages, which start counting from 1 again.
async function sokujaNumberedEpisodeUrl(item, query, detailBody) {
  const relative = sokujaEpisodeUrl(detailBody, query.episode, null);
  if (!Number.isInteger(query.season) || query.season <= 1) return relative;
  const absolute = await sokujaAbsoluteEpisode(item, query.season, query.episode);
  if (absolute == null) return null;
  if (sokujaHighestEpisodeNumber(detailBody) < absolute) return relative;
  return sokujaEpisodeUrl(detailBody, absolute, null);
}

function sokujaMovieUrl(html) {
  const pattern = /href=[\"']([^\"']+)[\"']/gi;
  let match;
  while ((match = pattern.exec(html || '')) != null) {
    if (/episode-/i.test(match[1])) return sokujaUrl(match[1]);
  }
  return null;
}

function sokujaEpisodeId(html) {
  const normalized = String(html || '').replace(/\\"/g, '"');
  const match = /episodeId"\s*:\s*(\d+)/i.exec(normalized);
  return match == null ? null : match[1];
}

function encodeSokujaSource(payload) {
  return host.codec.textToBase64(JSON.stringify(payload))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function decodeSokujaSource(encoded) {
  let base64 = String(encoded || '').replace(/-/g, '+').replace(/_/g, '/');
  const remainder = base64.length % 4;
  if (remainder !== 0) base64 += '='.repeat(4 - remainder);
  try {
    return JSON.parse(host.codec.base64ToText(base64));
  } catch (_) {
    return null;
  }
}

function sokujaMirrorEntries(mirrors) {
  const seen = new Set();
  return (Array.isArray(mirrors) ? mirrors : [])
    .map((mirror) => ({
      url: mirror && typeof mirror.embedUrl === 'string'
        ? mirror.embedUrl.trim()
        : '',
      quality: mirror && typeof mirror.quality === 'string'
        ? mirror.quality.trim()
        : '',
    }))
    .filter((mirror) => /^https?:\/\//i.test(mirror.url))
    .filter((mirror) => !seen.has(mirror.url) && seen.add(mirror.url));
}

function sokujaQualityHeight(value) {
  const match = /(?:^|[^0-9])(\d{3,4})\s*p?(?=$|[^a-z0-9])/i.exec(
    String(value || ''),
  );
  const height = match == null ? NaN : Number(match[1]);
  return Number.isInteger(height) && height > 0 ? height : null;
}

function sokujaVariantEntries(mirrors, headers) {
  const ids = new Set();
  return mirrors.map((mirror, index) => {
    const height = sokujaQualityHeight(mirror.quality);
    const base = height == null ? `mirror-${index + 1}` : `quality-${height}p`;
    let id = base;
    let suffix = 2;
    while (ids.has(id)) id = `${base}-${suffix++}`;
    ids.add(id);
    return {
      id,
      url: mirror.url,
      headers,
      format: /\.m3u8(?:$|\?)/i.test(mirror.url) ? 'hls' : 'other',
      label: mirror.quality || `Sokuja Mirror ${index + 1}`,
      ...(height == null ? {} : {height}),
    };
  });
}

function sokujaTmdbEpisodeRef(item) {
  const refId = item && item.ref && item.ref.id;
  if (typeof refId !== 'string') return null;
  const match = /^(?:v1-episode:)?series:([^:]+):season:([^:]+):episode:([^:]+)$/.exec(
    refId,
  );
  return match == null
    ? null
    : { tmdbId: match[1], season: match[2], episode: match[3] };
}

async function sokujaEpisodeAvailableAt(item) {
  const direct = item && item.availableAt;
  const directDate = sokujaDateKey(direct);
  if (directDate != null) return directDate;

  const parsed = sokujaTmdbEpisodeRef(item);
  if (parsed == null) return null;

  const query = [
    `api_key=${encodeURIComponent(SOKUJA_TMDB_API_KEY)}`,
    'language=en-US',
  ].join('&');
  const response = await sokujaGet(
    `${SOKUJA_TMDB_BASE}/tv/${encodeURIComponent(parsed.tmdbId)}` +
      `/season/${encodeURIComponent(parsed.season)}` +
      `/episode/${encodeURIComponent(parsed.episode)}?${query}`,
    { headers: sokujaHeaders(SOKUJA_TMDB_BASE) },
  );
  if (response == null) return null;
  try {
    const payload = JSON.parse(response.body);
    return sokujaDateKey(payload && payload.air_date);
  } catch (_) {
    return null;
  }
}

// Counts the episodes TMDB places before [season] to turn a season-relative
// number into the absolute one Sokuja indexes by.
async function sokujaAbsoluteEpisode(item, season, episode) {
  if (!Number.isInteger(episode) || episode < 1) return null;
  const parsed = sokujaTmdbEpisodeRef(item);
  if (parsed == null) return null;

  const query = [
    `api_key=${encodeURIComponent(SOKUJA_TMDB_API_KEY)}`,
    'language=en-US',
  ].join('&');
  const response = await sokujaGet(
    `${SOKUJA_TMDB_BASE}/tv/${encodeURIComponent(parsed.tmdbId)}?${query}`,
    { headers: sokujaHeaders(SOKUJA_TMDB_BASE) },
  );
  if (response == null) return null;
  let seasons;
  try {
    const payload = JSON.parse(response.body);
    seasons = Array.isArray(payload && payload.seasons) ? payload.seasons : [];
  } catch (_) {
    return null;
  }

  let offset = 0;
  for (const entry of seasons) {
    const number = Number(entry && entry.season_number);
    // Season 0 is specials: not part of the run Sokuja numbers through.
    if (!Number.isInteger(number) || number < 1 || number >= season) continue;
    const count = Number(entry && entry.episode_count);
    // One unknown count makes the whole sum wrong, so refuse rather than guess.
    if (!Number.isInteger(count) || count < 1) return null;
    offset += count;
  }
  return offset === 0 ? null : offset + episode;
}

function sokujaItemQuery(item) {
  const extra = item && item.extra && typeof item.extra === 'object'
    ? item.extra
    : {};
  const v2Episode = item && item.episode && typeof item.episode === 'object'
    ? item.episode
    : null;
  const groupId = v2Episode && typeof v2Episode.groupId === 'string'
    ? v2Episode.groupId
    : '';
  const seasonMatch = /(?:^|:)season:(\d+)/i.exec(groupId);
  const v2Season = seasonMatch == null ? null : Number(seasonMatch[1]);
  const v2EpisodeNumber = v2Episode && Number.isInteger(v2Episode.position)
    ? v2Episode.position
    : null;
  const v2SeriesTitle = item && typeof item.subtitle === 'string'
    ? item.subtitle.trim()
    : '';
  let title = '';
  if (typeof extra.seriesTitle === 'string' && extra.seriesTitle.trim()) {
    title = extra.seriesTitle;
  } else if (v2SeriesTitle) {
    title = v2SeriesTitle;
  } else if (item && typeof item.title === 'string') {
    title = item.title;
  }
  const season = Number.isInteger(extra.season) ? extra.season : v2Season;
  const episode = Number.isInteger(extra.episode) ? extra.episode : v2EpisodeNumber;
  return { title, season, episode, isEpisode: item && item.kind === 'episode' };
}

function sokujaPathOf(url) {
  const origin = sokujaOriginOf(url);
  if (origin == null || typeof url !== 'string') return null;
  const path = url.slice(origin.length);
  return path || '/';
}

function sokujaCatalogRefId(result) {
  return `${SOKUJA_PROVIDER_KEY}:anime:${encodeSokujaSource({
    p: sokujaPathOf(result.url),
    t: result.title,
    k: result.type === 'movie' ? 'video' : 'series',
    r: result.rating,
    y: result.releaseYear,
    i: result.poster,
  })}`;
}

function sokujaCatalogRefPayload(refId) {
  const prefix = `${SOKUJA_PROVIDER_KEY}:anime:`;
  if (typeof refId !== 'string' || !refId.startsWith(prefix)) return null;
  const payload = decodeSokujaSource(refId.slice(prefix.length));
  return payload && typeof payload.p === 'string' ? payload : null;
}

function sokujaCatalogItem(result) {
  const item = {
    ref: {
      extensionId: EXTENSION_ID,
      providerId: SOKUJA_PROVIDER_ID,
      id: sokujaCatalogRefId(result),
    },
    kind: result.type === 'movie' ? 'video' : 'series',
    title: result.title,
  };
  if (Number.isInteger(result.releaseYear) && result.releaseYear > 0) {
    item.releaseYear = result.releaseYear;
  }
  if (Number.isFinite(result.rating) && result.rating > 0) item.rating = result.rating;
  if (typeof result.poster === 'string' && result.poster) {
    item.artwork = { portrait: { url: result.poster } };
  }
  return item;
}

function sokujaCatalogOrder(subCategory) {
  if (subCategory == null) return SOKUJA_CATALOG_ORDERS[0];
  return SOKUJA_CATALOG_ORDERS.find((entry) => entry.id === subCategory) || null;
}

function sokujaHasNextPage(html, order, page) {
  const next = Number(page) + 1;
  return new RegExp(
    `(?:page=${next}(?:&|["']|$)|page%3D${next})`,
    'i',
  ).test(html || '') || new RegExp(
    `order=${order}[^"']*page=${next}`,
    'i',
  ).test(html || '');
}

async function sokujaCatalog(query) {
  if (query.category !== SOKUJA_ANIME_CATEGORY) return { sections: [] };
  const subCategories = SOKUJA_CATALOG_ORDERS.map((entry) => ({
    id: entry.id,
    name: entry.name,
  }));
  const selected = sokujaCatalogOrder(query.subCategory);
  if (selected == null) return { sections: [], subCategories };
  const requested = Number(query.page);
  const page = Number.isInteger(requested) && requested > 0 ? requested : 1;
  await sokujaEnsureBase();
  const params = `order=${encodeURIComponent(selected.order)}` +
    (page > 1 ? `&page=${page}` : '');
  const url = `${sokujaActiveBase}/anime/?${params}`;
  const response = await sokujaGet(url, { headers: sokujaHeaders(url) });
  if (response == null) return { sections: [], subCategories };
  const items = sokujaSearchResults(response.body)
    .slice(0, SOKUJA_CATALOG_PER_PAGE)
    .map(sokujaCatalogItem);
  const result = {
    sections: [{ id: selected.id, items }],
    subCategories,
  };
  if (sokujaHasNextPage(response.body, selected.order, page)) {
    result.nextPage = String(page + 1);
  }
  return result;
}

function sokujaDescription(html) {
  const match = /<h2\b[^>]*>\s*Sinopsis[\s\S]*?<\/h2>\s*<p\b[^>]*>([\s\S]*?)<\/p>/i.exec(
    html || '',
  );
  return match == null ? '' : sokujaDecodeHtml(match[1]);
}

function sokujaDetailGenres(html) {
  const genres = [];
  const pattern = /<a\b[^>]*href=["'][^"']*\/genre\/[^"']+["'][^>]*>([\s\S]*?)<\/a>/gi;
  let match;
  while ((match = pattern.exec(html || '')) != null) {
    const genre = sokujaDecodeHtml(match[1]);
    if (genre && genres.indexOf(genre) === -1) genres.push(genre);
  }
  return genres;
}

function sokujaCatalogEpisodeRef(parentPath, episode) {
  return `${SOKUJA_PROVIDER_KEY}:episode:${encodeSokujaSource({
    p: parentPath,
    n: episode,
  })}`;
}

function sokujaCatalogEpisodeGuide(parentRef, html) {
  const entries = sokujaEpisodes(html)
    .map((entry) => ({
      number: Number(entry && entry.episodeNumber),
      slug: entry && entry.slug,
      createdAt: sokujaEpisodeGuideDate(entry && entry.createdAt),
    }))
    .filter((entry) => Number.isInteger(entry.number) && entry.number > 0)
    .filter((entry) => typeof entry.slug === 'string' && entry.slug.length > 0)
    .sort((a, b) => a.number - b.number);
  if (entries.length === 0) return null;
  const parentPath = sokujaPathOf(parentRef.url);
  const episodes = entries.map((entry) => {
    const episode = {
      ref: {
        extensionId: EXTENSION_ID,
        providerId: SOKUJA_PROVIDER_ID,
        id: sokujaCatalogEpisodeRef(parentPath, entry.number),
      },
      title: `Episode ${entry.number}`,
      position: entry.number,
    };
    if (typeof entry.createdAt === 'string' && entry.createdAt) {
      episode.availableAt = entry.createdAt;
    }
    return episode;
  });
  return {
    groups: [{ id: 'season:1', title: 'Episodes', episodes }],
    defaultEpisodeRef: episodes[episodes.length - 1].ref,
  };
}

async function sokujaItemTitleVariants(item, fallback) {
  if (typeof globalThis.__animeTitleVariants !== 'function') return [fallback];
  try {
    const variants = await globalThis.__animeTitleVariants(item);
    return Array.isArray(variants) && variants.length > 0 ? variants : [fallback];
  } catch (_) {
    return [fallback];
  }
}

function sokujaEpisodeGuideDate(value) {
  if (typeof value !== 'string' || value.length === 0) return null;
  // Next.js RSC serializes Date values with a `$D` prefix. The extension
  // protocol expects the underlying ISO-8601 UTC timestamp instead.
  const normalized = value.replace(/^\$D(?=\d{4}-)/, '');
  return /^\d{4}-\d{2}-\d{2}T.*Z$/.test(normalized) ? normalized : null;
}

async function sokujaCatalogMeta(args) {
  const payload = sokujaCatalogRefPayload(args && args.ref && args.ref.id);
  if (payload == null) {
    throw new Error(`Not a Sokuja catalog ref id: ${args && args.ref && args.ref.id}`);
  }
  await sokujaEnsureBase();
  const url = sokujaUrl(payload.p);
  const response = await sokujaGet(url, { headers: sokujaHeaders(`${sokujaActiveBase}/`) });
  if (response == null) throw new Error(`Sokuja has no anime ${payload.p}`);
  const heading = sokujaTagText(response.body, 'h1')
    .replace(/\s+subtitle\s+indonesia\s*$/i, '')
    .trim();
  const ref = args.ref;
  const item = {
    ref,
    kind: payload.k === 'video' ? 'video' : 'series',
    title: heading || payload.t || 'Untitled',
  };
  if (Number.isInteger(payload.y) && payload.y > 0) item.releaseYear = payload.y;
  if (Number.isFinite(payload.r) && payload.r > 0) item.rating = payload.r;
  if (typeof payload.i === 'string' && payload.i) {
    item.artwork = { portrait: { url: payload.i } };
  }
  const description = sokujaDescription(response.body);
  const detail = { item };
  if (description) detail.description = description;
  const genres = sokujaDetailGenres(response.body);
  if (genres.length > 0) detail.tags = genres;
  if (item.kind === 'series') {
    const guide = sokujaCatalogEpisodeGuide({ ref, url }, response.body);
    if (guide != null) detail.episodeGuide = guide;
  }
  return detail;
}

function sokujaRankingResult(entry) {
  if (!entry || typeof entry.slug !== 'string' || typeof entry.title !== 'string') {
    return null;
  }
  const poster = entry.thumbnailUrl || entry.coverUrl;
  return {
    title: entry.title.trim(),
    url: sokujaUrl(`/anime/${entry.slug}/`),
    poster: typeof poster === 'string' ? sokujaUrl(poster) : null,
    type: typeof entry.type === 'string' ? entry.type.toLowerCase() : null,
    rating: Number(entry.score),
    releaseYear: Number(entry.year),
  };
}

async function sokujaRankingPayload() {
  if (sokujaRankingPending == null) {
    sokujaRankingPending = (async () => {
      await sokujaEnsureBase();
      const url = sokujaUrl(SOKUJA_RANKING_PATH);
      const response = await sokujaGet(url, { headers: sokujaHeaders(url) });
      if (response == null) return {};
      return {
        weekly: sokujaRscArray(response.body, 'weekly'),
        all: sokujaRscArray(response.body, 'all'),
      };
    })().catch(() => ({}));
  }
  return sokujaRankingPending;
}

async function sokujaAnimeRankingItems(rank) {
  const payload = await sokujaRankingPayload();
  const entries = Array.isArray(payload[rank]) ? payload[rank] : [];
  return entries
    .map(sokujaRankingResult)
    .filter((entry) => entry != null)
    .map(sokujaCatalogItem);
}

globalThis.__sokujaAnimeRankingItems = sokujaAnimeRankingItems;

async function sokujaSearch(args) {
  if (args && args.category != null && args.category !== SOKUJA_ANIME_CATEGORY) {
    return { sections: [] };
  }
  const query = args && args.query;
  if (!query) return { sections: [] };
  const requested = Number(args.page);
  const page = Number.isInteger(requested) && requested > 0 ? requested : 1;
  await sokujaEnsureBase();
  const url = `${sokujaActiveBase}/?s=${encodeURIComponent(query)}&page=${page}`;
  const response = await sokujaGet(url, { headers: sokujaHeaders(url) });
  if (response == null) return { sections: [] };
  const result = { sections: [{ id: 'sokuja-results', items: sokujaSearchResults(response.body).map(sokujaCatalogItem) }] };
  if (sokujaHasNextPage(response.body, '', page)) result.nextPage = String(page + 1);
  return result;
}

globalThis.__catalogProviders = globalThis.__catalogProviders || [];
globalThis.__catalogProviders.push({
  catalogId: SOKUJA_CATALOG_ID,
  catalog: sokujaCatalog,
});

globalThis.__metaProviders = globalThis.__metaProviders || [];
globalThis.__metaProviders.push({
  providerId: SOKUJA_PROVIDER_ID,
  meta: sokujaCatalogMeta,
});

globalThis.__sokujaCatalogActive = true;

globalThis.__extension = globalThis.__extension || {};
const sokujaPreviousSearch = globalThis.__extension.search;
globalThis.__extension.search = async (args) => {
  if (args && (args.category == null || args.category === SOKUJA_ANIME_CATEGORY)) {
    return sokujaSearch(args);
  }
  if (typeof sokujaPreviousSearch !== 'function') return { sections: [] };
  return sokujaPreviousSearch(args);
};

async function sokujaSources(args) {
  const enabled = args && args.enabledProviders;
  if (enabled != null && enabled.indexOf(SOKUJA_PROVIDER_ID) === -1) {
    return { sources: [] };
  }
  const item = args && args.item;
  if (!item || (item.kind !== 'episode' && item.kind !== 'video')) {
    return { sources: [] };
  }

  const query = sokujaItemQuery(item);
  if (!query.title) return { sources: [] };
  await sokujaEnsureBase();
  const availableAt = await sokujaEpisodeAvailableAt(item);
  const titleVariants = await sokujaItemTitleVariants(item, query.title);
  let found = null;
  for (const title of titleVariants) {
    found = await sokujaFindAnime(title, query.season, availableAt);
    if (found === SOKUJA_UNREACHABLE) {
      // A mirror that stops answering mid-session is the usual sign it rotated.
      // Re-run discovery once and retry, but only if it named a different host:
      // otherwise this is an outage and the second request buys nothing.
      const stale = sokujaActiveBase;
      sokujaForgetBase();
      const refreshed = await sokujaEnsureBase();
      found = refreshed === stale
        ? null
        : await sokujaFindAnime(title, query.season, availableAt);
    }
    if (found != null && found !== SOKUJA_UNREACHABLE) break;
  }
  if (found == null || found === SOKUJA_UNREACHABLE) return { sources: [] };
  const result = found.result;

  const detailBody = found.detailBody || (await sokujaGet(
    result.url,
    { headers: sokujaHeaders(`${sokujaActiveBase}/`) },
  ))?.body;
  if (detailBody == null) return { sources: [] };
  let watchUrl;
  if (!query.isEpisode) {
    watchUrl = sokujaMovieUrl(detailBody) || result.url;
  } else if (found.matchedByDate) {
    watchUrl = sokujaEpisodeUrl(
      detailBody,
      found.episodeNumber || query.episode,
      availableAt,
    );
  } else {
    watchUrl = await sokujaNumberedEpisodeUrl(item, query, detailBody);
  }
  if (watchUrl == null) return { sources: [] };

  const episodeResponse = await sokujaGet(
    watchUrl,
    { headers: sokujaHeaders(result.url) },
  );
  if (episodeResponse == null) return { sources: [] };
  const episodeId = sokujaEpisodeId(episodeResponse.body);
  if (episodeId == null) return { sources: [] };

  const mirrorsUrl = `${sokujaActiveBase}/api/video-mirrors/?e=${encodeURIComponent(episodeId)}`;
  const mirrorsResponse = await sokujaGet(
    mirrorsUrl,
    { headers: sokujaHeaders(watchUrl) },
  );
  if (mirrorsResponse == null) return { sources: [] };
  let mirrors;
  try {
    const data = JSON.parse(mirrorsResponse.body);
    mirrors = Array.isArray(data.mirrors) ? data.mirrors : [];
  } catch (_) {
    return { sources: [] };
  }

  const entries = sokujaMirrorEntries(mirrors);
  if (entries.length === 0) return {sources: []};
  return {
    sources: [{
      id: `${SOKUJA_PROVIDER_KEY}:${encodeSokujaSource({
        m: entries.map((entry) => ({u: entry.url, q: entry.quality})),
      })}`,
      label: 'Sokuja',
      provider: 'Nimora',
      providerId: SOKUJA_PROVIDER_ID,
    }],
  };
}

async function sokujaResolveSource(sourceId) {
  const prefix = `${SOKUJA_PROVIDER_KEY}:`;
  if (typeof sourceId !== 'string' || !sourceId.startsWith(prefix)) {
    throw new Error(`Invalid Sokuja sourceId: ${sourceId}`);
  }
  const payload = decodeSokujaSource(sourceId.slice(prefix.length));
  if (!payload) {
    throw new Error('Malformed Sokuja source id');
  }
  // Playback can resume from a stored source id in a session where nothing
  // searched Sokuja yet, so the Referer needs its own guarantee of a base.
  await sokujaEnsureBase();
  const entries = Array.isArray(payload.m)
    ? sokujaMirrorEntries(payload.m.map((entry) => ({
        embedUrl: entry && entry.u,
        quality: entry && entry.q,
      })))
    : sokujaMirrorEntries([{
        embedUrl: payload.u,
        quality: payload.q,
      }]);
  if (entries.length === 0) throw new Error('Malformed Sokuja source id');
  const headers = sokujaHeaders(`${sokujaActiveBase}/`);
  const variants = sokujaVariantEntries(entries, headers);
  const primary = variants.slice().sort((a, b) =>
    (a.height || Number.MAX_SAFE_INTEGER) -
    (b.height || Number.MAX_SAFE_INTEGER),
  )[0];
  return {
    url: primary.url,
    format: primary.format,
    headers: primary.headers,
    label: 'Sokuja',
    variants,
  };
}

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: SOKUJA_PROVIDER_KEY,
  sources: sokujaSources,
  resolve: (sourceId) => sokujaResolveSource(sourceId),
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
      (entry) => entry.providerKey === providerKey,
    );
    if (!provider) throw new Error(`No stream provider registered for "${providerKey}"`);
    return provider.resolve(sourceId);
  };
}
