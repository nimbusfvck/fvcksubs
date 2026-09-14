// shegu.st subtitle lookup, in JS on the host `fetch` API.
//
// A Stremio-shaped subtitle addon: one GET, keyed by TMDB id, returns a flat
// list of {language, url, type, display, source}. No cipher, no auth — the
// simplest upstream this bundle talks to.

const SHEGU_BASE = globalThis.__sheguBaseUrl || 'https://subtitles.shegu.st';

async function fetchMovieSubtitles(tmdbId, season, episode) {
  let url = `${SHEGU_BASE}/subtitles?type=movie&tmdb=${encodeURIComponent(tmdbId)}`;
  if (season != null && episode != null) {
    url = `${SHEGU_BASE}/subtitles?type=tv&tmdb=${encodeURIComponent(tmdbId)}&season=${encodeURIComponent(season)}&episode=${encodeURIComponent(episode)}`;
  }

  let response;
  try {
    response = await fetch(url);
  } catch (_) {
    return [];
  }
  if (response.status < 200 || response.status >= 300) return [];

  let data;
  try {
    data = JSON.parse(response.body);
  } catch (_) {
    return [];
  }
  const list = Array.isArray(data.subtitles) ? data.subtitles : [];

  const tracks = [];
  for (const entry of list) {
    const language = entry && entry.language;
    const trackUrl = entry && entry.url;
    if (!language || !trackUrl) continue;
    tracks.push({ language, url: trackUrl, label: entry.display || '' });
  }
  return tracks;
}

globalThis.sheguSubtitles = { fetchMovieSubtitles };

// ---- externalSubtitles role — a manual lookup, independent of any source ----
//
// The player's "fetch external subtitles" button asks for this role directly,
// keyed only on the item's `movie:<tmdbId>` /
// `series:<tmdbId>` ref, same convention every other provider file in this
// bundle re-parses for itself — see e.g. vaplayer.js's parseVaplayerRef).
function parseSheguRef(refId) {
  if (typeof refId !== 'string') return null;
  const episode = /^series:([^:]+):season:([^:]+):episode:([^:]+)$/.exec(refId);
  if (episode != null) {
    return {
      kind: 'series',
      tmdbId: episode[1],
      season: episode[2],
      episode: episode[3],
    };
  }
  const separator = refId.indexOf(':');
  if (separator < 0) return null;
  const kind = refId.slice(0, separator);
  const tmdbId = refId.slice(separator + 1);
  if ((kind !== 'movie' && kind !== 'series') || tmdbId.length === 0) {
    return null;
  }
  return { kind, tmdbId, season: null, episode: null };
}

function parseSheguAnilistEpisode(refId, item) {
  if (typeof refId !== 'string') return null;
  const match = /^anilist:episode:(\d+):(\d+)$/.exec(refId);
  if (match == null) return null;

  const groupId = item && item.episode && typeof item.episode.groupId === 'string'
    ? item.episode.groupId
    : '';
  const seasonMatch = /(?:^|:)season:(\d+)/i.exec(groupId);
  return {
    anilistId: match[1],
    episode: match[2],
    season: seasonMatch == null ? '1' : seasonMatch[1],
  };
}

async function sheguExternalSubtitles(args) {
  const item = args.item || {};
  const refId = (item.ref && item.ref.id) || item.id || '';
  const parsed = parseSheguRef(refId);
  if (!parsed) {
    const anilistEpisode = parseSheguAnilistEpisode(refId, item);
    if (
      anilistEpisode == null ||
      typeof flystreamResolveAnilistIdentity !== 'function'
    ) {
      return { subtitles: [] };
    }
    let identity;
    try {
      identity = await flystreamResolveAnilistIdentity(anilistEpisode, item);
    } catch (_) {
      return { subtitles: [] };
    }
    if (identity == null || typeof identity.tmdbId !== 'string') {
      return { subtitles: [] };
    }
    const tracks = await fetchMovieSubtitles(
      identity.tmdbId,
      identity.season || anilistEpisode.season,
      anilistEpisode.episode,
    );
    return { subtitles: tracks };
  }

  const isSeries = parsed.kind === 'series';
  if (isSeries && (parsed.season == null || parsed.episode == null)) {
    return { subtitles: [] };
  }

  const tracks = await fetchMovieSubtitles(
    parsed.tmdbId,
    isSeries ? parsed.season : null,
    isSeries ? parsed.episode : null,
  );
  return { subtitles: tracks };
}

globalThis.__extension = globalThis.__extension || {};
if (!globalThis.__extension.subtitles) {
  globalThis.__extension.subtitles = sheguExternalSubtitles;
}
