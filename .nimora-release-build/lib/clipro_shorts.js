// Premier League vertical moments from Clipro/Blaze, exposed as Shorts.
//
// The API returns one moment per result. A moment can expose several poster
// and video renditions; prefer its vertical MP4 rendition for the Shorts
// player and keep the URL resolution lazy/session-only.

const CLIPRO_BASE_URL =
  globalThis.__cliproBaseUrl ||
  'https://blazesdk-prod-cdn.clipro.tv';
const CLIPRO_API_KEY =
  globalThis.__cliproApiKey ||
  'b95c92c4952a43a5bc5f7e692c1e3636';
const CLIPRO_PROVIDER_ID = 'nimora.clipro';
const CLIPRO_CATALOG_ID = 'clipro_shorts';
const CLIPRO_FOTMOB_BASE_URL =
  globalThis.__cliproFotmobBaseUrl || 'https://www.fotmob.com';
const CLIPRO_FOTMOB_LEAGUE_ID = '47';
const CLIPRO_FOTMOB_CACHE_TTL_MS = 15 * 60 * 1000;
const CLIPRO_CACHE_TTL_MS = 5 * 60 * 1000;
const CLIPRO_MAX_ITEMS = 20;
const CLIPRO_USER_AGENT =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';

let cliproMomentsMemo = null;
let cliproLabelFiltersMemo = null;

function cliproSeasonCode(value) {
  const match = /^(\d{4})\/(\d{4})$/.exec(String(value || '').trim());
  if (match == null) return null;
  return `${match[1]}${match[2].slice(-2)}`;
}

function cliproRoundNumber(value) {
  const round = Number(value);
  return Number.isInteger(round) && round > 0 ? round : null;
}

function cliproLabelFiltersFromFotmob(data) {
  const season = cliproSeasonCode(data && data.details && data.details.selectedSeason);
  if (season == null) return [];

  const fixtureInfo = data && data.fixtures && data.fixtures.fixtureInfo;
  const activeRound = cliproRoundNumber(
    fixtureInfo && fixtureInfo.activeRound && fixtureInfo.activeRound.roundId,
  );
  const matches = data && data.fixtures && Array.isArray(data.fixtures.allMatches)
    ? data.fixtures.allMatches
    : [];
  const playedRounds = matches
    .filter((match) => {
      const status = match && match.status;
      return status && (status.finished === true || status.ongoing === true);
    })
    .map((match) => cliproRoundNumber(match && match.round))
    .filter((round) => round != null);
  const latestPlayedRound = playedRounds.length === 0
    ? null
    : Math.max(...playedRounds);

  const rounds = new Set();
  if (activeRound != null) rounds.add(activeRound);
  if (latestPlayedRound != null) rounds.add(latestPlayedRound);
  // Once a round is in progress, keep the immediately previous round in the
  // feed during the transition so a sparse new round cannot hide fresh clips.
  if (activeRound != null && latestPlayedRound === activeRound && activeRound > 1) {
    rounds.add(activeRound - 1);
  }
  return [...rounds]
    .sort((a, b) => b - a)
    .map((round) => `${season}-mw${round}`);
}

async function cliproLabelFilters() {
  const nowMs = Date.now();
  if (
    cliproLabelFiltersMemo != null &&
    nowMs - cliproLabelFiltersMemo.fetchedAt < CLIPRO_FOTMOB_CACHE_TTL_MS
  ) {
    return cliproLabelFiltersMemo.promise;
  }

  const promise = (async () => {
    const response = await fetch(
      `${CLIPRO_FOTMOB_BASE_URL}/api/data/leagues?id=${CLIPRO_FOTMOB_LEAGUE_ID}`,
      {
        headers: {
          Accept: 'application/json, text/plain, */*',
          'User-Agent': CLIPRO_USER_AGENT,
        },
      },
    );
    if (response.status < 200 || response.status >= 300) {
      throw new Error(`FotMob Premier League request failed: ${response.status}`);
    }
    return cliproLabelFiltersFromFotmob(JSON.parse(response.body));
  })().catch(() => []);

  cliproLabelFiltersMemo = { fetchedAt: nowMs, promise };
  return promise;
}

function cliproMomentsUrl(labelFilter) {
  const query = {
    ApiKey: CLIPRO_API_KEY,
    clientPlatform: 'Web',
    labelsFilterExpression: labelFilter,
    maxItems: '100',
    labelsPriority: '[]',
  };
  const encoded = Object.entries(query)
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
    .join('&');
  return `${CLIPRO_BASE_URL}/api/blazesdk/v1.3/moments?${encoded}`;
}

function cliproHttpUrl(value) {
  if (typeof value !== 'string') return null;
  const url = value.trim();
  return /^https?:\/\//i.test(url) ? url : null;
}

function cliproIsMp4(rendition) {
  if (rendition == null || typeof rendition !== 'object') return false;
  const fileType = String(rendition.fileType || '').toLowerCase();
  const url = cliproHttpUrl(rendition.url);
  return url != null && (fileType === 'mp4' || /\.mp4(?:[?#]|$)/i.test(url));
}

function cliproIsVertical(rendition) {
  if (rendition == null || typeof rendition !== 'object') return false;
  const aspect = `${rendition.aspectRatio || ''} ${rendition.aspectRatioDescription || ''}`
    .toLowerCase();
  return aspect.includes('vertical') || aspect.includes('9:16');
}

function cliproVideoRendition(moment) {
  const content = moment && moment.baseLayer && moment.baseLayer.content;
  const renditions = content && Array.isArray(content.renditions)
    ? content.renditions.filter(cliproIsMp4)
    : [];
  if (renditions.length === 0) return null;
  return renditions.slice().sort((a, b) => {
    const aVertical = cliproIsVertical(a) ? 0 : 1;
    const bVertical = cliproIsVertical(b) ? 0 : 1;
    if (aVertical !== bVertical) return aVertical - bVertical;
    return Number(b.bitRate || 0) - Number(a.bitRate || 0);
  })[0];
}

function cliproPosterUrl(moment) {
  const poster = moment && moment.poster;
  const posterRendition = poster && poster.rendition;
  const posterUrl = cliproHttpUrl(posterRendition && posterRendition.url);
  if (posterUrl != null) return posterUrl;
  const posterRenditions = poster && Array.isArray(poster.renditions)
    ? poster.renditions
    : [];
  const firstPoster = posterRenditions.find((rendition) =>
    cliproHttpUrl(rendition && rendition.url) != null,
  );
  if (firstPoster != null) return cliproHttpUrl(firstPoster.url);

  const thumbnails = moment && Array.isArray(moment.thumbnails)
    ? moment.thumbnails
    : [];
  const preferred = thumbnails.find((thumbnail) => {
    const rendition = thumbnail && thumbnail.rendition;
    return cliproIsVertical(rendition) && cliproHttpUrl(rendition.url) != null;
  }) || thumbnails.find((thumbnail) =>
    cliproHttpUrl(thumbnail && thumbnail.rendition && thumbnail.rendition.url) != null,
  );
  return preferred == null
    ? null
    : cliproHttpUrl(preferred.rendition && preferred.rendition.url);
}

async function cliproMomentsForLabel(labelFilter) {
  const response = await fetch(cliproMomentsUrl(labelFilter), {
    headers: {
      Accept: 'application/json',
      'User-Agent': CLIPRO_USER_AGENT,
    },
  });
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Clipro moments request failed: ${response.status}`);
  }
  const data = JSON.parse(response.body);
  return data != null && Array.isArray(data.result) ? data.result : [];
}

async function cliproMoments() {
  const nowMs = Date.now();
  if (
    cliproMomentsMemo != null &&
    nowMs - cliproMomentsMemo.fetchedAt < CLIPRO_CACHE_TTL_MS
  ) {
    return cliproMomentsMemo.promise;
  }

  const promise = (async () => {
    const labels = await cliproLabelFilters();
    const batches = await Promise.all(
      labels.map((label) => cliproMomentsForLabel(label).catch(() => [])),
    );
    const momentsById = new Map();
    for (const batch of batches) {
      for (const moment of batch) {
        if (moment == null || moment.id == null) continue;
        const id = String(moment.id);
        if (!momentsById.has(id)) momentsById.set(id, moment);
      }
    }
    return [...momentsById.values()];
  })().catch(() => []);

  cliproMomentsMemo = { fetchedAt: nowMs, promise };
  return promise;
}

function cliproText(value) {
  return String(value || '').replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
}

function cliproMomentItem(moment) {
  if (moment == null || moment.id == null || cliproVideoRendition(moment) == null) {
    return null;
  }
  const title = cliproText(moment.title) || 'Premier League Moment';
  const item = {
    ref: {
      extensionId: EXTENSION_ID,
      providerId: CLIPRO_PROVIDER_ID,
      id: `moment:${String(moment.id)}`,
    },
    kind: 'video',
    title,
    subtitle: 'Premier League',
    tags: ['sports', 'football', 'premier-league'],
  };
  const poster = cliproPosterUrl(moment);
  if (poster != null) item.artwork = { portrait: { url: poster } };
  return item;
}

function cliproMomentTimestamp(moment) {
  if (moment == null) return null;
  const value = moment.createTime || moment.updateTime;
  if (typeof value !== 'string' || value.trim() === '') return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function cliproCuratedMoments(moments) {
  if (!Array.isArray(moments)) return [];
  const seen = new Set();
  const candidates = [];
  moments.forEach((moment, index) => {
    const item = cliproMomentItem(moment);
    if (item == null || seen.has(item.ref.id)) return;
    seen.add(item.ref.id);
    candidates.push({ moment, index });
  });
  candidates.sort((a, b) => {
    const aDate = cliproMomentTimestamp(a.moment);
    const bDate = cliproMomentTimestamp(b.moment);
    if (aDate != null && bDate == null) return -1;
    if (aDate == null && bDate != null) return 1;
    if (aDate != null && bDate != null && aDate !== bDate) {
      return bDate - aDate;
    }
    return a.index - b.index;
  });
  return candidates.slice(0, CLIPRO_MAX_ITEMS).map(({ moment }) => moment);
}

function cliproMomentItems(moments) {
  return cliproCuratedMoments(moments)
    .map((moment) => cliproMomentItem(moment))
    .filter((item) => item != null);
}

function cliproMomentIdFromItem(item) {
  const id = item && item.ref && item.ref.id;
  const prefix = 'moment:';
  if (
    item == null || item.ref == null ||
    item.ref.providerId !== CLIPRO_PROVIDER_ID ||
    typeof id !== 'string' || !id.startsWith(prefix)
  ) return null;
  const momentId = id.slice(prefix.length);
  return momentId.length === 0 ? null : momentId;
}

async function cliproPreview(args) {
  const item = args && args.item;
  const momentId = cliproMomentIdFromItem(item);
  if (momentId == null) return { sources: [] };

  const moments = await cliproMoments();
  const moment = moments.find((entry) =>
    entry != null && String(entry.id) === momentId,
  );
  const rendition = cliproVideoRendition(moment);
  const url = cliproHttpUrl(rendition && rendition.url);
  if (url == null) return { sources: [] };
  return {
    sources: [{
      id: `preview:clipro:${momentId}`,
      type: 'direct',
      stream: {
        url,
        format: 'other',
        label: 'Premier League Moment',
      },
    }],
  };
}

async function cliproShortsCatalog() {
  const moments = await cliproMoments();
  return {
    sections: [{
      id: 'clipro',
      title: 'Premier League Moments',
      items: cliproMomentItems(moments),
    }],
  };
}

globalThis.__catalogProviders = globalThis.__catalogProviders || [];
globalThis.__catalogProviders.push({
  catalogId: CLIPRO_CATALOG_ID,
  catalog: cliproShortsCatalog,
});

globalThis.__previewProviders = globalThis.__previewProviders || [];
globalThis.__previewProviders.push({
  providerId: CLIPRO_PROVIDER_ID,
  preview: cliproPreview,
});
