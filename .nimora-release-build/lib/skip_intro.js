// Optional playback-segment lookup for episode items.
//
// IntroDB keys its timestamps by the show's IMDb id. AniSkip keys anime by
// MyAnimeList id, so AniList items are resolved to MAL before querying it.
// This role is deliberately best-effort: missing IDs, an upstream 404, or a
// provider outage must leave playback usable with no segments.

const SKIP_INTRO_PROVIDER_ID = 'nimora.skipintro';
const SKIP_INTRO_TMDB_BASE =
  globalThis.__tmdbBaseUrl || 'https://api.themoviedb.org/3';
const SKIP_INTRO_TMDB_API_KEY =
  globalThis.__tmdbApiKey || '8476a7ab80ad76f0936744df0430e67c';
const SKIP_INTRO_ANILIST_BASE =
  globalThis.__anilistApiUrl || 'https://graphql.anilist.co';
const SKIP_INTRO_INTRODB_BASE =
  globalThis.__introDbBaseUrl || 'https://api.introdb.app';
const SKIP_INTRO_ANISKIP_BASE =
  globalThis.__aniSkipBaseUrl || 'https://api.aniskip.com/v2';

const skipIntroTmdbImdbMemo = new Map();
const skipIntroAniListMalMemo = new Map();

function skipIntroPositiveInteger(value) {
  const number = typeof value === 'number' ? value : Number(value);
  return Number.isInteger(number) && number > 0 ? number : null;
}

function skipIntroMilliseconds(value) {
  const number = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(number) && number >= 0 ? Math.round(number) : null;
}

function skipIntroSecondsToMilliseconds(value) {
  const number = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(number) && number >= 0
    ? Math.round(number * 1000)
    : null;
}

function skipIntroInterval(type, startMs, endMs) {
  const start = skipIntroMilliseconds(startMs);
  const end = skipIntroMilliseconds(endMs);
  if (start == null || end == null || end <= start) return null;
  return { type, startMs: start, endMs: end };
}

function skipIntroResponseInterval(type, segment) {
  if (segment == null || typeof segment !== 'object') return null;
  const start = segment.start_ms == null
    ? skipIntroSecondsToMilliseconds(segment.start_sec)
    : skipIntroMilliseconds(segment.start_ms);
  const end = segment.end_ms == null
    ? skipIntroSecondsToMilliseconds(segment.end_sec)
    : skipIntroMilliseconds(segment.end_ms);
  return skipIntroInterval(type, start, end);
}

function skipIntroMapAniSkipType(value) {
  const type = String(value || '').trim().toLowerCase();
  if (type === 'op' || type === 'opening' || type === 'mixed-op' || type === 'intro') {
    return 'intro';
  }
  if (type === 'recap') return 'recap';
  if (
    type === 'ed' ||
    type === 'ending' ||
    type === 'mixed-ed' ||
    type === 'outro' ||
    type === 'credits'
  ) {
    return 'outro';
  }
  return null;
}

function skipIntroEpisodeContext(item) {
  if (item == null || typeof item !== 'object' || item.kind !== 'episode') {
    return null;
  }
  const ref = item.ref;
  const episode = item.episode;
  const parentRef = episode && episode.parentRef;
  const seasonMatch = /^season:(\d+)$/.exec(String(episode && episode.groupId || ''));
  const season = seasonMatch == null ? 1 : Number(seasonMatch[1]);
  const episodeNumber = skipIntroPositiveInteger(episode && episode.position);
  if (
    ref == null ||
    typeof ref.providerId !== 'string' ||
    parentRef == null ||
    typeof parentRef.id !== 'string' ||
    episodeNumber == null ||
    !Number.isInteger(season) ||
    season <= 0
  ) {
    return null;
  }

  if (ref.providerId === 'nimora.tmdb') {
    const match = /^series:(\d+)$/.exec(parentRef.id);
    if (match == null) return null;
    return {
      kind: 'tmdb',
      tmdbId: match[1],
      season,
      episode: episodeNumber,
    };
  }

  if (ref.providerId === 'nimora.anilist') {
    const match = /^anilist:media:(\d+)$/.exec(parentRef.id);
    if (match == null) return null;
    return {
      kind: 'anilist',
      anilistId: match[1],
      season,
      episode: episodeNumber,
    };
  }
  return null;
}

async function skipIntroFetchJson(url, options) {
  const response = await fetch(url, options);
  if (response.status < 200 || response.status >= 300) return null;
  try {
    return JSON.parse(response.body);
  } catch (_) {
    return null;
  }
}

function skipIntroQuery(params) {
  return Object.entries(params)
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
    .join('&');
}

async function skipIntroTmdbImdbId(tmdbId) {
  if (skipIntroTmdbImdbMemo.has(tmdbId)) {
    return skipIntroTmdbImdbMemo.get(tmdbId);
  }
  const promise = (async () => {
    const params = skipIntroQuery({
      api_key: SKIP_INTRO_TMDB_API_KEY,
      language: 'en-US',
    });
    const data = await skipIntroFetchJson(
      `${SKIP_INTRO_TMDB_BASE}/tv/${encodeURIComponent(tmdbId)}/external_ids?${params}`,
    );
    const imdbId = data && typeof data.imdb_id === 'string'
      ? data.imdb_id.trim()
      : '';
    return imdbId.startsWith('tt') ? imdbId : null;
  })().catch(() => null);
  skipIntroTmdbImdbMemo.set(tmdbId, promise);
  return promise;
}

async function skipIntroIntroDb(context) {
  const imdbId = await skipIntroTmdbImdbId(context.tmdbId);
  if (imdbId == null) return [];
  const params = skipIntroQuery({
    imdb_id: imdbId,
    season: String(context.season),
    episode: String(context.episode),
  });
  const data = await skipIntroFetchJson(
    `${SKIP_INTRO_INTRODB_BASE}/segments?${params}`,
  );
  if (data == null || typeof data !== 'object') return [];
  return [
    skipIntroResponseInterval('intro', data.intro),
    skipIntroResponseInterval('recap', data.recap),
    skipIntroResponseInterval('outro', data.outro),
  ].filter((segment) => segment != null);
}

async function skipIntroAniListMalId(anilistId) {
  if (skipIntroAniListMalMemo.has(anilistId)) {
    return skipIntroAniListMalMemo.get(anilistId);
  }
  const promise = (async () => {
    const data = await skipIntroFetchJson(SKIP_INTRO_ANILIST_BASE, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        query: 'query ($id: Int) { Media(id: $id, type: ANIME) { idMal } }',
        variables: { id: Number(anilistId) },
      }),
    });
    const idMal = data && data.data && data.data.Media && data.data.Media.idMal;
    return skipIntroPositiveInteger(idMal);
  })().catch(() => null);
  skipIntroAniListMalMemo.set(anilistId, promise);
  return promise;
}

async function skipIntroAniSkip(context) {
  const malId = await skipIntroAniListMalId(context.anilistId);
  if (malId == null) return [];
  const params = [
    ['types[]', 'op'],
    ['types[]', 'ed'],
    ['types[]', 'mixed-op'],
    ['types[]', 'mixed-ed'],
    ['types[]', 'recap'],
    ['episodeLength', '0'],
  ];
  const query = params
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
    .join('&');
  const data = await skipIntroFetchJson(
    `${SKIP_INTRO_ANISKIP_BASE}/skip-times/${encodeURIComponent(malId)}/${encodeURIComponent(context.episode)}?${query}`,
  );
  const results = data && Array.isArray(data.results) ? data.results : [];
  return results
    .map((result) => {
      const type = skipIntroMapAniSkipType(result && result.skipType);
      const interval = result && result.interval;
      if (type == null || interval == null) return null;
      return skipIntroInterval(
        type,
        skipIntroSecondsToMilliseconds(interval.startTime),
        skipIntroSecondsToMilliseconds(interval.endTime),
      );
    })
    .filter((segment) => segment != null);
}

function skipIntroOverlap(a, b) {
  return a.startMs < b.endMs && b.startMs < a.endMs;
}

// Sources disagree, and one source disagrees with itself: AniSkip carries
// several community submissions per episode, so One Piece and Frieren each
// come back with two intros overlapping by half their length, and Attack on
// Titan adds an "outro" sitting in its first two minutes.
//
// Dropping only exact duplicates left all of them standing, and the player
// showed it: skipping to the end of the first intro lands inside the second,
// which still covers that moment and offers the button again — the double
// skip a viewer sees.
//
// Overlap is the tell, so overlap resolves it. Same-type segments that touch
// keep the earliest, since that is where a viewer pressing skip wants to
// leave from. An outro overlapping an intro is dropped outright: a closing
// sequence cannot sit inside an opening one, and mislabelling it that way
// would have the player treat the first minutes as the end of the episode.
function skipIntroMergeSegments(segmentLists) {
  const candidates = segmentLists
    .flat()
    .filter(
      (segment) =>
        segment != null &&
        Number.isFinite(segment.startMs) &&
        Number.isFinite(segment.endMs) &&
        segment.startMs >= 0 &&
        segment.endMs > segment.startMs,
    )
    .sort((a, b) => a.startMs - b.startMs || a.endMs - b.endMs);

  const kept = [];
  const keepUnlessOverlapping = (segment) => {
    if (kept.some((other) => other.type === segment.type && skipIntroOverlap(other, segment))) {
      return;
    }
    kept.push(segment);
  };

  // Openings and recaps first, so an outro is judged against every intro that
  // survived rather than against whichever happened to be read first.
  for (const segment of candidates) {
    if (segment.type !== 'outro') keepUnlessOverlapping(segment);
  }
  for (const segment of candidates) {
    if (segment.type !== 'outro') continue;
    if (kept.some((other) => other.type === 'intro' && skipIntroOverlap(other, segment))) {
      continue;
    }
    keepUnlessOverlapping(segment);
  }

  kept.sort((a, b) => a.startMs - b.startMs || a.endMs - b.endMs);
  return kept;
}

async function skipIntroSegments(args) {
  const context = skipIntroEpisodeContext(args && args.item);
  if (context == null) return { segments: [] };
  const lookups = context.kind === 'tmdb'
    ? [skipIntroIntroDb(context)]
    : [skipIntroAniSkip(context)];
  const settled = await Promise.all(lookups.map((lookup) => lookup.catch(() => [])));
  return { segments: skipIntroMergeSegments(settled) };
}

globalThis.__extension = globalThis.__extension || {};
if (!globalThis.__extension.segments) {
  globalThis.__extension.segments = skipIntroSegments;
}
