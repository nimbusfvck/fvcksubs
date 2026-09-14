// MovieBox (aoneroom) as a stream provider, over the host `fetch` API.
//
// Ported from CineStream's `invokeMoviebox` (CineStreamExtractors.kt). Four
// steps, and each one needs the previous:
//
//   1. a bearer token, read from the `x-user` *response header* of an
//      otherwise uninteresting "latest app packages" call
//   2. a search by title, which yields a `subjectId`
//   3. a `detailPath` for that subject, from a second host
//   4. `subject/play` + `subject/download`, which finally carry URLs
//
// Step 1 is why this provider exists here at all: it needs to read a response
// header, which the host `fetch` does expose (verified — `res.headers` is
// populated). Nothing else in this extension had needed one.
//
// Unlike every other provider here, MovieBox is keyed by **title**, not by a
// tmdb id — it has no idea what TMDB is. That makes matching the weak point:
// its index is regionally skewed (searching an English title readily returns
// unrelated Indonesian ones), so titles are compared exactly rather than
// fuzzily, and a near-miss is dropped instead of guessed at. Playing the
// wrong film is worse than offering nothing.
//
// An episode gets its *series* title from `extra.seriesTitle` — the item's own
// `title` is the episode's ("Ep 3 (S2E3)"), which would find nothing.

const MOVIEBOX_API = globalThis.__movieboxApiUrl || 'https://h5-api.aoneroom.com';
const MOVIEBOX_WEB = globalThis.__movieboxWebUrl || 'https://h5.aoneroom.com';

const MOVIEBOX_PROVIDER_KEY = 'moviebox';

// The upstream serves these only to its own player origin.
const MOVIEBOX_PLAYER_ORIGIN = 'https://fmoviesunblocked.net';
const MOVIEBOX_UA =
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/138.0.0.0';

// A trailing season range — "Breaking Bad [Indonesian] S1-S2" — is how the
// index names a whole show, and is not part of the title being matched.
const MOVIEBOX_SEASON_SUFFIX = /\s+S\d+(?:-S?\d+)*$/i;

// "Title [Indonesian]" is the same subject in another dub; the bracket is the
// language, and worth keeping as a label rather than discarding.
const MOVIEBOX_LANGUAGE_SUFFIX = /^(.*?)(?:\s+\[([^\]]+)\])?$/;

// The token is a short-lived JWT handed out to anyone who asks, so it is
// fetched per call rather than cached: a stale one fails the whole chain, and
// the request that mints it is cheap.
async function movieboxToken() {
  let response;
  try {
    response = await fetch(
      `${MOVIEBOX_API}/wefeed-h5api-bff/app/get-latest-app-pkgs?app_name=moviebox`,
      { headers: { 'User-Agent': MOVIEBOX_UA } },
    );
  } catch (_) {
    return null;
  }
  if (response.status < 200 || response.status >= 300) return null;

  const headers = response.headers || {};
  const raw = headers['x-user'] || headers['X-User'];
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed && parsed.token ? parsed.token : null;
  } catch (_) {
    return null;
  }
}

function movieboxHeaders(token, extra) {
  return {
    Accept: 'application/json',
    'Accept-Language': 'en-US,en;q=0.5',
    'X-Client-Info': '{"timezone":"Africa/Nairobi"}',
    Authorization: `Bearer ${token}`,
    'User-Agent': MOVIEBOX_UA,
    Referer: MOVIEBOX_API,
    ...(extra || {}),
  };
}

// Responses nest as `{data: {...}}` or `{data: {data: {...}}}` depending on
// the endpoint.
function movieboxUnwrap(payload) {
  const data = payload && payload.data;
  if (!data) return payload || {};
  return data.data || data;
}

async function movieboxJson(url, options) {
  let response;
  try {
    response = await fetch(url, options);
  } catch (_) {
    return null;
  }
  if (response.status < 200 || response.status >= 300) return null;
  try {
    return JSON.parse(response.body);
  } catch (_) {
    return null;
  }
}

// Subjects whose title matches `title` exactly, once a season range is
// stripped and a language bracket set aside.
function movieboxMatches(items, title) {
  const wanted = `${title}`.trim().toLowerCase();
  const found = [];
  const seen = {};
  for (const item of items) {
    if (!item || !item.subjectId) continue;
    const raw = `${item.title || ''}`.replace(MOVIEBOX_SEASON_SUFFIX, '').trim();
    const parts = MOVIEBOX_LANGUAGE_SUFFIX.exec(raw);
    if (!parts) continue;
    const name = (parts[1] || '').trim().toLowerCase();
    if (name !== wanted) continue;

    const id = `${item.subjectId}`;
    if (seen[id]) continue;
    seen[id] = true;
    found.push({ subjectId: id, language: parts[2] || 'Original' });
  }
  return found;
}

async function movieboxSearch(token, title, isSeries) {
  const payload = await movieboxJson(
    `${MOVIEBOX_API}/wefeed-h5api-bff/subject/search`,
    {
      method: 'POST',
      headers: movieboxHeaders(token, {
        'Content-Type': 'application/json',
      }),
      body: JSON.stringify({
        keyword: title,
        page: 1,
        perPage: 24,
        subjectType: isSeries ? 2 : 1,
      }),
    },
  );
  const items = movieboxUnwrap(payload).items;
  return Array.isArray(items) ? movieboxMatches(items, title) : [];
}

// A subject's `detailPath`, which `play`/`download` both require. Served by a
// different host than everything else, and without a token.
async function movieboxDetailPath(subjectId) {
  const payload = await movieboxJson(
    `${MOVIEBOX_WEB}/wefeed-h5-bff/web/post/list/subject?id=${encodeURIComponent(subjectId)}`,
    { headers: { 'User-Agent': MOVIEBOX_UA } },
  );
  const items = (payload && payload.data && payload.data.items) || [];
  const subject = items[0] && items[0].subject;
  return (subject && subject.detailPath) || null;
}

function encodeMovieboxSourceId(payload) {
  return base64ToBase64Url(host.codec.textToBase64(JSON.stringify(payload)));
}

function decodeMovieboxSourceId(encoded) {
  return JSON.parse(host.codec.base64ToText(base64UrlToBase64(encoded)));
}

// the item's `movie:<tmdbId>` / `series:<tmdbId>` ref id, when it came
// from there. MovieBox itself never needs it — it searches by name — but the
// shegu.st subtitle fallback is keyed by tmdbId, so it is carried along when
// available and simply absent when not.
function movieboxTmdbOf(item) {
  const refId = (item.ref && item.ref.id) || '';
  if (typeof refId !== 'string') return null;
  const separator = refId.indexOf(':');
  if (separator < 0) return null;
  const kind = refId.slice(0, separator);
  const tmdbId = refId.slice(separator + 1);
  if ((kind !== 'movie' && kind !== 'series') || !tmdbId) return null;
  return tmdbId;
}

// The title to search on: a series' own name, never the episode's.
function movieboxTitleOf(item) {
  const extra = item.extra || {};
  const seriesTitle = extra.seriesTitle;
  if (typeof seriesTitle === 'string' && seriesTitle.length > 0) {
    return seriesTitle;
  }
  return typeof item.title === 'string' ? item.title : '';
}

// sources() — one entry per matching subject.
//
// Stops after the search: `detailPath` and the play/download calls are three
// more round trips per subject, and resolve() needs fresh URLs anyway.
async function movieboxListSources(args) {
  const item = args.item || {};
  const kind = item.kind;

  // Only the VOD kinds; a fixture has no title to look up here.
  const isSeries = kind === 'episode' || kind === 'series';
  if (kind !== 'video' && !isSeries) return { sources: [] };
  if (isSeries) return { sources: [] };

  const title = movieboxTitleOf(item);
  if (!title) return { sources: [] };

  const token = await movieboxToken();
  if (!token) return { sources: [] };

  const subjects = await movieboxSearch(token, title, isSeries);
  const tmdbId = movieboxTmdbOf(item);

  return {
    sources: subjects.map((subject, index) => {
      const id = `${MOVIEBOX_PROVIDER_KEY}:${encodeMovieboxSourceId({
        s: subject.subjectId,
        ...(tmdbId ? { m: tmdbId } : {}),
      })}`;
      // Keep the provider name and language; do not mask the source with an alias.
      const lang =
        subject.language === 'Original' ? '' : ` [${subject.language}]`;
      return {
        id,
        label: `MovieBox${lang}`,
        provider: 'Nimora',
        providerId: 'nimora.moviebox',
      };
    }),
  };
}

// Streams from `play`, plus `download`'s own list — the two overlap but each
// carries entries the other doesn't. VIP-locked entries are dropped: they
// resolve to something the viewer cannot actually play.
function movieboxStreams(playData, downloadData) {
  const out = [];
  for (const stream of playData.streams || []) {
    if (!stream || !stream.url || stream.vipLocked) continue;
    out.push({ url: stream.url, format: stream.format });
  }
  for (const download of downloadData.downloads || []) {
    if (!download || !download.url || download.vipLocked) continue;
    out.push({ url: download.url, format: download.format });
  }
  return out;
}

function movieboxCaptions(downloadData) {
  const captions = downloadData.captions;
  if (!Array.isArray(captions)) return [];
  return captions
    .filter((c) => c && typeof c.url === 'string' && c.url.length > 0)
    .map((c) => ({
      language: c.lan || c.lanName || '',
      url: c.url,
      label: c.lanName || c.lan || '',
    }));
}

function movieboxStreamFormat(stream) {
  const url = `${stream.url || ''}`;
  const format = `${stream.format || ''}`.toLowerCase();
  if (
    format === 'hls' ||
    /\.m3u8(?:$|\?)/i.test(url) ||
    /(?:^|\/)playlist(?:\/|$)/i.test(url)
  ) {
    return 'hls';
  }
  if (format === 'dash' || /\.mpd(?:$|\?)/i.test(url)) return 'dash';
  return 'other';
}

async function movieboxResolveSource(sourceId) {
  const prefix = `${MOVIEBOX_PROVIDER_KEY}:`;
  if (!sourceId.startsWith(prefix)) {
    throw new Error(`Invalid MovieBox sourceId: ${sourceId}`);
  }
  const decoded = decodeMovieboxSourceId(sourceId.slice(prefix.length));
  const { s: subjectId, m: tmdbId, se: season, ep: episode } = decoded;

  const token = await movieboxToken();
  if (!token) throw new Error('MovieBox: no token');

  const detailPath = await movieboxDetailPath(subjectId);
  if (!detailPath) throw new Error('MovieBox: no detailPath for subject');

  let params = `subjectId=${encodeURIComponent(subjectId)}`;
  if (season != null) {
    params += `&se=${encodeURIComponent(season)}&ep=${encodeURIComponent(episode)}`;
  }
  params += `&detailPath=${encodeURIComponent(detailPath)}`;

  const headers = movieboxHeaders(token, {
    Origin: MOVIEBOX_PLAYER_ORIGIN,
    Referer: `${MOVIEBOX_PLAYER_ORIGIN}/spa/videoPlayPage/movies/${detailPath}?id=${subjectId}&type=/movie/detail`,
  });
  const playbackReferer = headers.Referer;

  const [play, download] = await Promise.all([
    movieboxJson(`${MOVIEBOX_API}/wefeed-h5api-bff/subject/play?${params}`, {
      headers,
    }),
    movieboxJson(`${MOVIEBOX_API}/wefeed-h5api-bff/subject/download?${params}`, {
      headers,
    }),
  ]);

  const playData = movieboxUnwrap(play);
  const downloadData = movieboxUnwrap(download);
  const streams = movieboxStreams(playData, downloadData);
  if (streams.length === 0) {
    throw new Error('MovieBox: no playable stream for this subject');
  }

  const chosen = streams[0];
  // Some MovieBox playlists use `/playlist/` without an `.m3u8` suffix.
  // Preserve the provider's format, but recognize that URL shape as HLS so
  // the native player selects the playlist extractor.
  const format = movieboxStreamFormat(chosen);

  // Only captions advertised by MovieBox belong to this resolved source.
  // Shegu is an independent external-subtitles provider and is fetched by
  // the app only after the viewer asks for external subtitles.
  const subtitles = movieboxCaptions(downloadData);

  return {
    url: chosen.url,
    format,
    headers: {
      Origin: MOVIEBOX_PLAYER_ORIGIN,
      Referer: playbackReferer,
      'User-Agent': MOVIEBOX_UA,
    },
    subtitles,
  };
}

// ---- registration — see kora.js's tail for the shared aggregator ----

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: MOVIEBOX_PROVIDER_KEY,
  sources: movieboxListSources,
  resolve: (sourceId) => movieboxResolveSource(sourceId),
});
