// AniList anime catalog, search, and meta.
//
// TMDB backs everything else here, and deliberately does not back anime. The
// two databases disagree about what an anime *is*: TMDB folds Bleach's four
// Thousand-Year Blood War cours into one 50-episode "Season 2", while AniList
// lists each cour as its own entry numbered from 1 — which is exactly how
// Sokuja and Indomax list them. Matching a catalog item to a stream is a
// title-and-number game, so the catalog that counts the way the sources count
// wins more sources.
//
// The cost is deliberate and worth stating: an AniList ref carries no TMDB id,
// so the tmdbId-keyed providers (Vidrock, Videasy, MovieBox, and Shegu
// subtitles) cannot serve these items. Anime plays from the providers that
// match on title — which are the ones that carry Indonesian subtitles anyway.

const ANILIST_API_URL = globalThis.__anilistApiUrl || 'https://graphql.anilist.co';
const ANILIST_PROVIDER_ID = 'nimora.anilist';
const ANILIST_CATALOG_ID = 'anilist';
const ANILIST_CATEGORY = 'anime';
const ANILIST_PER_PAGE = 30;
// One page of aired episodes is enough to date a running cour, which is the
// case that needs dates at all: a stream provider stamps its uploads with the
// broadcast day. A long-runner's early episodes fall outside this window and
// carry no date, and are matched by number instead.
const ANILIST_SCHEDULE_PER_PAGE = 100;

const ANILIST_MEDIA_FIELDS = `
  id
  format
  status
  episodes
  averageScore
  startDate { year }
  title { romaji english }
  coverImage { extraLarge large }
  bannerImage
`;

const ANILIST_LIST_QUERY = `
  query ($page: Int, $perPage: Int, $sort: [MediaSort], $status: MediaStatus, $search: String, $season: MediaSeason, $seasonYear: Int) {
    Page(page: $page, perPage: $perPage) {
      pageInfo { currentPage hasNextPage }
      media(type: ANIME, isAdult: false, sort: $sort, status: $status, search: $search, season: $season, seasonYear: $seasonYear) {
        ${ANILIST_MEDIA_FIELDS}
      }
    }
  }
`;

const ANILIST_MEDIA_QUERY = `
  query ($id: Int, $schedulePerPage: Int) {
    Media(id: $id, type: ANIME) {
      ${ANILIST_MEDIA_FIELDS}
      genres
      description(asHtml: false)
      nextAiringEpisode { episode }
      airingSchedule(notYetAired: false, page: 1, perPage: $schedulePerPage) {
        nodes { episode airingAt }
      }
    }
  }
`;

// Sorted shelves rather than genre shelves: AniList's genre list is long and
// uneven, while these four answer the questions a browsing user actually has.
const ANILIST_SHELVES = [
  { id: 'trending', name: 'Trending', sort: ['TRENDING_DESC'] },
  { id: 'popular', name: 'Popular', sort: ['POPULARITY_DESC'] },
  { id: 'airing', name: 'Airing Now', sort: ['POPULARITY_DESC'], status: 'RELEASING' },
  { id: 'top', name: 'Top Rated', sort: ['SCORE_DESC'] },
];

async function anilistQuery(query, variables) {
  try {
    const response = await fetch(ANILIST_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({ query, variables }),
    });
    if (response.status < 200 || response.status >= 300) return null;
    const payload = JSON.parse(response.body);
    // GraphQL reports failure in the body with a 200, so a present `data` is
    // the only signal worth trusting.
    return payload && payload.data ? payload.data : null;
  } catch (_) {
    return null;
  }
}

// Romaji first, not English: the Indonesian fansub sites this catalog feeds
// list titles in romaji, and the item's title is what the stream providers
// match on.
function anilistTitle(media) {
  const title = media && media.title ? media.title : {};
  return title.romaji || title.english || 'Untitled';
}

function anilistRefId(mediaId) {
  return `anilist:media:${mediaId}`;
}

function anilistEpisodeRefId(mediaId, episode) {
  return `anilist:episode:${mediaId}:${episode}`;
}

function anilistParseRefId(refId) {
  const match = /^anilist:media:(\d+)$/.exec(String(refId || ''));
  return match == null ? null : match[1];
}

function anilistToMediaItem(media) {
  const item = {
    ref: {
      extensionId: EXTENSION_ID,
      providerId: ANILIST_PROVIDER_ID,
      id: anilistRefId(media.id),
    },
    kind: media.format === 'MOVIE' ? 'video' : 'series',
    title: anilistTitle(media),
  };
  const year = media.startDate && media.startDate.year;
  if (Number.isInteger(year) && year > 0) item.releaseYear = year;
  // AniList scores out of 100; the protocol's rating is the 0–10 scale the
  // rest of the catalog uses.
  if (Number.isFinite(media.averageScore) && media.averageScore > 0) {
    item.rating = media.averageScore / 10;
  }
  const artwork = {};
  const cover = media.coverImage || {};
  const portrait = cover.extraLarge || cover.large;
  if (portrait) artwork.portrait = { url: portrait };
  if (media.bannerImage) artwork.landscape = { url: media.bannerImage };
  if (Object.keys(artwork).length > 0) item.artwork = artwork;
  return item;
}

function anilistItemsOf(data) {
  const page = data && data.Page;
  const media = page && Array.isArray(page.media) ? page.media : [];
  return media.filter((entry) => entry != null).map(anilistToMediaItem);
}

function anilistShelf(subCategory) {
  if (subCategory == null) return ANILIST_SHELVES[0];
  return ANILIST_SHELVES.find((shelf) => shelf.id === subCategory) || null;
}

async function anilistCatalog(query) {
  if (query.category !== ANILIST_CATEGORY) return { sections: [] };
  const subCategories = ANILIST_SHELVES.map((shelf) => ({
    id: shelf.id,
    name: shelf.name,
  }));
  const shelf = anilistShelf(query.subCategory);
  if (shelf == null) return { sections: [], subCategories };

  const requested = Number(query.page);
  const page = Number.isInteger(requested) && requested > 0 ? requested : 1;
  const data = await anilistQuery(ANILIST_LIST_QUERY, {
    page,
    perPage: ANILIST_PER_PAGE,
    sort: shelf.sort,
    status: shelf.status,
  });
  if (data == null) return { sections: [], subCategories };

  // No section title: the shelf is chosen by chip and the grid is one flat,
  // paginated list, so a heading would name what the chip already says and put
  // it between pages as the user scrolls.
  const result = {
    sections: [{ id: shelf.id, items: anilistItemsOf(data) }],
    subCategories,
  };
  const pageInfo = data.Page && data.Page.pageInfo;
  if (pageInfo && pageInfo.hasNextPage) result.nextPage = String(page + 1);
  return result;
}

// The Home "Trending Anime" row. It lives in the TMDB-backed highlights
// catalog with the other rows, but its data comes from here: TMDB has no
// anime genre, and narrowing `discover` to Japanese animation on one
// streamer's licence returned barely thirty titles.
const ANILIST_HIGHLIGHT_LIMIT = 25;

function anilistSeasonForDate(date) {
  const month = date.getUTCMonth() + 1;
  let season;
  if (month <= 3) {
    season = 'WINTER';
  } else if (month <= 6) {
    season = 'SPRING';
  } else if (month <= 9) {
    season = 'SUMMER';
  } else {
    season = 'FALL';
  }
  return { season, seasonYear: date.getUTCFullYear() };
}

async function anilistHighlightItems() {
  const data = await anilistQuery(ANILIST_LIST_QUERY, {
    page: 1,
    perPage: ANILIST_HIGHLIGHT_LIMIT,
    sort: ['TRENDING_DESC'],
  });
  return data == null ? [] : anilistItemsOf(data);
}

async function anilistPopularSeasonItems(now) {
  const current = anilistSeasonForDate(now || new Date());
  const data = await anilistQuery(ANILIST_LIST_QUERY, {
    page: 1,
    perPage: ANILIST_HIGHLIGHT_LIMIT,
    sort: ['POPULARITY_DESC'],
    season: current.season,
    seasonYear: current.seasonYear,
  });
  return data == null ? [] : anilistItemsOf(data);
}

async function anilistSearch(args) {
  const search = args && args.query;
  if (!search) return { sections: [] };
  const requested = Number(args.page);
  const page = Number.isInteger(requested) && requested > 0 ? requested : 1;
  const data = await anilistQuery(ANILIST_LIST_QUERY, {
    page,
    perPage: ANILIST_PER_PAGE,
    search,
    sort: ['SEARCH_MATCH'],
  });
  if (data == null) return { sections: [] };
  const result = { sections: [{ id: 'anilist-results', items: anilistItemsOf(data) }] };
  const pageInfo = data.Page && data.Page.pageInfo;
  if (pageInfo && pageInfo.hasNextPage) result.nextPage = String(page + 1);
  return result;
}

// AniList's plain-text description still carries the site's own line breaks
// and the occasional inline tag.
function anilistDescription(value) {
  return String(value || '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]*>/g, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function anilistHighestScheduled(schedule) {
  let highest = 0;
  for (const episode of schedule.keys()) {
    if (episode > highest) highest = episode;
  }
  return highest;
}

// The guide lists every episode announced, aired or not — the app hides the
// unaired ones by their date. `episodes` is null while a series is running,
// so an announced total is not always available and the schedule stands in.
function anilistEpisodeCount(media, schedule) {
  if (Number.isInteger(media.episodes) && media.episodes > 0) {
    return media.episodes;
  }
  return Math.max(anilistLastAired(media, schedule), anilistHighestScheduled(schedule));
}

// Where a series that has never been played should start. Not the last
// episode in the guide: a running cour announces its full episode count from
// the first week, so the guide's tail is months away from airing.
function anilistLastAired(media, schedule) {
  const next = media.nextAiringEpisode && media.nextAiringEpisode.episode;
  if (Number.isInteger(next) && next > 0) return next - 1;
  const scheduled = anilistHighestScheduled(schedule);
  if (scheduled > 0) return scheduled;
  // Nothing airing and nothing scheduled: a finished series, all of it out.
  return Number.isInteger(media.episodes) && media.episodes > 0
    ? media.episodes
    : 0;
}

function anilistSchedule(media) {
  const nodes = media.airingSchedule && Array.isArray(media.airingSchedule.nodes)
    ? media.airingSchedule.nodes
    : [];
  const byEpisode = new Map();
  for (const node of nodes) {
    const episode = node && Number(node.episode);
    const airingAt = node && Number(node.airingAt);
    if (!Number.isInteger(episode) || !Number.isFinite(airingAt)) continue;
    byEpisode.set(episode, new Date(airingAt * 1000).toISOString());
  }
  return byEpisode;
}

// One group, always: an AniList entry *is* one cour, numbered from 1, so a
// season axis on top of it would be invented. The id still says `season:1`
// because stream providers read the season out of it.
function anilistEpisodeGuide(media, schedule, total) {
  if (total < 1) return null;
  const episodes = [];
  for (let position = 1; position <= total; position++) {
    const episode = {
      ref: {
        extensionId: EXTENSION_ID,
        providerId: ANILIST_PROVIDER_ID,
        id: anilistEpisodeRefId(media.id, position),
      },
      title: `Episode ${position}`,
      position,
    };
    const availableAt = schedule.get(position);
    if (availableAt != null) episode.availableAt = availableAt;
    episodes.push(episode);
  }
  return { groups: [{ id: 'season:1', title: 'Episodes', episodes }] };
}

async function anilistMeta(args) {
  const mediaId = anilistParseRefId(args && args.ref && args.ref.id);
  if (mediaId == null) {
    throw new Error(`Not an AniList ref id: ${args && args.ref && args.ref.id}`);
  }
  const data = await anilistQuery(ANILIST_MEDIA_QUERY, {
    id: Number(mediaId),
    schedulePerPage: ANILIST_SCHEDULE_PER_PAGE,
  });
  const media = data && data.Media;
  if (media == null) throw new Error(`AniList has no media ${mediaId}`);

  const detail = { item: anilistToMediaItem(media) };
  const description = anilistDescription(media.description);
  if (description) detail.description = description;
  if (Array.isArray(media.genres) && media.genres.length > 0) {
    detail.tags = media.genres.filter((genre) => typeof genre === 'string');
  }
  if (media.format === 'MOVIE') return detail;

  const schedule = anilistSchedule(media);
  const total = anilistEpisodeCount(media, schedule);
  const guide = anilistEpisodeGuide(media, schedule, total);
  if (guide != null) {
    detail.episodeGuide = guide;
    const lastAired = Math.min(anilistLastAired(media, schedule), total);
    if (lastAired >= 1) {
      detail.episodeGuide.defaultEpisodeRef = {
        extensionId: EXTENSION_ID,
        providerId: ANILIST_PROVIDER_ID,
        id: anilistEpisodeRefId(media.id, lastAired),
      };
    }
  }
  return detail;
}

globalThis.__catalogProviders = globalThis.__catalogProviders || [];
globalThis.__catalogProviders.push({
  catalogId: ANILIST_CATALOG_ID,
  catalog: anilistCatalog,
});

globalThis.__metaProviders = globalThis.__metaProviders || [];
globalThis.__metaProviders.push({
  providerId: ANILIST_PROVIDER_ID,
  meta: anilistMeta,
});

// Search is one call per extension, so the providers in this bundle form a
// chain rather than a fan-out. Sokuja owns the live anime catalog when it is
// present; this keeps AniList available as a metadata/search fallback for
// isolated bundles and existing AniList refs.
globalThis.__extension = globalThis.__extension || {};
const anilistPreviousSearch = globalThis.__extension.search;
globalThis.__extension.search = async (args) => {
  if (args && args.category === ANILIST_CATEGORY &&
      !globalThis.__sokujaCatalogActive) {
    return anilistSearch(args);
  }
  if (typeof anilistPreviousSearch !== 'function') return { sections: [] };
  return anilistPreviousSearch(args);
};
