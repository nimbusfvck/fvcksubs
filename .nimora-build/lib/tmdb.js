// TMDB + shegu.st curated-lists catalog, as a JS extension — Movies and TV.
//
// Talks to TMDB and lists.shegu.st directly. Items use stable
// `movie:<tmdbId>` / `series:<tmdbId>` references; see tmdbRefId below.
//
// Registers into `globalThis.__catalogProviders`/`__metaProviders` rather
// than assigning `__extension.catalog`/`__extension.meta` directly, so this
// can coexist with the fixtures catalog without either clobbering the other.
//
// Reuses `EXTENSION_ID` from fixtures.js (build_bundle.dart loads that first).

const TMDB_BASE = globalThis.__tmdbBaseUrl || 'https://api.themoviedb.org/3';
const TMDB_IMAGE_BASE = 'https://image.tmdb.org/t/p';
const SHEGU_LISTS_BASE = globalThis.__sheguListsBaseUrl || 'https://lists.shegu.st/joy';
const SHEGU_TRAILER_BASE = globalThis.__sheguTrailerBaseUrl || 'https://trailer.shegu.st';
const TMDB_API_KEY = '8476a7ab80ad76f0936744df0430e67c';

const TMDB_PROVIDER_ID = 'nimora.tmdb';
const TMDB_CATALOG_ID = 'discover';
const TMDB_MOVIE_CATEGORY = 'movie';
const TMDB_TV_CATEGORY = 'tv';
const TMDB_WATCH_REGION = globalThis.__tmdbWatchRegion || 'US';
// Popular Today follows TMDB's paid streaming tab. Rent and purchase offers
// are separate categories on TMDB and are intentionally not included here.
const TMDB_STREAMING_TYPES = 'flatrate';
const TMDB_LEAKS_BASE = globalThis.__flystreamBaseUrl || 'https://flystream.net';
const TMDB_LEAKS_TTL_MS = 15 * 60 * 1000;
const SHEGU_TRAILER_TIMEOUT_MS = 1500;

let tmdbLeaksMemo = null;
const tmdbTitleLogoMemo = new Map();
const TMDB_TITLE_LOGO_CONCURRENCY = 4;

// --- fetch helpers ---

function tmdbUrl(path, query) {
  const params = Object.entries({ api_key: TMDB_API_KEY, language: 'en-US', ...query })
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
  return `${TMDB_BASE}${path}?${params}`;
}

async function tmdbGetJson(path, query) {
  const response = await fetch(tmdbUrl(path, query));
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Request to ${path} failed: ${response.status}`);
  }
  return JSON.parse(response.body);
}

// FlyStream's leak feed is metadata enrichment, not a playback source. Keep
// the fetch behind the existing FlyStream cookie/gate when the bundle has
// loaded flystream.js, and keep a direct fallback for isolated unit tests.
async function tmdbFetchLeaks() {
  const url = `${TMDB_LEAKS_BASE}/api/leaks`;
  if (typeof flystreamRequestJson === 'function') {
    return flystreamRequestJson(url);
  }
  try {
    const response = await fetch(url, {
      headers: { Accept: 'application/json' },
    });
    if (response.status < 200 || response.status >= 300) return null;
    return JSON.parse(response.body);
  } catch (_) {
    return null;
  }
}

const TMDB_MONTHS = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

function tmdbDigitalDateFromBody(body, year) {
  if (typeof body !== 'string' || !Number.isInteger(year)) return null;
  const match = /\bon\s+digital\s+([a-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?\b/i.exec(body);
  if (match == null) return null;
  const month = TMDB_MONTHS.findIndex(
    (value) => value.toLowerCase() === match[1].toLowerCase(),
  );
  const day = Number(match[2]);
  if (month < 0 || day < 1 || day > 31) return null;
  const date = new Date(Date.UTC(year, month, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month ||
    date.getUTCDate() !== day
  ) {
    return null;
  }
  return {
    iso: `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`,
    display: `${TMDB_MONTHS[month]} ${day}, ${year}`,
  };
}

function tmdbLeakKey(mediaType, tmdbId) {
  return `${mediaType}:${tmdbId}`;
}

function tmdbLeakIndexFromResponse(data) {
  if (data == null || !Array.isArray(data.items)) return null;
  const index = new Map();
  for (const entry of data.items) {
    if (entry == null || typeof entry !== 'object') continue;
    const mediaType = entry.mediaType === 'movie' || entry.mediaType === 'tv'
      ? entry.mediaType
      : null;
    const tmdbId = Number(entry.tmdbId);
    if (mediaType == null || !Number.isInteger(tmdbId) || tmdbId < 1) continue;
    const key = tmdbLeakKey(mediaType, tmdbId);
    const status = index.get(key) || {
      onDigital: false,
      leak: false,
      digitalDate: null,
    };
    const kind = typeof entry.kind === 'string' ? entry.kind.toLowerCase() : '';
    if (kind === 'digital') status.onDigital = true;
    if (kind === 'leak') status.leak = true;
    if (kind === 'upcoming') {
      const year = Number(entry.year);
      const date = tmdbDigitalDateFromBody(entry.body, year);
      if (
        date != null &&
        (status.digitalDate == null || date.iso < status.digitalDate.iso)
      ) {
        status.digitalDate = date;
      }
    }
    index.set(key, status);
  }
  return index;
}

function tmdbLeakIndex() {
  const now = Date.now();
  if (
    tmdbLeaksMemo != null &&
    now - tmdbLeaksMemo.fetchedAt < TMDB_LEAKS_TTL_MS
  ) {
    return tmdbLeaksMemo.promise;
  }
  const promise = tmdbFetchLeaks()
    .then(tmdbLeakIndexFromResponse)
    .catch(() => null);
  tmdbLeaksMemo = { fetchedAt: now, promise };
  return promise;
}

async function tmdbLeakMetadata(tmdbId, mediaType) {
  const index = await tmdbLeakIndex();
  return index == null ? null : index.get(tmdbLeakKey(mediaType, tmdbId)) || null;
}

function tmdbApplyLeakMetadata(detail, metadata) {
  if (metadata == null) return detail;
  const tags = Array.isArray(detail.tags) ? detail.tags.slice() : [];
  if (metadata.onDigital && !tags.includes('On Digital')) tags.push('On Digital');
  if (metadata.leak && !tags.includes('Leak')) tags.push('Leak');
  if (tags.length > 0) detail.tags = tags;
  if (metadata.digitalDate != null) {
    const facts = Array.isArray(detail.facts) ? detail.facts.slice() : [];
    if (!facts.some((fact) => fact && fact.label === 'Digital release')) {
      facts.push({ label: 'Digital release', value: metadata.digitalDate.display });
    }
    detail.facts = facts;
  }
  return detail;
}

async function sheguGetJson(slug, limit) {
  const url = `${SHEGU_LISTS_BASE}/${slug}?limit=${limit}`;
  const response = await fetch(url);
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Request to ${slug} failed: ${response.status}`);
  }
  return JSON.parse(response.body);
}

function sheguVideoTrailerFromResponse(data) {
  if (data == null || typeof data !== 'object') return null;
  const url = typeof data.url === 'string' ? data.url.trim() : '';
  const mimeType = typeof data.mime === 'string' ? data.mime.trim() : '';
  if ((!url.startsWith('http://') && !url.startsWith('https://')) ||
      !mimeType.toLowerCase().startsWith('video/')) return null;
  return {
    title: 'Trailer',
    url,
    site: data.source || null,
    mimeType,
  };
}

async function sheguVideoTrailer(tmdbId, type) {
  let timeoutHandle = null;
  try {
    const url = `${SHEGU_TRAILER_BASE}/trailer?tmdb=${encodeURIComponent(tmdbId)}&type=${encodeURIComponent(type)}`;
    // This is optional detail enrichment. Shegu is Cloudflare-fronted, and a
    // 503 from its unavailable upstream must not be misclassified by the
    // generic host detector as a browser challenge. The private header is
    // consumed by the JS host and is never sent to Shegu; a slow/outage
    // response is bounded as well.
    const request = fetch(url, {
      headers: { 'x-qjsr-disable-cloudflare': '1' },
    });
    const response = await Promise.race([
      request,
      new Promise((resolve) => {
        timeoutHandle = setTimeout(() => resolve(null), SHEGU_TRAILER_TIMEOUT_MS);
      }),
    ]);
    if (timeoutHandle != null) clearTimeout(timeoutHandle);
    if (response == null) return null;
    if (response.status < 200 || response.status >= 300) return null;
    return sheguVideoTrailerFromResponse(JSON.parse(response.body));
  } catch (_) {
    if (timeoutHandle != null) clearTimeout(timeoutHandle);
    // Trailer previews are optional; a provider outage must not hide metadata.
    return null;
  }
}

function sheguPreviewWithThumbnail(preview, trailers) {
  if (preview == null) return null;
  const thumbnail = trailers.find((trailer) => trailer.thumbnail)?.thumbnail;
  return thumbnail == null ? preview : { ...preview, thumbnail };
}

// --- ref id ---

function tmdbRefId(mediaType, id) {
  return `${mediaType === 'movie' ? 'movie' : 'series'}:${id}`;
}

function parseTmdbRef(refId) {
  if (typeof refId !== 'string') return null;
  const separator = refId.indexOf(':');
  if (separator < 0) return null;
  const kind = refId.slice(0, separator);
  const tmdbId = refId.slice(separator + 1);
  if ((kind !== 'movie' && kind !== 'series') || tmdbId.length === 0) {
    return null;
  }
  return { kind, tmdbId };
}

// --- mapping ---

// Works for both a search-result-shaped object (trending/top_rated/discover
// `results[]`) and a detail-shaped one (`/movie/{id}`, `/tv/{id}`) — the
// fields this reads are the same in both.
function tmdbToMediaItem(result, mediaType) {
  const kind = mediaType === 'movie' ? 'video' : 'series';
  const title = result.title || result.name || 'Untitled';
  const dateStr = result.release_date || result.first_air_date;
  const releaseYear = dateStr ? parseInt(dateStr.slice(0, 4), 10) : null;
  const rating =
    typeof result.vote_average === 'number' && result.vote_average > 0
      ? result.vote_average
      : null;
  const mediaItem = {
    ref: {
      extensionId: EXTENSION_ID,
      providerId: TMDB_PROVIDER_ID,
      id: tmdbRefId(mediaType, result.id),
    },
    kind,
    title,
    tags: [mediaType === 'movie' ? 'movie' : 'tv'],
  };
  if (Number.isInteger(releaseYear) && releaseYear > 0) {
    mediaItem.releaseYear = releaseYear;
  }
  const releaseDate = tmdbReleaseDateIso(dateStr);
  if (releaseDate) mediaItem.releaseDate = releaseDate;
  if (rating != null) mediaItem.rating = rating;
  const artwork = {};
  if (result.poster_path) artwork.portrait = { url: `${TMDB_IMAGE_BASE}/w500${result.poster_path}` };
  if (result.backdrop_path) artwork.landscape = { url: `${TMDB_IMAGE_BASE}/w780${result.backdrop_path}` };
  const titleLogo = tmdbTitleLogo(result.images);
  if (titleLogo) artwork.logo = { url: `${TMDB_IMAGE_BASE}/w300${titleLogo.file_path}` };
  if (Object.keys(artwork).length > 0) mediaItem.artwork = artwork;
  return mediaItem;
}

// TMDB dates are plain calendar days (no timezone); the app requires a full
// ISO-8601 UTC instant, so anchor them at midnight UTC.
function tmdbReleaseDateIso(dateStr) {
  if (typeof dateStr !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) return null;
  return `${dateStr}T00:00:00Z`;
}

// TMDB returns logos in popularity order. Prefer an English title treatment,
// then an untagged one that can work across locales.
function tmdbTitleLogo(images) {
  const logos = images && Array.isArray(images.logos) ? images.logos : [];
  return logos.find((logo) => logo.file_path && logo.iso_639_1 === 'en')
    || logos.find((logo) => logo.file_path && logo.iso_639_1 == null)
    || null;
}

function tmdbTitleLogoRequest(mediaType, tmdbId) {
  const key = `${mediaType}:${tmdbId}`;
  const existing = tmdbTitleLogoMemo.get(key);
  if (existing != null) return existing;
  const request = tmdbGetJson(`/${mediaType}/${tmdbId}/images`, {
    include_image_language: 'en,null',
  })
    .then(tmdbTitleLogo)
    .catch(() => null);
  tmdbTitleLogoMemo.set(key, request);
  return request;
}

async function enrichTrendingTitleLogos(results, items, mediaType) {
  let nextIndex = 0;
  const worker = async () => {
    while (nextIndex < results.length) {
      const index = nextIndex++;
      const result = results[index];
      if (result == null || result.id == null) continue;
      const logo = await tmdbTitleLogoRequest(mediaType, result.id);
      if (logo == null) continue;
      items[index].artwork = {
        ...(items[index].artwork || {}),
        logo: { url: `${TMDB_IMAGE_BASE}/w300${logo.file_path}` },
      };
    }
  };
  const workerCount = Math.min(TMDB_TITLE_LOGO_CONCURRENCY, results.length);
  await Promise.all(Array.from({ length: workerCount }, () => worker()));
  return items;
}

function tmdbTrailerUrl(video) {
  const site = String(video.site || '').toLowerCase();
  const key = String(video.key || '').trim();
  if (key.length === 0) return null;
  if (site === 'youtube') {
    return `https://www.youtube.com/watch?v=${encodeURIComponent(key)}`;
  }
  if (site === 'vimeo') return `https://vimeo.com/${encodeURIComponent(key)}`;
  return null;
}

// Keep only preview videos the app can open externally. Official trailers are
// preferred, then teasers, while the upstream publication date breaks ties.
function tmdbTrailers(data) {
  const videos = data && data.videos && Array.isArray(data.videos.results)
    ? data.videos.results
    : [];
  const typeRank = { Trailer: 0, Teaser: 1, Clip: 2, Featurette: 3 };
  return videos
    .map((video, index) => ({ video, index, url: tmdbTrailerUrl(video) }))
    .filter(({ video, url }) =>
      url != null && Object.prototype.hasOwnProperty.call(typeRank, video.type),
    )
    .sort((a, b) => {
      const aOfficial = a.video.official === true ? 0 : 1;
      const bOfficial = b.video.official === true ? 0 : 1;
      if (aOfficial !== bOfficial) return aOfficial - bOfficial;
      const aType = typeRank[a.video.type];
      const bType = typeRank[b.video.type];
      if (aType !== bType) return aType - bType;
      const aDate = Date.parse(a.video.published_at || '') || 0;
      const bDate = Date.parse(b.video.published_at || '') || 0;
      if (aDate !== bDate) return bDate - aDate;
      return a.index - b.index;
    })
    .slice(0, 3)
    .map(({ video, url }) => ({
      title: video.name || video.type || 'Trailer',
      url,
      site: video.site,
      ...(String(video.site || '').toLowerCase() === 'youtube' && video.key
        ? { thumbnail: { url: `https://img.youtube.com/vi/${encodeURIComponent(video.key)}/mqdefault.jpg` } }
        : {}),
    }));
}

// shegu.st's own `ratings.tmdb` is `{value, votes, scale, url}`. Normalize
// it to the 0–10 scale used by the TMDB catalog before exposing it as rating.
function sheguRating(item) {
  const tmdbRating = item.ratings && item.ratings.tmdb;
  if (tmdbRating == null || typeof tmdbRating.value !== 'number') return null;
  const scale =
    typeof tmdbRating.scale === 'number' && tmdbRating.scale > 0 ? tmdbRating.scale : 100;
  const normalized = (tmdbRating.value / scale) * 10;
  return normalized > 0 ? Math.round(normalized * 10) / 10 : null;
}

// shegu.st's `/joy/<slug>` lists (oscar-nominees-best-picture,
// cannes-film-festival) are movie-only, and `poster` is already a full
// image.tmdb.org URL (confirmed against the live API) — unlike TMDB's own
// bare `poster_path`.
function sheguToMediaItem(item, group) {
  if (item.type !== 'movie') return null;
  const tmdbId = item.ids && item.ids.tmdb;
  if (tmdbId == null) return null;
  const mediaItem = {
    ref: {
      extensionId: EXTENSION_ID,
      providerId: TMDB_PROVIDER_ID,
      id: tmdbRefId('movie', tmdbId),
    },
    kind: 'video',
    title: item.title || 'Untitled',
    tags: ['movie'],
  };
  const releaseYear = Number(item.year);
  const rating = sheguRating(item);
  if (Number.isInteger(releaseYear) && releaseYear > 0) {
    mediaItem.releaseYear = releaseYear;
  }
  if (rating != null) mediaItem.rating = rating;
  if (item.poster) mediaItem.artwork = { portrait: { url: item.poster } };
  return mediaItem;
}

// --- section fetches (each returns MediaItems with no group set yet —
// fetchGroup below tags them) ---

// TMDB has no anime genre, so Japanese animation is the closest honest test:
// genre 16 plus a Japanese origin. Both signals are required — genre 16 alone
// sweeps up Western cartoons, and Japanese origin alone sweeps up live action.
function tmdbIsAnime(result) {
  const genres = Array.isArray(result && result.genre_ids) ? result.genre_ids : [];
  if (genres.indexOf(16) === -1) return false;
  const origin = Array.isArray(result.origin_country) ? result.origin_country : [];
  return result.original_language === 'ja' || origin.indexOf('JP') !== -1;
}

async function fetchTrending(mediaType) {
  const data = await tmdbGetJson(`/trending/${mediaType}/day`, { include_adult: 'false' });
  // Anime has its own row now, from a database that counts cours the way the
  // streaming sites do. Leaving it here as well would put the same title on
  // Home twice, under two ids that resolve through different providers.
  const results = (Array.isArray(data.results) ? data.results : [])
    .filter((result) => !tmdbIsAnime(result));
  const items = results.map((r) => tmdbToMediaItem(r, mediaType));
  if (results.length === 0) return items;

  // Every Trending item can become a Home hero candidate. Keep the fan-out
  // bounded and memoized so repeated catalog reads do not create an
  // unbounded burst of TMDB requests.
  return enrichTrendingTitleLogos(results, items, mediaType);
}

// A future-dated result isn't guaranteed to actually be one — TMDB's flat
// `release_date`/`first_air_date` field can carry a stale, long-past date
// (region rerelease quirks and the like) even when a feed calls the title
// "upcoming". Trust our own read of that date, not the endpoint's label.
function tmdbIsNotYetReleased(item) {
  return typeof item.releaseDate === 'string' && Date.parse(item.releaseDate) > Date.now();
}

// TMDB's own `/movie/upcoming` only covers the near-term theatrical window
// (the next month or two) and misses tentpoles releasing further out — a
// Dune or Avengers sequel a year away won't be in it. Discover every title
// with a future primary release date instead. Popularity, kept alongside
// each item rather than baked into the API's own ordering, is what
// `fetchComingSoon` below uses to pick winners once movies and TV are merged
// — sorting this single list by release date and cutting it to 25 would
// otherwise let a page of near-term small releases bury a tentpole that's
// simply further out (this happened: Dune/Avengers sequels dropped off).
async function fetchUpcomingMovies() {
  const today = new Date().toISOString().slice(0, 10);
  const data = await tmdbGetJson('/discover/movie', {
    page: 1,
    include_adult: 'false',
    'primary_release_date.gte': today,
    sort_by: 'popularity.desc',
  });
  const results = (Array.isArray(data.results) ? data.results : [])
    .filter((result) => !tmdbIsAnime(result));
  return results
    .map((r) => ({ item: tmdbToMediaItem(r, 'movie'), popularity: typeof r.popularity === 'number' ? r.popularity : 0 }))
    .filter((entry) => tmdbIsNotYetReleased(entry.item));
}

// TMDB has no dedicated "upcoming" endpoint for TV at all — discover series
// whose first air date hasn't happened yet, same popularity ranking as movies.
async function fetchUpcomingTv() {
  const today = new Date().toISOString().slice(0, 10);
  const data = await tmdbGetJson('/discover/tv', {
    page: 1,
    include_adult: 'false',
    'first_air_date.gte': today,
    sort_by: 'popularity.desc',
  });
  const results = (Array.isArray(data.results) ? data.results : [])
    .filter((result) => !tmdbIsAnime(result));
  return results
    .map((r) => ({ item: tmdbToMediaItem(r, 'tv'), popularity: typeof r.popularity === 'number' ? r.popularity : 0 }))
    .filter((entry) => tmdbIsNotYetReleased(entry.item));
}

// Movie and TV releases not out yet, combined into one shelf and ranked by
// popularity — not by how soon each one releases. A tentpole several months
// out (Dune, an Avengers sequel) is exactly the kind of title this shelf
// should lead with; sorting by nearest date instead buries it under an
// entire page of small/indie titles that just happen to release sooner.
async function fetchComingSoon() {
  const [movies, series] = await Promise.all([
    fetchUpcomingMovies().catch(() => []),
    fetchUpcomingTv().catch(() => []),
  ]);
  return [...movies, ...series]
    .sort((a, b) => b.popularity - a.popularity)
    .slice(0, 25)
    .map((entry) => entry.item);
}

function tmdbRequestedPage(page) {
  const parsed = Number(page);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : 1;
}

async function fetchTopRatedPage(mediaType, page) {
  const requestedPage = tmdbRequestedPage(page);
  const data = await tmdbGetJson(`/${mediaType}/top_rated`, {
    page: requestedPage,
    include_adult: 'false',
  });
  const results = Array.isArray(data.results) ? data.results : [];
  return {
    items: results.map((r) => tmdbToMediaItem(r, mediaType)),
    page: typeof data.page === 'number' ? data.page : requestedPage,
    totalPages: typeof data.total_pages === 'number' ? data.total_pages : requestedPage,
  };
}

async function fetchTopRated(mediaType) {
  const page = await fetchTopRatedPage(mediaType, 1);
  return page.items;
}

async function fetchPopularPage(mediaType, page) {
  const requestedPage = tmdbRequestedPage(page);
  const data = await tmdbGetJson(`/${mediaType}/popular`, {
    page: requestedPage,
    include_adult: 'false',
  });
  const results = Array.isArray(data.results) ? data.results : [];
  return {
    items: results.map((r) => tmdbToMediaItem(r, mediaType)),
    page: typeof data.page === 'number' ? data.page : requestedPage,
    totalPages: typeof data.total_pages === 'number' ? data.total_pages : requestedPage,
  };
}

async function fetchPopular(mediaType) {
  const page = await fetchPopularPage(mediaType, 1);
  return page.items;
}

// TMDB does not expose a dedicated "popular by country" list. Keep the
// country-specific values in data so adding another country only needs one
// entry here. Shelf titles intentionally follow `Popular <Country> Series &
// Movies`, which the app can match with /^Popular (.+) Series & Movies$/i.
const POPULAR_COUNTRY_SHELVES = [
  { id: 'korean', label: 'Korean', originCountry: 'KR', originalLanguage: 'ko' },
  { id: 'indonesian', label: 'Indonesian', originCountry: 'ID', originalLanguage: 'id' },
];

function popularCountryTitle(country) {
  return `Popular ${country.label} Series & Movies`;
}

async function fetchPopularCountryMediaTypePage(country, mediaType, page) {
  const requestedPage = tmdbRequestedPage(page);
  const data = await tmdbGetJson(`/discover/${mediaType}`, {
    page: requestedPage,
    include_adult: 'false',
    with_origin_country: country.originCountry,
    with_original_language: country.originalLanguage,
    sort_by: 'popularity.desc',
    'vote_count.gte': 5,
  });
  const results = Array.isArray(data.results) ? data.results : [];
  return {
    entries: results.map((result) => ({
      item: tmdbToMediaItem(result, mediaType),
      popularity: typeof result.popularity === 'number' ? result.popularity : 0,
      voteCount: typeof result.vote_count === 'number' ? result.vote_count : 0,
    })),
    page: typeof data.page === 'number' ? data.page : requestedPage,
    totalPages: typeof data.total_pages === 'number' ? data.total_pages : requestedPage,
  };
}

async function fetchPopularCountryMediaType(country, mediaType) {
  const page = await fetchPopularCountryMediaTypePage(country, mediaType, 1);
  return page.entries;
}

function popularCountryItems(movies, series) {
  return [...movies, ...series]
    .sort((a, b) => b.popularity - a.popularity || b.voteCount - a.voteCount)
    .slice(0, 25)
    .map((entry) => entry.item);
}

async function fetchPopularCountryPage(country, page) {
  const requestedPage = tmdbRequestedPage(page);
  const [movies, series] = await Promise.all([
    fetchPopularCountryMediaTypePage(country, 'movie', requestedPage),
    fetchPopularCountryMediaTypePage(country, 'tv', requestedPage),
  ]);
  const nextPage = movies.page < movies.totalPages || series.page < series.totalPages
    ? String(requestedPage + 1)
    : null;
  return {
    items: popularCountryItems(movies.entries, series.entries),
    nextPage,
  };
}

async function fetchPopularCountry(country) {
  const page = await fetchPopularCountryPage(country, 1);
  return page.items;
}

async function fetchSheguList(slug) {
  const data = await sheguGetJson(slug, 25);
  const items = Array.isArray(data.items) ? data.items : [];
  return items.map((item) => sheguToMediaItem(item, null)).filter((item) => item != null);
}

async function fetchDiscoverPage(mediaType, extraParams, page) {
  const data = await tmdbGetJson(`/discover/${mediaType}`, {
    include_adult: 'false',
    watch_region: 'US',
    sort_by: 'popularity.desc',
    page,
    ...extraParams,
  });
  const results = Array.isArray(data.results) ? data.results : [];
  return {
    items: results.map((r) => tmdbToMediaItem(r, mediaType, null)),
    page: typeof data.page === 'number' ? data.page : page,
    totalPages: typeof data.total_pages === 'number' ? data.total_pages : page,
  };
}

async function fetchDiscover(mediaType, page) {
  return fetchDiscoverPage(mediaType, {}, page);
}

// Keep the genre set deliberately small. Each entry becomes one horizontal
// row, and a category page should not fan out to every genre TMDB exposes.
const TOP_BY_GENRE = {
  movie: [
    { id: 'action', name: 'Action', tmdbId: 28, minimumVotes: 200 },
    { id: 'comedy', name: 'Comedy', tmdbId: 35, minimumVotes: 200 },
    { id: 'drama', name: 'Drama', tmdbId: 18, minimumVotes: 200 },
    { id: 'horror', name: 'Horror', tmdbId: 27, minimumVotes: 200 },
    { id: 'science_fiction', name: 'Sci-Fi', tmdbId: 878, minimumVotes: 200 },
  ],
  tv: [
    { id: 'action_adventure', name: 'Action & Adventure', tmdbId: 10759, minimumVotes: 100 },
    { id: 'comedy', name: 'Comedy', tmdbId: 35, minimumVotes: 100 },
    { id: 'crime', name: 'Crime', tmdbId: 80, minimumVotes: 100 },
    { id: 'drama', name: 'Drama', tmdbId: 18, minimumVotes: 100 },
    { id: 'science_fiction_fantasy', name: 'Sci-Fi & Fantasy', tmdbId: 10765, minimumVotes: 100 },
  ],
};

async function fetchTopByGenrePage(mediaType, genre, page) {
  return fetchDiscoverPage(mediaType, {
    with_genres: genre.tmdbId,
    sort_by: 'vote_average.desc',
    'vote_count.gte': genre.minimumVotes,
  }, page);
}

async function fetchTopByGenre(mediaType, genre) {
  const page = await fetchTopByGenrePage(mediaType, genre, 1);
  return page.items;
}

function topByGenreGroups(mediaType) {
  const genres = TOP_BY_GENRE[mediaType] || [];
  return genres.map((genre) => ({
    id: `top_by_genre_${mediaType}_${genre.id}`,
    name: `Top By Genre · ${genre.name}`,
    fetch: () => fetchTopByGenre(mediaType, genre),
    fetchPage: async (page) => {
      const result = await fetchTopByGenrePage(mediaType, genre, page);
      return {
        items: result.items,
        nextPage: result.page < result.totalPages ? String(result.page + 1) : null,
      };
    },
  }));
}

async function fetchPopularStreamingMediaTypePage(mediaType, page) {
  try {
    const requestedPage = tmdbRequestedPage(page);
    const data = await tmdbGetJson(`/discover/${mediaType}`, {
      include_adult: 'false',
      watch_region: TMDB_WATCH_REGION,
      with_watch_monetization_types: TMDB_STREAMING_TYPES,
      sort_by: 'popularity.desc',
      page: requestedPage,
    });
    const results = Array.isArray(data.results) ? data.results : [];
    return {
      entries: results.map((result) => ({
        item: tmdbToMediaItem(result, mediaType),
        popularity: typeof result.popularity === 'number' ? result.popularity : 0,
      })),
      page: typeof data.page === 'number' ? data.page : requestedPage,
      totalPages: typeof data.total_pages === 'number' ? data.total_pages : requestedPage,
    };
  } catch (_) {
    return { entries: [], page: 1, totalPages: 1 };
  }
}

async function fetchPopularStreamingMediaType(mediaType) {
  const page = await fetchPopularStreamingMediaTypePage(mediaType, 1);
  return page.entries;
}

// Combine paid movie and TV streaming results into one shelf. The public API
// exposes the availability filter, while the website's private panel owns its
// own ranking and may therefore show a different order.
async function fetchPopularStreaming() {
  const page = await fetchPopularStreamingPage(1);
  return page.items;
}

async function fetchPopularStreamingPage(page) {
  const requestedPage = tmdbRequestedPage(page);
  const [movies, tv] = await Promise.all([
    fetchPopularStreamingMediaTypePage('movie', requestedPage),
    fetchPopularStreamingMediaTypePage('tv', requestedPage),
  ]);
  const items = [...movies.entries, ...tv.entries]
    .sort((a, b) => b.popularity - a.popularity)
    .slice(0, 25)
    .map((entry) => entry.item);
  const nextPage = movies.page < movies.totalPages || tv.page < tv.totalPages
    ? String(requestedPage + 1)
    : null;
  return { items, nextPage };
}

// TMDB's `watch_providers` catalog ids — stable across regions, used with
// `with_watch_providers` to narrow discover to one streamer's US catalog.
const WATCH_PROVIDER = {
  netflix: 8,
  hulu: 15,
  disneyPlus: 337,
  primeVideo: 9,
  hbo: 1899,
  appleTv: 350,
};

async function fetchWatchProvider(mediaType, providerId) {
  const page = await fetchDiscoverPage(mediaType, { with_watch_providers: providerId }, 1);
  return page.items;
}

async function fetchWatchProviderPage(mediaType, providerId, page) {
  const discover = await fetchDiscoverPage(
    mediaType,
    { with_watch_providers: providerId },
    tmdbRequestedPage(page),
  );
  return {
    items: discover.items,
    nextPage: discover.page < discover.totalPages ? String(discover.page + 1) : null,
  };
}

// Try/catch wrapper so one upstream outage drops just its own section
// instead of failing the whole shelf.
async function fetchGroup(label, fetchFn) {
  try {
    const items = await fetchFn();
  return items;
  } catch (e) {
    return [];
  }
}

async function fetchGroupPage(label, fetchFn, page) {
  try {
    const result = await fetchFn(page);
    return result && Array.isArray(result.items) ? result : { items: [] };
  } catch (e) {
    return { items: [] };
  }
}

// --- "highlights" catalog: horizontal-row sections. The `all` category is
// mixed; movie and tv reuse the same catalog with only their own sections.
// Separate from the `movie`/`tv` grid catalog below: same provider, second
// catalog, own catalogId, so it can keep `display: "row"` while the other
// one is `"grid"` (CatalogDecl.display is one value per catalog, not per
// category — see manifest.json).

const HIGHLIGHTS_CATALOG_ID = 'highlights';
const TMDB_ALL_CATEGORY = 'all';

async function fetchTimesoccerHighlights() {
  const loader = globalThis.__timesoccerHighlightPage;
  if (typeof loader !== 'function') return [];
  try {
    const page = await loader(null);
    return page && Array.isArray(page.items) ? page.items : [];
  } catch (_) {
    return [];
  }
}

async function fetchTimesoccerHighlightsPage(page) {
  const loader = globalThis.__timesoccerHighlightPage;
  if (typeof loader !== 'function') return { items: [] };
  try {
    const result = await loader(page);
    return result && Array.isArray(result.items) ? result : { items: [] };
  } catch (_) {
    return { items: [] };
  }
}

async function fetchLayarKacaHighlight(category) {
  const page = await fetchLayarKacaHighlightPage(category, null);
  return page.items;
}

async function fetchLayarKacaHighlightPage(category, page) {
  const loader = globalThis.__layarkacaHighlightPage;
  if (typeof loader !== 'function') return {items: []};
  try {
    const result = await loader(category, page);
    return result && Array.isArray(result.items) ? result : {items: []};
  } catch (_) {
    return {items: []};
  }
}

async function fetchSokujaAnimeRanking(rank) {
  const loader = globalThis.__sokujaAnimeRankingItems;
  if (typeof loader !== 'function') return [];
  try {
    const items = await loader(rank);
    return Array.isArray(items) ? items : [];
  } catch (_) {
    return [];
  }
}

const HIGHLIGHT_GROUPS = [
  { id: 'trending_movie', name: 'Trending Movie', fetch: () => fetchTrending('movie') },
  { id: 'trending_tv', name: 'Trending TV', fetch: () => fetchTrending('tv') },
  {
    id: 'popular_today',
    name: 'Popular Today',
    fetch: fetchPopularStreaming,
    fetchPage: fetchPopularStreamingPage,
  },
  { id: 'football_highlights', name: 'Football Highlights', fetch: fetchTimesoccerHighlights },
  { id: 'coming_soon', name: 'Coming Soon', fetch: () => fetchComingSoon() },
  {
    id: 'top_anime_all_time',
    name: 'Top Anime All Time',
    fetch: () => fetchSokujaAnimeRanking('all'),
  },
  {
    id: 'popular_anime_week',
    name: 'Popular Anime This Week',
    fetch: () => fetchSokujaAnimeRanking('weekly'),
  },
  {
    id: 'top_rated_movie',
    name: 'Top Rated Movie',
    fetch: () => fetchTopRated('movie'),
    fetchPage: async (page) => {
      const result = await fetchTopRatedPage('movie', page);
      return {
        items: result.items,
        nextPage: result.page < result.totalPages ? String(result.page + 1) : null,
      };
    },
  },
  {
    id: 'top_rated_tv',
    name: 'Top Rated TV',
    fetch: () => fetchTopRated('tv'),
    fetchPage: async (page) => {
      const result = await fetchTopRatedPage('tv', page);
      return {
        items: result.items,
        nextPage: result.page < result.totalPages ? String(result.page + 1) : null,
      };
    },
  },
  {
    id: 'popular_movie_all_time',
    name: 'Popular Movies',
    fetch: () => fetchPopular('movie'),
    fetchPage: async (page) => {
      const result = await fetchPopularPage('movie', page);
      return {
        items: result.items,
        nextPage: result.page < result.totalPages ? String(result.page + 1) : null,
      };
    },
  },
  {
    id: 'popular_tv_all_time',
    name: 'Popular TV Series',
    fetch: () => fetchPopular('tv'),
    fetchPage: async (page) => {
      const result = await fetchPopularPage('tv', page);
      return {
        items: result.items,
        nextPage: result.page < result.totalPages ? String(result.page + 1) : null,
      };
    },
  },
  {
    id: 'netflix_movies',
    name: 'Movies on Netflix',
    fetch: () => fetchWatchProvider('movie', WATCH_PROVIDER.netflix),
    fetchPage: (page) => fetchWatchProviderPage('movie', WATCH_PROVIDER.netflix, page),
  },
  {
    id: 'hulu_movies',
    name: 'Movies on Hulu',
    fetch: () => fetchWatchProvider('movie', WATCH_PROVIDER.hulu),
    fetchPage: (page) => fetchWatchProviderPage('movie', WATCH_PROVIDER.hulu, page),
  },
  {
    id: 'disney_movies',
    name: 'Movies on Disney+',
    fetch: () => fetchWatchProvider('movie', WATCH_PROVIDER.disneyPlus),
    fetchPage: (page) => fetchWatchProviderPage('movie', WATCH_PROVIDER.disneyPlus, page),
  },
  {
    id: 'prime_movies',
    name: 'Movies on Prime Video',
    fetch: () => fetchWatchProvider('movie', WATCH_PROVIDER.primeVideo),
    fetchPage: (page) => fetchWatchProviderPage('movie', WATCH_PROVIDER.primeVideo, page),
  },
  {
    id: 'hbo_movies',
    name: 'Movies on HBO',
    fetch: () => fetchWatchProvider('movie', WATCH_PROVIDER.hbo),
    fetchPage: (page) => fetchWatchProviderPage('movie', WATCH_PROVIDER.hbo, page),
  },
  {
    id: 'appletv_movies',
    name: 'Movies on Apple TV',
    fetch: () => fetchWatchProvider('movie', WATCH_PROVIDER.appleTv),
    fetchPage: (page) => fetchWatchProviderPage('movie', WATCH_PROVIDER.appleTv, page),
  },
  {
    id: 'netflix_tv',
    name: 'TV Series on Netflix',
    fetch: () => fetchWatchProvider('tv', WATCH_PROVIDER.netflix),
    fetchPage: (page) => fetchWatchProviderPage('tv', WATCH_PROVIDER.netflix, page),
  },
  {
    id: 'disney_tv',
    name: 'TV Series on Disney+',
    fetch: () => fetchWatchProvider('tv', WATCH_PROVIDER.disneyPlus),
    fetchPage: (page) => fetchWatchProviderPage('tv', WATCH_PROVIDER.disneyPlus, page),
  },
  {
    id: 'appletv_tv',
    name: 'TV Series on Apple TV',
    fetch: () => fetchWatchProvider('tv', WATCH_PROVIDER.appleTv),
    fetchPage: (page) => fetchWatchProviderPage('tv', WATCH_PROVIDER.appleTv, page),
  },
  {
    id: 'prime_tv',
    name: 'TV Series on Prime',
    fetch: () => fetchWatchProvider('tv', WATCH_PROVIDER.primeVideo),
    fetchPage: (page) => fetchWatchProviderPage('tv', WATCH_PROVIDER.primeVideo, page),
  },
  {
    id: 'hbo_tv',
    name: 'TV Series on HBO',
    fetch: () => fetchWatchProvider('tv', WATCH_PROVIDER.hbo),
    fetchPage: (page) => fetchWatchProviderPage('tv', WATCH_PROVIDER.hbo, page),
  },
  {
    id: 'layarkaca_movies',
    name: 'Movies on LK21',
    fetch: () => fetchLayarKacaHighlight('movie'),
    fetchPage: (page) => fetchLayarKacaHighlightPage('movie', page),
  },
  {
    id: 'layarkaca_tv',
    name: 'TV Series on LK21',
    fetch: () => fetchLayarKacaHighlight('tv'),
    fetchPage: (page) => fetchLayarKacaHighlightPage('tv', page),
  },
  ...POPULAR_COUNTRY_SHELVES.map((country) => ({
    id: `popular_${country.id}`,
    name: popularCountryTitle(country),
    fetch: () => fetchPopularCountry(country),
    fetchPage: (page) => fetchPopularCountryPage(country, page),
  })),
  { id: 'rotten_tomatoes_best', name: 'Rotten Tomatoes Best of All Time', fetch: () => fetchSheguList('rotten-tomatoes-best-of-all-time') },
  { id: 'based_on_true_story', name: 'Based On True Story', fetch: () => fetchSheguList('based-on-a-true-story') },
  { id: 'oscar_nominees', name: 'Oscar Nominees', fetch: () => fetchSheguList('oscar-nominees-best-picture') },
  { id: 'cannes', name: 'Cannes Film Festival', fetch: () => fetchSheguList('cannes-film-festival') },
];

// These are the shelves from the mixed Home catalog that have an unambiguous
// movie or TV identity. Mixed rows such as Popular Today, Coming Soon, and
// country rankings stay on `all` until they have a category-specific fetch.
const CATEGORY_HIGHLIGHT_IDS = {
  movie: [
    'trending_movie',
    'top_rated_movie',
    'popular_movie_all_time',
    'netflix_movies',
    'hulu_movies',
    'disney_movies',
    'prime_movies',
    'hbo_movies',
    'appletv_movies',
    'layarkaca_movies',
    'rotten_tomatoes_best',
    'based_on_true_story',
    'oscar_nominees',
    'cannes',
    'top_by_genre',
  ],
  tv: [
    'trending_tv',
    'top_rated_tv',
    'popular_tv_all_time',
    'netflix_tv',
    'disney_tv',
    'appletv_tv',
    'prime_tv',
    'hbo_tv',
    'layarkaca_tv',
    'top_by_genre',
  ],
};

function highlightGroupsForCategory(category) {
  if (category === TMDB_ALL_CATEGORY) return HIGHLIGHT_GROUPS;
  const ids = CATEGORY_HIGHLIGHT_IDS[category];
  if (!Array.isArray(ids)) return [];
  const groups = [];
  for (const id of ids) {
    if (id === 'top_by_genre') {
      groups.push(...topByGenreGroups(category));
      continue;
    }
    const group = HIGHLIGHT_GROUPS.find((entry) => entry.id === id);
    if (group != null) groups.push(group);
  }
  return groups;
}

// Highlights declare `subCategories` — one per group, id-matched to the name
// each group is tagged with. Groups backed by a paginated TMDB endpoint also
// expose `nextPage`, allowing the app's See more grid to load more on scroll.
// Non-paginated editorial lists remain single-page, but *do*
// declare `subCategories` — one per group, id-matched to the name each
// group is tagged with — so "See more" on any one of them narrows to just
// that section instead of falling back to the whole unnarrowed catalog
// (the app only narrows when it finds a subCategory whose name matches the
// section heading it came from; with none declared, every "See more" here
// used to reopen everything, unfiltered, under a mismatched title).
async function tmdbHighlightsCatalog(query) {
  const groups = highlightGroupsForCategory(query.category);
  if (groups.length === 0) return { sections: [] };
  const subCategories = groups.map((g) => ({ id: g.id, name: g.name }));

  if (query.subCategory != null) {
    const matched = groups.find((g) => g.id === query.subCategory);
    if (matched == null) return { sections: [], subCategories };
    if (matched.id === 'football_highlights') {
      const page = await fetchTimesoccerHighlightsPage(query.page);
      const result = {
        sections: [{ id: matched.id, title: matched.name, items: page.items }],
        subCategories,
      };
      if (page.nextPage != null) result.nextPage = page.nextPage;
      return result;
    }
    if (typeof matched.fetchPage === 'function') {
      const page = await fetchGroupPage(matched.name, matched.fetchPage, query.page);
      const result = {
        sections: [{ id: matched.id, title: matched.name, items: page.items }],
        subCategories,
      };
      if (page.nextPage != null) result.nextPage = page.nextPage;
      return result;
    }
    const items = await fetchGroup(matched.name, matched.fetch);
    return { sections: [{ id: matched.id, title: matched.name, items }], subCategories };
  }

  const itemGroups = await Promise.all(
    groups.map((g) => fetchGroup(g.name, g.fetch)),
  );
  return {
    sections: groups.map((group, index) => ({
      id: group.id,
      title: group.name,
      items: itemGroups[index],
    })).filter((section) => section.items.length > 0),
    subCategories,
  };
}

// --- catalog: no sections, no subCategories — just the popularity-sorted
// discover feed, straight from the API, paginated for infinite scroll. Named
// curated lists live on the row-based `highlights` catalog above; this
// `movie`/`tv` catalog remains a single flat, ungrouped list for the grid.

async function tmdbCatalog(query) {
  const mediaType =
    query.category === TMDB_MOVIE_CATEGORY
      ? 'movie'
      : query.category === TMDB_TV_CATEGORY
        ? 'tv'
        : null;
  if (mediaType == null) return { sections: [] };

  const page = query.page ? Number(query.page) : 1;
  const discover = await fetchDiscover(mediaType, page);
  const result = { sections: [{ id: 'discover', items: discover.items }] };
  if (discover.page < discover.totalPages) result.nextPage = String(discover.page + 1);
  return result;
}

// --- "previews" catalog: the Shorts feed producer — Coming Soon interleaved
// with released Trending Movie/TV, de-duplicated by MediaRef. This is a
// preview-surface catalog (`categories: []` in manifest.json), so it never
// appears as a Home shelf; the app discovers it only through the Shorts
// registry lookup. The merge policy is entirely ours — the app renders the
// declared order and does not re-sort it.

const PREVIEW_CATALOG_ID = 'previews';
const PREVIEW_TRAILER_TTL_MS = 60 * 60 * 1000;

function mediaRefKey(ref) {
  return `${ref.extensionId}/${ref.providerId}/${ref.id}`;
}

// Alternates movie/tv within one pool so a run of same-kind candidates
// doesn't dominate a stretch of the feed, while preserving each kind's own
// relative order (popularity for Coming Soon, trending rank for Trending).
function alternateByKind(items) {
  const movies = items.filter((item) => item.kind === 'video');
  const series = items.filter((item) => item.kind === 'series');
  const merged = [];
  for (let i = 0; i < movies.length || i < series.length; i++) {
    if (i < movies.length) merged.push(movies[i]);
    if (i < series.length) merged.push(series[i]);
  }
  return merged;
}

// Trending's "day" window can surface a title whose release date is still
// ahead of it (an early trailer spike) — Coming Soon already owns that case,
// so this pool is filtered down to what's actually out.
async function fetchReleasedTrending() {
  const [movies, tv] = await Promise.all([
    fetchTrending('movie').catch(() => []),
    fetchTrending('tv').catch(() => []),
  ]);
  return alternateByKind([...movies, ...tv]).filter(
    (item) => !tmdbIsNotYetReleased(item),
  );
}

// Interleaves two Coming Soon candidates with one released Trending
// candidate, then de-duplicates by MediaRef, keeping the first occurrence —
// upcoming discovery leads the feed while every few items stay useful for
// the Watch action right away.
function interleavePreviewFeed(comingSoon, trending) {
  const merged = [];
  let ci = 0;
  let ti = 0;
  while (ci < comingSoon.length || ti < trending.length) {
    for (let n = 0; n < 2 && ci < comingSoon.length; n++) merged.push(comingSoon[ci++]);
    if (ti < trending.length) merged.push(trending[ti++]);
  }
  const seen = new Set();
  return merged.filter((item) => {
    const key = mediaRefKey(item.ref);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

async function tmdbPreviewCatalog() {
  const [comingSoonRaw, trending] = await Promise.all([
    fetchComingSoon().catch(() => []),
    fetchReleasedTrending().catch(() => []),
  ]);
  const candidates = interleavePreviewFeed(alternateByKind(comingSoonRaw), trending);
  const items = await filterToItemsWithTrailer(candidates);
  return { sections: [{ id: 'previews', items }] };
}

// --- meta (detail page fetch) ---

const TMDB_MAX_CAST = 15;

function tmdbCreditsOf(data) {
  const cast = data.credits && Array.isArray(data.credits.cast) ? data.credits.cast : [];
  return cast.slice(0, TMDB_MAX_CAST).map((person) => {
    const member = { name: person.name || 'Unknown' };
    if (person.character) member.role = person.character;
    if (person.profile_path) {
      member.image = { url: `${TMDB_IMAGE_BASE}/w185${person.profile_path}` };
    }
    return member;
  });
}

function tmdbUsCertification(movieData) {
  const results =
    movieData.release_dates && Array.isArray(movieData.release_dates.results)
      ? movieData.release_dates.results
      : [];
  const us = results.find((r) => r.iso_3166_1 === 'US');
  if (us == null || !Array.isArray(us.release_dates)) return null;
  const withCert = us.release_dates.find((d) => d.certification);
  return withCert ? withCert.certification : null;
}

function tmdbUsContentRating(tvData) {
  const results =
    tvData.content_ratings && Array.isArray(tvData.content_ratings.results)
      ? tvData.content_ratings.results
      : [];
  const us = results.find((r) => r.iso_3166_1 === 'US');
  return us && us.rating ? us.rating : null;
}

function tmdbGenresOf(data) {
  return Array.isArray(data.genres) ? data.genres.map((g) => g.name).filter((n) => !!n) : [];
}

function tmdbFact(facts, label, value) {
  if (typeof value === 'string' && value.trim().length > 0) {
    facts.push({ label, value });
  }
}

function tmdbNames(values) {
  if (!Array.isArray(values)) return null;
  const names = values
    .map((value) => value && typeof value.name === 'string' ? value.name : null)
    .filter((value) => value != null);
  return names.length > 0 ? names.join(', ') : null;
}

function tmdbMovieFacts(data) {
  const facts = [];
  if (typeof data.runtime === 'number' && data.runtime > 0) {
    tmdbFact(facts, 'Runtime', `${data.runtime} min`);
  }
  tmdbFact(facts, 'Release date', data.release_date);
  tmdbFact(facts, 'Certification', tmdbUsCertification(data));
  tmdbFact(facts, 'Status', data.status);
  tmdbFact(facts, 'Original language', data.original_language);
  tmdbFact(facts, 'Languages', tmdbNames(data.spoken_languages));
  tmdbFact(facts, 'Production countries', tmdbNames(data.production_countries));
  return facts;
}

function tmdbTvFacts(data) {
  const facts = [];
  if (Array.isArray(data.episode_run_time) && data.episode_run_time.length > 0) {
    tmdbFact(facts, 'Episode runtime', `${data.episode_run_time[0]} min`);
  }
  tmdbFact(facts, 'First aired', data.first_air_date);
  tmdbFact(facts, 'Certification', tmdbUsContentRating(data));
  tmdbFact(facts, 'Status', data.status);
  if (typeof data.number_of_seasons === 'number' && data.number_of_seasons > 0) {
    tmdbFact(facts, 'Seasons', String(data.number_of_seasons));
  }
  if (typeof data.number_of_episodes === 'number' && data.number_of_episodes > 0) {
    tmdbFact(facts, 'Episodes', String(data.number_of_episodes));
  }
  tmdbFact(facts, 'Original language', data.original_language);
  tmdbFact(facts, 'Networks', tmdbNames(data.networks));
  return facts;
}

function tmdbEpisodeRef(tvId, seasonNumber, episodeNumber) {
  return {
    extensionId: EXTENSION_ID,
    providerId: TMDB_PROVIDER_ID,
    id: `series:${tvId}:season:${seasonNumber}:episode:${episodeNumber}`,
  };
}

function tmdbEpisodeOf(tvId, seasonNumber, episode) {
  const mapped = {
    ref: tmdbEpisodeRef(tvId, seasonNumber, episode.episode_number),
    title: episode.name || 'Untitled',
    position: episode.episode_number,
  };
  if (episode.overview) mapped.description = episode.overview;
  if (episode.still_path) {
    mapped.artwork = { landscape: { url: `${TMDB_IMAGE_BASE}/w300${episode.still_path}` } };
  }
  if (typeof episode.runtime === 'number' && episode.runtime > 0) {
    mapped.durationSeconds = episode.runtime * 60;
  }
  // `air_date` is a bare `"YYYY-MM-DD"` — pinned to UTC midnight explicitly
  // rather than left for the app's date parser to assume a timezone, which
  // could roll it into the wrong day depending on the device's own.
  if (episode.air_date) mapped.availableAt = `${episode.air_date}T00:00:00Z`;
  return mapped;
}

// TMDB's `/tv/{id}` only gives season counts, not episodes — fetch each
// season's episodes in parallel (SeriesSeason.episodes is expected eagerly,
// not lazily, per media_item.dart).
async function tmdbSeasonsOf(tvId, showData) {
  const seasons = Array.isArray(showData.seasons) ? showData.seasons : [];
  return Promise.all(
    seasons.map(async (season) => {
      const detail = await tmdbGetJson(`/tv/${tvId}/season/${season.season_number}`, {});
      const episodes = Array.isArray(detail.episodes) ? detail.episodes : [];
      return {
        id: `season:${season.season_number}`,
        title: season.name || `Season ${season.season_number}`,
        episodes: episodes.map((episode) =>
          tmdbEpisodeOf(tvId, season.season_number, episode)),
      };
    }),
  );
}

async function tmdbRelatedPage(tmdbId, mediaType, relation) {
  try {
    const data = await tmdbGetJson(`/${mediaType}/${tmdbId}/${relation}`, {
      page: 1,
      include_adult: 'false',
    });
    const results = Array.isArray(data.results) ? data.results : [];
    const currentRef = tmdbRefId(mediaType, tmdbId);
    return results
      .map((result) => tmdbToMediaItem(result, mediaType))
      .filter((item) => item.ref.id !== currentRef)
      .slice(0, 10);
  } catch (_) {
    return [];
  }
}

async function tmdbCollectionOf(collectionId) {
  if (collectionId == null) return null;
  try {
    const data = await tmdbGetJson(`/collection/${collectionId}`, {
      include_adult: 'false',
    });
    const parts = Array.isArray(data.parts) ? data.parts : [];
    const items = parts
      .filter((part) => part && part.id != null)
      .map((part) => tmdbToMediaItem(part, 'movie'));
    if (items.length === 0) return null;
    return {
      id: String(data.id || collectionId),
      name: data.name || 'Collection',
      items,
    };
  } catch (_) {
    return null;
  }
}

// Recommendations are the primary detail shelf. Similar is only a fallback:
// TMDB's similar endpoint is based on genres and keywords and can be loose.
async function tmdbRecommendationsOf(tmdbId, mediaType) {
  const recommendations = await tmdbRelatedPage(tmdbId, mediaType, 'recommendations');
  return recommendations.length > 0
    ? recommendations
    : tmdbRelatedPage(tmdbId, mediaType, 'similar');
}

async function tmdbMovieMeta(tmdbId) {
  const data = await tmdbGetJson(`/movie/${tmdbId}`, {
    append_to_response: 'credits,release_dates,images,videos',
    include_image_language: 'en,null',
    include_video_language: 'en,null',
  });
  const detail = { item: tmdbToMediaItem(data, 'movie') };
  if (data.overview) detail.description = data.overview;
  const genres = tmdbGenresOf(data);
  if (genres.length > 0) detail.tags = genres;
  const facts = tmdbMovieFacts(data);
  if (facts.length > 0) detail.facts = facts;
  const credits = tmdbCreditsOf(data);
  if (credits.length > 0) detail.credits = credits;
  const trailers = tmdbTrailers(data);
  const collectionId = data.belongs_to_collection && data.belongs_to_collection.id;
  const [leakMetadata, previewResponse, recommendations, collection] = await Promise.all([
    tmdbLeakMetadata(tmdbId, 'movie'),
    sheguVideoTrailer(tmdbId, 'movie'),
    tmdbRecommendationsOf(tmdbId, 'movie'),
    tmdbCollectionOf(collectionId),
  ]);
  tmdbApplyLeakMetadata(detail, leakMetadata);
  const preview = sheguPreviewWithThumbnail(previewResponse, trailers);
  if (preview != null) trailers.unshift(preview);
  if (trailers.length > 0) detail.trailers = trailers;
  if (collection != null) detail.collection = collection;
  if (recommendations.length > 0) detail.recommendations = recommendations;
  return detail;
}

async function tmdbTvMeta(tmdbId) {
  const data = await tmdbGetJson(`/tv/${tmdbId}`, {
    append_to_response: 'credits,content_ratings,images,videos',
    include_image_language: 'en,null',
    include_video_language: 'en,null',
  });
  const detail = { item: tmdbToMediaItem(data, 'tv') };
  if (data.overview) detail.description = data.overview;
  const genres = tmdbGenresOf(data);
  if (genres.length > 0) detail.tags = genres;
  const facts = tmdbTvFacts(data);
  if (facts.length > 0) detail.facts = facts;
  const credits = tmdbCreditsOf(data);
  if (credits.length > 0) detail.credits = credits;
  const trailers = tmdbTrailers(data);
  const [leakMetadata, previewResponse, recommendations] = await Promise.all([
    tmdbLeakMetadata(tmdbId, 'tv'),
    sheguVideoTrailer(tmdbId, 'tv'),
    tmdbRecommendationsOf(tmdbId, 'tv'),
  ]);
  tmdbApplyLeakMetadata(detail, leakMetadata);
  const preview = sheguPreviewWithThumbnail(previewResponse, trailers);
  if (preview != null) trailers.unshift(preview);
  if (trailers.length > 0) detail.trailers = trailers;
  if (recommendations.length > 0) detail.recommendations = recommendations;
  const seasons = await tmdbSeasonsOf(tmdbId, data);
  if (seasons.length > 0) {
    detail.episodeGuide = { groups: seasons };
  }
  // `last_episode_to_air` is TMDB's own answer to "what's actually aired so
  // far" — `seasons` above lists every episode announced, aired or not, so
  // this is what tells the app's Play button where to default a series that
  // has never been played, instead of walking the full episode list live
  // to find out (see latestAvailableEpisodeTarget in the app).
  const lastAired = data.last_episode_to_air;
  if (
    lastAired &&
    typeof lastAired.season_number === 'number' &&
    typeof lastAired.episode_number === 'number'
  ) {
    const defaultRef = tmdbEpisodeRef(
      tmdbId,
      lastAired.season_number,
      lastAired.episode_number,
    );
    if (seasons.some((group) => group.episodes.some((episode) =>
      episode.ref.id === defaultRef.id))) {
      detail.episodeGuide.defaultEpisodeRef = defaultRef;
    }
  }
  return detail;
}

async function tmdbMeta(args) {
  const parsed = parseTmdbRef(args.ref && args.ref.id);
  if (parsed === null) {
    throw new Error(`Not a TMDB ref id: ${args.ref && args.ref.id}`);
  }
  return parsed.kind === 'series' ? tmdbTvMeta(parsed.tmdbId) : tmdbMovieMeta(parsed.tmdbId);
}

// --- preview (Shorts feed catalog filter + just-in-time resolver) ---
//
// Deliberately its own lightweight fetch, not a slice of `tmdbMovieMeta`/
// `tmdbTvMeta`'s `append_to_response`: those pull credits, release dates and
// images on top of videos, which would turn "does this candidate have a
// trailer" into a full detail fetch per candidate.

async function tmdbVideosOnly(mediaType, tmdbId) {
  const data = await tmdbGetJson(`/${mediaType}/${tmdbId}/videos`, {
    include_video_language: 'en,null',
  });
  return Array.isArray(data.results) ? data.results : [];
}

function newestByPublishDate(videos) {
  if (videos.length === 0) return null;
  return videos
    .slice()
    .sort((a, b) => (Date.parse(b.published_at || '') || 0) - (Date.parse(a.published_at || '') || 0))[0];
}

// Official Trailer, then official Teaser, then a non-official Trailer,
// falling back to whatever YouTube video was published most recently. Only
// YouTube is considered: the app resolves the returned key as a YouTube
// embed, never a raw watch URL.
function tmdbPreviewVideoKey(videos) {
  const youtubeVideos = videos.filter(
    (v) => v && String(v.site || '').toLowerCase() === 'youtube'
      && typeof v.key === 'string' && v.key.trim().length > 0,
  );
  const officialTrailers = youtubeVideos.filter((v) => v.type === 'Trailer' && v.official === true);
  const officialTeasers = youtubeVideos.filter((v) => v.type === 'Teaser' && v.official === true);
  const nonOfficialTrailers = youtubeVideos.filter((v) => v.type === 'Trailer' && v.official !== true);
  const chosen =
    newestByPublishDate(officialTrailers)
    || newestByPublishDate(officialTeasers)
    || newestByPublishDate(nonOfficialTrailers)
    || newestByPublishDate(youtubeVideos);
  return chosen ? chosen.key.trim() : null;
}

// Resolved trailer keys (or `null` for "checked, no trailer"), keyed by
// `mediaType:tmdbId` — bridges `filterToItemsWithTrailer`'s catalog-build
// check and the Shorts workflow's later per-item `preview()` call for the
// same title so it isn't the exact same TMDB videos fetch twice. Entries are
// session-only and expire so newly published trailers can be discovered.
const _previewTrailerCache = new Map();

async function trailerKeyFor(item) {
  const parsed = item && item.ref ? parseTmdbRef(item.ref.id) : null;
  if (parsed === null) return null;
  const mediaType = parsed.kind === 'series' ? 'tv' : 'movie';
  const cacheKey = `${mediaType}:${parsed.tmdbId}`;
  const nowMs = Date.now();
  const cached = _previewTrailerCache.get(cacheKey);
  if (cached != null && nowMs - cached.fetchedAt < PREVIEW_TRAILER_TTL_MS) {
    return cached.key;
  }
  const videos = await tmdbVideosOnly(mediaType, parsed.tmdbId);
  const key = tmdbPreviewVideoKey(videos);
  _previewTrailerCache.set(cacheKey, { key, fetchedAt: nowMs });
  return key;
}

// A candidate with no resolvable YouTube trailer is a dead end in the
// Shorts feed — the viewer would swipe to it and get skipped immediately.
// Checking every candidate here, once per catalog load, keeps it out of
// the list entirely rather than relying on the client's own lazy skip.
async function filterToItemsWithTrailer(items) {
  const keys = await Promise.all(items.map((item) => trailerKeyFor(item).catch(() => null)));
  return items.filter((_, i) => keys[i] != null);
}

// Nothing here is persisted, and the short TTL above lets a caller re-resolve
// an item's preview after an upstream trailer update.
async function tmdbPreview(args) {
  const item = args && args.item;
  let key;
  try {
    key = await trailerKeyFor(item);
  } catch (_) {
    // An upstream hiccup on one item must not look different from that
    // item simply having no trailer.
    return { sources: [] };
  }
  if (key == null) return { sources: [] };
  return {
    sources: [{ id: `yt:${key}`, type: 'embedded', provider: 'youtube', mediaId: key }],
  };
}

// --- search ---
//
// The app fans a free-text query out to every extension's own `search`
// once, unpaged, and merges the results (see `ExtensionRegistry.search`) —
// no per-media-type split on the app side, so both `/search/movie` and
// `/search/tv` are queried here and merged into one list, newest-relevance
// first by TMDB's own `popularity` (each endpoint only ranks within its own
// kind, so this is what makes a single combined ordering out of the two).
//
// One endpoint failing (network blip on just movie or just tv) doesn't
// blank the other's results — same tolerance `fetchGroup` gives catalog
// sections.
async function tmdbSearchType(mediaType, query, page, extraParams) {
  try {
    const data = await tmdbGetJson(`/search/${mediaType}`, {
      query,
      page,
      include_adult: 'false',
      ...extraParams,
    });
    const results = Array.isArray(data.results) ? data.results : [];
    return results.map((result) => ({ result, mediaType }));
  } catch (e) {
    return [];
  }
}

// TMDB backs the film and television scopes and nothing else here: anime has
// its own catalog, counted the way the streaming sites count, and NSFW is
// Indomax's. Answering those scopes would put the wrong database in front of
// a user who just told us which one they wanted. An unscoped search still
// searches both of TMDB's kinds, as it always has.
const TMDB_SEARCH_CATEGORIES = ['movie', 'tv'];

async function tmdbSearch(args) {
  const query = args.query;
  if (!query) return { sections: [] };
  const category = args.category;
  if (category != null && TMDB_SEARCH_CATEGORIES.indexOf(category) === -1) {
    return { sections: [] };
  }
  const page = args.page ? Number(args.page) : 1;
  const [movies, tv] = await Promise.all([
    category === 'tv'
      ? []
      : tmdbSearchType('movie', query, page, { region: 'US' }),
    category === 'movie' ? [] : tmdbSearchType('tv', query, page),
  ]);
  const merged = [...movies, ...tv].sort(
    (a, b) => (b.result.popularity || 0) - (a.result.popularity || 0),
  );
  return {
    sections: [{
      id: 'results',
      items: merged.map((entry) => tmdbToMediaItem(entry.result, entry.mediaType)),
    }],
  };
}

// --- provider registry ---

globalThis.__catalogProviders = globalThis.__catalogProviders || [];
globalThis.__catalogProviders.push({
  catalogId: TMDB_CATALOG_ID,
  catalog: tmdbCatalog,
});
globalThis.__catalogProviders.push({
  catalogId: HIGHLIGHTS_CATALOG_ID,
  catalog: tmdbHighlightsCatalog,
});
globalThis.__catalogProviders.push({
  catalogId: PREVIEW_CATALOG_ID,
  catalog: tmdbPreviewCatalog,
});

globalThis.__extension = globalThis.__extension || {};
if (!globalThis.__extension.catalog) {
  globalThis.__extension.catalog = async (query) => {
    const provider = globalThis.__catalogProviders.find(
      (p) => p.catalogId === query.catalogId,
    );
    if (!provider) {
      throw new Error(`No catalog provider registered for "${query.catalogId}"`);
    }
    return provider.catalog(query);
  };
}

globalThis.__metaProviders = globalThis.__metaProviders || [];
globalThis.__metaProviders.push({
  providerId: TMDB_PROVIDER_ID,
  meta: tmdbMeta,
});

globalThis.__extension = globalThis.__extension || {};
if (!globalThis.__extension.meta) {
  globalThis.__extension.meta = async (args) => {
    const provider = globalThis.__metaProviders.find(
      (p) => p.providerId === args.ref.providerId,
    );
    if (!provider) {
      throw new Error(`No meta provider registered for "${args.ref.providerId}"`);
    }
    return provider.meta(args);
  };
}

globalThis.__previewProviders = globalThis.__previewProviders || [];
globalThis.__previewProviders.push({
  providerId: TMDB_PROVIDER_ID,
  preview: tmdbPreview,
});

globalThis.__extension = globalThis.__extension || {};
if (!globalThis.__extension.preview) {
  globalThis.__extension.preview = async (args) => {
    const providerId = args && args.item && args.item.ref ? args.item.ref.providerId : null;
    const provider = globalThis.__previewProviders.find((p) => p.providerId === providerId);
    if (!provider) {
      throw new Error(`No preview provider registered for "${providerId}"`);
    }
    return provider.preview(args);
  };
}

// Unlike catalog/meta, `search` is called once per *extension*, not routed
// by a provider or catalog id (see `ExtensionRegistry.search`) — so there's
// nothing to dispatch on, and no other provider in this extension needs the
// slot. A plain guarded assignment is enough.
globalThis.__extension = globalThis.__extension || {};
if (!globalThis.__extension.search) {
  globalThis.__extension.search = tmdbSearch;
}
