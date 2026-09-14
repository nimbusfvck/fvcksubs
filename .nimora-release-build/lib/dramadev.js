// Dramadev Dracin series exposed as Shorts and native HLS sources, plus
// stream-only movie matching for TMDB-backed movie items.
//
// Dramadev's stream endpoint returns a short-lived /vmanifest token. The
// manifest is a regular HLS media playlist with relative /v/ MPEG-TS
// segments, so resolution stays lazy and every playback attempt gets a fresh
// token instead of caching a signed media URL.

const DRAMADEV_BASE_URL =
  globalThis.__dramadevBaseUrl || 'https://dramadev.my.id';
const DRAMADEV_PROVIDER_ID = 'nimora.dramadev';
const DRAMADEV_PROVIDER_KEY = 'dramadev';
const DRAMADEV_TMDB_PROVIDER_ID = 'nimora.tmdb';
const DRAMADEV_CATALOG_ID = 'dracin_shorts';
const DRAMADEV_SHORTS_PAGE_LIMIT = 5;
const DRAMADEV_COLLECTIONS = [
  { id: 'dramaverse', title: 'Dramaverse' },
  { id: 'storyreel', title: 'Storyreel' },
];
const DRAMADEV_USER_AGENT =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';

function dramadevBaseUrl() {
  return DRAMADEV_BASE_URL.replace(/\/$/, '');
}

function dramadevUrl(path) {
  if (typeof path !== 'string' || path.trim() === '') return null;
  const value = path.trim();
  if (/^https?:\/\//i.test(value)) return value;
  return value.startsWith('/')
    ? `${dramadevBaseUrl()}${value}`
    : `${dramadevBaseUrl()}/${value}`;
}

function dramadevHeaders(referer) {
  return {
    Accept: 'application/json, text/plain, */*',
    Origin: dramadevBaseUrl(),
    Referer: referer || `${dramadevBaseUrl()}/`,
    'User-Agent': DRAMADEV_USER_AGENT,
  };
}

async function dramadevGet(path, referer) {
  const url = dramadevUrl(path);
  if (url == null) return null;
  try {
    const response = await fetch(url, { headers: dramadevHeaders(referer) });
    if (response.status < 200 || response.status >= 300) return null;
    return response;
  } catch (_) {
    return null;
  }
}

async function dramadevJson(path, referer) {
  const response = await dramadevGet(path, referer);
  if (response == null) return null;
  try { return JSON.parse(response.body); } catch (_) { return null; }
}

function dramadevText(value) {
  return String(value || '').replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
}

// Keep title matching conservative. Dramadev's search response does not
// expose a TMDB id or release year, so punctuation/whitespace differences
// are normalized but fuzzy matches are deliberately not accepted.
function dramadevTitleKey(value) {
  return dramadevText(value)
    .toLowerCase()
    .replace(/[\s\-_:,.!?'()[\]{}]+/g, ' ')
    .trim();
}

function dramadevTmdbMovieId(item) {
  const ref = item && item.ref;
  const id = ref && typeof ref.id === 'string' ? ref.id : '';
  const match = /^movie:([^:]+)$/.exec(id);
  if (
    item == null || item.kind !== 'video' ||
    ref == null || ref.providerId !== DRAMADEV_TMDB_PROVIDER_ID ||
    match == null
  ) return null;
  return match[1];
}

async function dramadevMovieSearch(title) {
  const data = await dramadevJson(
    `/search/lookseries?q=${encodeURIComponent(String(title || ''))}`,
    `${dramadevBaseUrl()}/`,
  );
  if (data == null || !Array.isArray(data.items)) return [];
  const wanted = dramadevTitleKey(title);
  const seen = new Set();
  return data.items.filter((item) => {
    if (
      item == null || item.id == null || seen.has(String(item.id)) ||
      dramadevTitleKey(item.title) !== wanted
    ) return false;
    seen.add(String(item.id));
    return true;
  });
}

async function dramadevLookseriesEpisodes(id) {
  const data = await dramadevJson(
    `/episodes/lookseries?id=${encodeURIComponent(String(id))}`,
    `${dramadevBaseUrl()}/`,
  );
  return data && Array.isArray(data.episodes) ? data.episodes : [];
}

function dramadevMoreSeries(data, collectionId) {
  if (data == null || !Array.isArray(data.items)) return [];
  const seen = new Set();
  return data.items.filter((item) => {
    if (item == null || item.id == null || seen.has(String(item.id))) return false;
    if (!dramadevText(item.title)) return false;
    seen.add(String(item.id));
    return true;
  }).map((item) => ({ ...item, collection: collectionId }));
}

function dramadevCollection(collectionId) {
  return DRAMADEV_COLLECTIONS.find((collection) => collection.id === collectionId) ||
    DRAMADEV_COLLECTIONS[0];
}

async function dramadevMorePage(collectionId, page) {
  const requestedPage = Number.isInteger(page) && page > 0 ? page : 1;
  const collection = dramadevCollection(collectionId);
  return dramadevJson(
    `/more/${collection.id}/foryou?page=${requestedPage}`,
    `${dramadevBaseUrl()}/more/${collection.id}/foryou?page=${requestedPage}`,
  );
}

function dramadevEpisodeNumber(episode) {
  const number = Number(episode && (episode.n || episode.ep));
  return Number.isFinite(number) && number > 0 ? number : null;
}

function dramadevEncode(payload) {
  return encodeURIComponent(JSON.stringify(payload));
}

function dramadevDecode(value) {
  try { return JSON.parse(decodeURIComponent(String(value || ''))); } catch (_) { return null; }
}

function dramadevSeriesPayload(series) {
  return {
    id: String(series.id),
    title: dramadevText(series.title) || 'Dramaverse',
    cover: typeof series.cover === 'string' ? series.cover.trim() : '',
    collection: dramadevCollection(series.collection).id,
  };
}

function dramadevSeriesRef(series) {
  return {
    extensionId: EXTENSION_ID,
    providerId: DRAMADEV_PROVIDER_ID,
    id: `${DRAMADEV_PROVIDER_KEY}:series:${dramadevEncode(dramadevSeriesPayload(series))}`,
  };
}

function dramadevSeriesItem(series) {
  const payload = dramadevSeriesPayload(series);
  const item = {
    ref: dramadevSeriesRef(payload),
    kind: 'series',
    title: payload.title,
    subtitle: 'Dramaverse',
    tags: ['dracin', payload.collection],
  };
  if (payload.cover) item.artwork = { portrait: { url: payload.cover } };
  return item;
}

function dramadevEpisodeRef(series, episode) {
  const number = dramadevEpisodeNumber(episode);
  if (number == null) return null;
  return {
    extensionId: EXTENSION_ID,
    providerId: DRAMADEV_PROVIDER_ID,
    id: `${DRAMADEV_PROVIDER_KEY}:episode:${dramadevEncode({
      id: String(series.id),
      ep: String(episode.ep || number),
      n: number,
      collection: dramadevCollection(series.collection).id,
    })}`,
  };
}

function dramadevEpisodeSummary(series, episode) {
  const number = dramadevEpisodeNumber(episode);
  const ref = dramadevEpisodeRef(series, episode);
  if (number == null || ref == null) return null;
  const title = dramadevText(episode && episode.title) || `Episode ${number}`;
  const summary = {
    ref,
    title,
    position: number,
  };
  if (typeof series.cover === 'string' && series.cover.trim()) {
    summary.artwork = { portrait: { url: series.cover.trim() } };
  }
  return summary;
}

function dramadevEpisodePayloadFromRef(ref) {
  const id = ref && typeof ref.id === 'string' ? ref.id : '';
  const prefix = `${DRAMADEV_PROVIDER_KEY}:episode:`;
  if (
    ref == null || ref.providerId !== DRAMADEV_PROVIDER_ID ||
    !id.startsWith(prefix)
  ) return null;
  const payload = dramadevDecode(id.slice(prefix.length));
  return payload && payload.id != null && payload.ep != null && payload.n != null
    ? payload
    : null;
}

function dramadevSeriesPayloadFromRef(ref) {
  const id = ref && typeof ref.id === 'string' ? ref.id : '';
  const prefix = `${DRAMADEV_PROVIDER_KEY}:series:`;
  if (
    ref == null || ref.providerId !== DRAMADEV_PROVIDER_ID ||
    !id.startsWith(prefix)
  ) return null;
  const payload = dramadevDecode(id.slice(prefix.length));
  return payload && payload.id != null ? payload : null;
}

function dramadevSeriesFromPayload(payload) {
  return {
    id: String(payload.id),
    title: dramadevText(payload.title) || 'Dramaverse',
    cover: typeof payload.cover === 'string' ? payload.cover : '',
    collection: dramadevCollection(payload.collection).id,
  };
}

async function dramadevEpisodes(series) {
  const id = encodeURIComponent(String(series.id));
  const collection = dramadevCollection(series.collection);
  const data = await dramadevJson(
    `/episodes/${collection.id}?id=${id}`,
    `${dramadevBaseUrl()}/episodes/${collection.id}?id=${id}`,
  );
  const episodes = data && Array.isArray(data.episodes) ? data.episodes : [];
  return episodes
    .map((episode, index) => ({ episode, index, number: dramadevEpisodeNumber(episode) }))
    .filter((entry) => entry.number != null)
    .sort((a, b) => a.number - b.number || a.index - b.index)
    .map((entry) => dramadevEpisodeSummary(series, entry.episode))
    .filter((item) => item != null);
}

async function dramadevShortsCatalog(query) {
  const requestedPage = Number(query && query.page);
  const page = Number.isInteger(requestedPage) && requestedPage > 0
    ? requestedPage
    : null;
  const firstPage = page || 1;
  const lastPage = page || DRAMADEV_SHORTS_PAGE_LIMIT;
  const sections = await Promise.all(DRAMADEV_COLLECTIONS.map(async (collection) => {
    const pages = [];
    for (let currentPage = firstPage; currentPage <= lastPage; currentPage++) {
      const data = await dramadevMorePage(collection.id, currentPage);
      const series = dramadevMoreSeries(data, collection.id);
      if (series.length === 0) break;
      pages.push(...series);
      if (page != null) break;
    }

    const seen = new Set();
    const items = pages
      .filter((series) => {
        const id = String(series.id);
        if (seen.has(id)) return false;
        seen.add(id);
        return true;
      })
      .map(dramadevSeriesItem);
    return items.length === 0
      ? null
      : { id: `dracin-${collection.id}`, title: collection.title, items };
  }));
  const result = {
    sections: sections.filter((section) => section != null),
  };
  // The endpoint has no total-pages metadata. A non-empty page is the only
  // safe signal available, so direct catalog requests can continue one page
  // at a time while the Shorts preview uses a bounded initial batch above.
  if (page != null && result.sections.length > 0) {
    result.nextPage = String(page + 1);
  }
  return result;
}

function dramadevPayloadFromRef(ref) {
  return dramadevEpisodePayloadFromRef(ref);
}

async function dramadevMeta(args) {
  const payload = dramadevSeriesPayloadFromRef(args && args.ref);
  if (payload == null) throw new Error('Malformed Dramadev series ref');
  const series = dramadevSeriesFromPayload(payload);
  const episodes = await dramadevEpisodes(series);
  const defaultEpisodeRef = episodes.length > 0 ? episodes[0].ref : null;
  const detail = {
    item: dramadevSeriesItem(series),
    tags: ['dracin', series.collection],
  };
  if (episodes.length > 0) {
    detail.episodeGuide = {
      groups: [{ id: 'season:1', title: 'Episodes', episodes }],
      defaultEpisodeRef,
    };
  }
  return detail;
}

function dramadevPayloadFromSourceId(sourceId) {
  const prefix = `${DRAMADEV_PROVIDER_KEY}:`;
  if (typeof sourceId !== 'string' || !sourceId.startsWith(prefix)) return null;
  return dramadevDecode(sourceId.slice(prefix.length));
}

async function dramadevResolvePayload(payload) {
  if (payload == null || payload.id == null) return null;
  let streamPath;
  if (payload.kind === 'movie') {
    streamPath = `/stream/lookseries?id=${encodeURIComponent(String(payload.id))}` +
      '&ep=&n=1';
  } else {
    const collection = dramadevCollection(payload.collection);
    const query = `id=${encodeURIComponent(String(payload.id))}` +
      `&ep=${encodeURIComponent(String(payload.ep))}` +
      `&n=${encodeURIComponent(String(payload.n))}`;
    streamPath = `/stream/${collection.id}?${query}`;
  }
  const stream = await dramadevJson(
    streamPath,
    `${dramadevBaseUrl()}${streamPath}`,
  );
  const manifestUrl = dramadevUrl(stream && stream.video_url);
  if (manifestUrl == null) return null;

  const manifest = await dramadevGet(manifestUrl, `${dramadevBaseUrl()}/`);
  const body = String(manifest && manifest.body || '').trim();
  if (!/^#EXTM3U(?:\s|$)/.test(body) || !/#EXTINF:/i.test(body)) return null;
  if (!/(?:^|\n)\/v\/[^\s\r\n]+/i.test(body)) return null;

  return {
    url: manifestUrl,
    format: 'hls',
    headers: {
      Origin: dramadevBaseUrl(),
      Referer: `${dramadevBaseUrl()}/`,
      'User-Agent': DRAMADEV_USER_AGENT,
    },
    label: 'Dramadev HLS',
  };
}

async function dramadevSources(args) {
  const enabled = args && args.enabledProviders;
  if (enabled != null && enabled.indexOf(DRAMADEV_PROVIDER_ID) === -1) {
    return { sources: [] };
  }
  const item = args && args.item;
  const payload = dramadevPayloadFromRef(item && item.ref);
  if (payload != null && item.kind === 'episode') {
    return {
      sources: [{
        id: `${DRAMADEV_PROVIDER_KEY}:${dramadevEncode(payload)}`,
        label: 'Dramadev HLS',
        provider: 'Nimora',
        providerId: DRAMADEV_PROVIDER_ID,
      }],
    };
  }

  const tmdbId = dramadevTmdbMovieId(item);
  if (tmdbId == null) return { sources: [] };
  const title = dramadevText(item.title);
  if (!title) return { sources: [] };
  const matches = await dramadevMovieSearch(title);
  // The search response has no year/TMDB id. Never guess between duplicate
  // exact titles; offering no source is safer than playing the wrong film.
  if (matches.length !== 1) return { sources: [] };
  const match = matches[0];
  const episodes = await dramadevLookseriesEpisodes(match.id);
  // LookSeries represents a movie as a one-entry playback list. This keeps
  // the stream-only provider from accidentally claiming a TV series.
  if (episodes.length !== 1) return { sources: [] };
  const moviePayload = {
    kind: 'movie',
    id: String(match.id),
    tmdbId,
    title,
  };
  return {
    sources: [{
      id: `${DRAMADEV_PROVIDER_KEY}:${dramadevEncode(moviePayload)}`,
      label: 'Dramadev HLS',
      provider: 'Nimora',
      providerId: DRAMADEV_PROVIDER_ID,
    }],
  };
}

async function dramadevResolveSource(sourceId) {
  const payload = dramadevPayloadFromSourceId(sourceId);
  if (payload == null) throw new Error('Malformed Dramadev source id');
  const stream = await dramadevResolvePayload(payload);
  if (stream == null) throw new Error('Dramadev returned no playable HLS');
  return stream;
}

async function dramadevPreview(args) {
  const ref = args && args.item && args.item.ref;
  let payload = dramadevPayloadFromRef(ref);
  if (payload == null) {
    const seriesPayload = dramadevSeriesPayloadFromRef(ref);
    if (seriesPayload == null) return { sources: [] };
    const episodes = await dramadevEpisodes(dramadevSeriesFromPayload(seriesPayload));
    const first = episodes[0];
    if (first == null) return { sources: [] };
    const episodeParts = dramadevEpisodePayloadFromRef(first.ref);
    if (episodeParts == null) return { sources: [] };
    payload = episodeParts;
  }
  const stream = await dramadevResolvePayload(payload);
  if (stream == null) return { sources: [] };
  return {
    sources: [{
      id: `preview:${DRAMADEV_PROVIDER_KEY}:${dramadevEncode(payload)}`,
      type: 'direct',
      stream,
    }],
  };
}

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: DRAMADEV_PROVIDER_KEY,
  sources: dramadevSources,
  resolve: dramadevResolveSource,
});

globalThis.__catalogProviders = globalThis.__catalogProviders || [];
globalThis.__catalogProviders.push({
  catalogId: DRAMADEV_CATALOG_ID,
  catalog: dramadevShortsCatalog,
});

globalThis.__metaProviders = globalThis.__metaProviders || [];
globalThis.__metaProviders.push({
  providerId: DRAMADEV_PROVIDER_ID,
  meta: dramadevMeta,
});

globalThis.__previewProviders = globalThis.__previewProviders || [];
globalThis.__previewProviders.push({
  providerId: DRAMADEV_PROVIDER_ID,
  preview: dramadevPreview,
});
