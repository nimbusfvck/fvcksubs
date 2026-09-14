// Football fixtures catalog, as a JS extension.
//
// Sourced from FotMob's daily match feed for schedule and live status. A small
// set of provider-only contributors may add missing live events, while stream
// providers still resolve the selected event independently.
//
// The host provides: `fetch(url, options)` -> Promise<{status, headers, url,
// body}>. Nothing else — no fs, no process, no ambient network.
//
// This is the file that loads first in the bundle (see build_bundle.dart):
// it declares `EXTENSION_ID` and installs the base `globalThis.__extension`
// object every other file adds to.

// Overridable purely so a test can point this at a loopback fixture server;
// production otherwise. Not a general configuration mechanism — extensions
// have none yet, and this is not one.
const FOTMOB_BASE = globalThis.__fotmobBaseUrl || 'https://www.fotmob.com';
// Keep the match feed localized for Indonesian users, but use the US league
// market for FotMob's popular list so Indonesian domestic competitions are not
// promoted into the Football catalog just because the app is localized to ID.
const FOTMOB_CCODE3 = 'IDN';
const FOTMOB_LEAGUE_COUNTRY = 'USA';
const FOTMOB_IMAGE_BASE = 'https://images.fotmob.com/image_resources/logo/teamlogo';
const FOTMOB_LEAGUE_IMAGE_BASE =
  'https://images.fotmob.com/image_resources/logo/leaguelogo/dark';
// FotMob's market list includes youth competitions but omits Saudi Pro League
// for the US market. Keep the Football catalog focused on senior competitions
// and explicitly include the requested Saudi top flight.
const CURATED_INCLUDED_LEAGUE_IDS = new Set(['536']);
const CURATED_EXCLUDED_LEAGUE_IDS = new Set(['9741']);
const CURATED_EXCLUDED_LEAGUE_NAMES = /\bUEFA Youth League\b/i;
const FOTMOB_USER_AGENT =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';
const TIME_ZONE = 'Asia/Jakarta';

const EXTENSION_ID = globalThis.__nimoraExtensionId || 'nimora';
const PROVIDER_ID = 'nimora.matches';

// The one catalog this extension declares, and the categories inside it.
// `live` is based on FotMob's match status; `schedule` is the daily match
// schedule. `all` includes the live football items alongside the other live
// sports catalog entries.
const CATALOG_ID = 'fixtures';
const SCHEDULE_CATALOG_ID = 'fixtures_schedule';
const FEATURED_CATALOG_ID = 'fixtures_featured';
const LIVE_CATEGORY = 'live';
const ALL_CATEGORY = 'all';

// Unfinished fixtures remain relevant while live and up to a week before
// kickoff. Finished fixtures remain for two days so the timeline can show
// yesterday's history.
const UPCOMING_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
// Keep yesterday's completed events in the timeline so the previous date
// remains visible after the live window rolls over.
const RECENT_WINDOW_MS = 48 * 60 * 60 * 1000;
const FIXTURES_TTL_MS = 15 * 60 * 1000;
const LEAGUE_BRANDING_TTL_MS = 24 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const JAKARTA_OFFSET_MS = 7 * 60 * 60 * 1000;

// These durations are deliberately conservative event windows, not claims
// about the exact final whistle or checkered flag. Providers can override
// them when an upstream end time becomes available.
const EVENT_DURATION_MINUTES = [
  { match: /fighting|boxing|ufc|mma|wwe|wrestling|combat|kickboxing/i, minutes: 240 },
  { match: /motorsport|formula\s*1|motogp|nascar|wrc|racing/i, minutes: 210 },
  { match: /american football|nfl/i, minutes: 210 },
  { match: /cricket/i, minutes: 240 },
  { match: /tennis/i, minutes: 180 },
  { match: /basketball|nba|wnba/i, minutes: 150 },
  { match: /volleyball/i, minutes: 135 },
  { match: /badminton|bwf/i, minutes: 120 },
  { match: /football|soccer/i, minutes: 135 },
];
const DEFAULT_EVENT_DURATION_MINUTES = 180;

function eventDurationMinutes(sportName, title) {
  const identity = `${sportName || ''} ${title || ''}`;
  return EVENT_DURATION_MINUTES.find((entry) => entry.match.test(identity))
    ?.minutes || DEFAULT_EVENT_DURATION_MINUTES;
}

function eventSchedule(startsAt, state, sportName, title, explicitEndsAt = null) {
  const startsAtMs = startsAt instanceof Date
    ? startsAt.getTime()
    : typeof startsAt === 'number' ? startsAt : Date.parse(startsAt);
  const explicitEndMs = explicitEndsAt instanceof Date
    ? explicitEndsAt.getTime()
    : typeof explicitEndsAt === 'number'
        ? explicitEndsAt
        : Date.parse(explicitEndsAt);
  const endsAtMs = Number.isFinite(explicitEndMs) && explicitEndMs > startsAtMs
    ? explicitEndMs
    : startsAtMs + eventDurationMinutes(sportName, title) * 60 * 1000;
  return {
    startsAt: new Date(startsAtMs).toISOString(),
    endsAt: new Date(endsAtMs).toISOString(),
    state,
  };
}

// Editorial ranking for globally recognisable clubs. FotMob ids are the
// primary key; aliases cover alternate names returned by football feeds. This
// belongs to the extension because the shell must not know what
// counts as a top football club.
const TOP_CLUBS = [
  { id: '8634', aliases: ['barcelona', 'fc barcelona', 'barca', 'barça'] },
  { id: '8650', aliases: ['liverpool', 'liverpool fc'] },
  { id: '8633', aliases: ['real madrid', 'real madrid cf'] },
  { id: '8456', aliases: ['manchester city', 'man city'] },
  { id: '9825', aliases: ['arsenal', 'arsenal fc'] },
  { id: '10260', aliases: ['manchester united', 'man united', 'man utd'] },
  { id: '9823', aliases: ['bayern munich', 'bayern munchen', 'fc bayern'] },
  {
    id: '9847',
    aliases: ['paris saint-germain', 'paris saint germain', 'psg'],
  },
  { id: '8636', aliases: ['inter milan', 'internazionale', 'inter'] },
  { id: '9885', aliases: ['juventus', 'juve'] },
];

const TOP_CLUB_BY_ID = new Map(
  TOP_CLUBS.map((club, index) => [club.id, index]),
);
const TOP_CLUB_BY_NAME = new Map(
  TOP_CLUBS.flatMap((club, index) =>
    club.aliases.map((alias) => [alias, index]),
  ),
);

// How long a match is assumed to still be in play after kickoff when the
// upstream status has no explicit ongoing flag.
const ASSUMED_MATCH_DURATION_MS = 130 * 60 * 1000;

// --- fetch ---

function fotmobDateKey(nowMs, dayOffset) {
  const shifted = new Date(nowMs + JAKARTA_OFFSET_MS + dayOffset * DAY_MS);
  return `${shifted.getUTCFullYear()}${String(shifted.getUTCMonth() + 1).padStart(2, '0')}${String(shifted.getUTCDate()).padStart(2, '0')}`;
}

async function fetchFotmobMatchesForDate(dateKey) {
  const url =
    `${FOTMOB_BASE}/api/data/matches?date=${dateKey}` +
    `&timezone=${encodeURIComponent(TIME_ZONE)}` +
    `&ccode3=${encodeURIComponent(FOTMOB_CCODE3)}` +
    '&includeNextDayLateNight=true';
  const response = await fetch(url, {
    headers: {
      'User-Agent': FOTMOB_USER_AGENT,
      Accept: 'application/json, text/plain, */*',
      Referer: `${FOTMOB_BASE}/?show=ongoing`,
    },
  });
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Request to matches failed: ${response.status}`);
  }
  const data = JSON.parse(response.body);
  if (
    typeof data !== 'object' ||
    data === null ||
    !Array.isArray(data.leagues)
  ) {
    throw new Error('matches response has no leagues');
  }
  return data;
}

async function fetchFotmobPopularLeagues() {
  const url =
    `${FOTMOB_BASE}/api/data/allLeagues?locale=en` +
    `&country=${encodeURIComponent(FOTMOB_LEAGUE_COUNTRY)}`;
  const response = await fetch(url, {
    headers: {
      'User-Agent': FOTMOB_USER_AGENT,
      Accept: 'application/json, text/plain, */*',
      Referer: `${FOTMOB_BASE}/`,
    },
  });
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Request to league list failed: ${response.status}`);
  }
  const data = JSON.parse(response.body);
  if (
    typeof data !== 'object' ||
    data === null ||
    !Array.isArray(data.popular)
  ) {
    throw new Error('league list response has no popular leagues');
  }
  return flattenFotmobLeagueList(data);
}

function flattenFotmobLeagueList(data) {
  const popular = Array.isArray(data?.popular) ? data.popular : [];
  const international = Array.isArray(data?.international)
    ? data.international.flatMap((group) =>
      Array.isArray(group?.leagues) ? group.leagues : [],
    )
    : [];
  return [...popular, ...international];
}

function validFotmobColor(value) {
  return typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value)
    ? value
    : null;
}

function leagueIdKey(value) {
  if (value == null) return null;
  const key = String(value).trim();
  return /^\d+$/.test(key) ? key : null;
}

function brandingLeagueId(match) {
  return leagueIdKey(match.primaryLeagueId) || leagueIdKey(match.leagueId);
}

function footballLeagueIds(match) {
  return [match.leagueId, match.primaryLeagueId, match.primaryId]
    .map((id) => leagueIdKey(id))
    .filter((id) => id != null);
}

function isCuratedExcludedLeague(match) {
  return footballLeagueIds(match).some((id) => CURATED_EXCLUDED_LEAGUE_IDS.has(id)) ||
    CURATED_EXCLUDED_LEAGUE_NAMES.test(`${match.leagueName || ''}`);
}

function fetchFotmobLeagueBranding(leagueId) {
  const key = leagueIdKey(leagueId);
  if (key == null) return Promise.resolve(null);

  const nowMs = Date.now();
  const cached = leagueBrandingMemo.get(key);
  if (cached != null && nowMs - cached.fetchedAt < LEAGUE_BRANDING_TTL_MS) {
    return cached.promise;
  }

  const logo = { url: leagueLogoUrl(key) };
  const promise = fetch(
    `${FOTMOB_BASE}/api/data/leagues?id=${encodeURIComponent(key)}`,
    {
      headers: {
        'User-Agent': FOTMOB_USER_AGENT,
        Accept: 'application/json, text/plain, */*',
        Referer: `${FOTMOB_BASE}/leagues/${key}`,
      },
    },
  )
    .then((response) => {
      if (response.status < 200 || response.status >= 300) return { logo };
      const data = JSON.parse(response.body);
      const color = validFotmobColor(data?.details?.leagueColor);
      return color == null ? { logo } : { logo, primaryColor: color };
    })
    .catch(() => ({ logo }));

  leagueBrandingMemo.set(key, { promise, fetchedAt: nowMs });
  return promise;
}

async function leagueBrandingFor(matches) {
  const keys = [
    ...new Set(
      matches
        .map((match) => brandingLeagueId(match))
        .filter((key) => key != null),
    ),
  ];
  const entries = await Promise.all(
    keys.map(async (key) => [key, await fetchFotmobLeagueBranding(key)]),
  );
  return new Map(entries.filter((entry) => entry[1] != null));
}

// The daily match feed is fetched for today plus the next seven Jakarta dates.
// Deduplication below handles the endpoint's next-day late-night overlap.
let fixturesMemo = null;
let popularLeaguesMemo = null;
const leagueBrandingMemo = new Map();

function fetchFixturesMemo(nowMs) {
  if (
    fixturesMemo === null ||
    nowMs - fixturesMemo.fetchedAt >= FIXTURES_TTL_MS
  ) {
    const promise = fetchFotmobMatches(nowMs).catch((e) => {
      fixturesMemo = null;
      throw e;
    });
    fixturesMemo = { promise, fetchedAt: nowMs };
  }
  return fixturesMemo.promise;
}

function fetchPopularLeaguesMemo() {
  if (popularLeaguesMemo === null) {
    popularLeaguesMemo = fetchFotmobPopularLeagues().catch((e) => {
      popularLeaguesMemo = null;
      throw e;
    });
  }
  return popularLeaguesMemo;
}

async function fetchFotmobMatches(nowMs) {
  // FotMob's current-day feed can omit an earlier match once it is no longer
  // part of the late-night carryover. Keep one Jakarta calendar day of
  // lookback so a provider cannot re-introduce an already-known FotMob event
  // as a provider-only card.
  const payloads = await Promise.all(
    Array.from({ length: 9 }, (_, index) =>
      fetchFotmobMatchesForDate(fotmobDateKey(nowMs, index - 1)),
    ),
  );
  const matchesById = new Map();
  for (const payload of payloads) {
    for (const match of flattenFotmobMatches(payload)) {
      const key = match.id == null
        ? `${match.leagueId}:${match.utcTime}:${match.home?.name}:${match.away?.name}`
        : String(match.id);
      if (!matchesById.has(key)) matchesById.set(key, match);
    }
  }
  return [...matchesById.values()];
}

// The daily response is `{ leagues: [{ id, primaryId, name, matches: [...] }] }`.
// Match status and kickoff are already provided by FotMob, so no second live
// feed or team-name reconciliation is needed.
function flattenFotmobMatches(data) {
  const matches = [];
  for (const league of data.leagues) {
    const leagueMatches = Array.isArray(league.matches) ? league.matches : [];
    for (const match of leagueMatches) {
      const status = match.status || {};
      matches.push({
        ...match,
        leagueName: match.leagueName || league.name,
        leagueId: match.leagueId != null ? match.leagueId : league.id,
        primaryLeagueId: match.primaryLeagueId != null
          ? match.primaryLeagueId
          : (match.primaryId != null ? match.primaryId : league.primaryId),
        utcTime: match.utcTime || status.utcTime,
        isLive: status.ongoing === true,
        isFinished: status.finished === true,
      });
    }
  }
  return matches;
}

// Filter the complete daily match feed by FotMob's popular and international
// league lists. This filters visibility only; all match metadata still comes
// from `/api/data/matches`.
function filterPopularMatches(matches, popularLeagues) {
  const allowedIds = new Set(
    popularLeagues
      .flatMap((league) =>
        league == null ? [] : [league.id, league.primaryId],
      )
      .filter((id) => id != null)
      .map((id) => String(id)),
  );
  return matches.filter(
    (match) => {
      if (isCuratedExcludedLeague(match)) return false;
      const ids = footballLeagueIds(match);
      return ids.some((id) =>
        allowedIds.has(id) || CURATED_INCLUDED_LEAGUE_IDS.has(id),
      );
    },
  );
}

function isWomenMatch(match) {
  const womenSuffix = /\s\(W\)$/i;
  const womenLeague = /\b(women|woman|female|ladies|girls)\b/i;
  const homeName = match.home && (match.home.longName || match.home.name);
  const awayName = match.away && (match.away.longName || match.away.name);
  return womenLeague.test(`${match.leagueName || ''}`) ||
    womenSuffix.test(`${homeName || ''}`) ||
    womenSuffix.test(`${awayName || ''}`);
}

function isFinishedMatch(match) {
  return match.isFinished === true || match.status?.finished === true;
}

// FotMob abbreviates some club names in its daily response. Keep verified
// aliases for the editorial top-club ranking.
const CLUB_NAME_ALIASES = {
  'nottm forest': 'nottingham forest',
  'man utd': 'manchester united',
  'man united': 'manchester united',
  'man city': 'manchester city',
  spurs: 'tottenham hotspur',
  wolves: 'wolverhampton wanderers',
  'west brom': 'west bromwich albion',
  'west bromwich': 'west bromwich albion',
};

function normalizedClubName(team) {
  const normalized = `${team && (team.longName || team.name) || ''}`
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\s+/g, ' ');
  return CLUB_NAME_ALIASES[normalized] || normalized;
}

function topClubRank(team) {
  if (team == null) return null;
  if (team.id != null) {
    const rankById = TOP_CLUB_BY_ID.get(String(team.id));
    if (rankById != null) return rankById;
  }
  const rankByName = TOP_CLUB_BY_NAME.get(normalizedClubName(team));
  return rankByName == null ? null : rankByName;
}

function topClubMatchRank(match) {
  const ranks = [topClubRank(match.home), topClubRank(match.away)]
    .filter((rank) => rank != null);
  if (ranks.length === 0) return null;
  return {
    clubs: ranks.length,
    rank: Math.min(...ranks),
  };
}

// Maps the editorial club rank onto the generic protocol rating consumed by
// the app's Featured Hero. A fixture involving both configured clubs gets a
// small bonus, while the ordered list still makes Barcelona rank above
// Liverpool and the remaining clubs.
function topClubEditorialRating(match) {
  const priority = topClubMatchRank(match);
  if (priority == null) return null;
  const clubScore = TOP_CLUBS.length - priority.rank;
  const fixtureBonus = priority.clubs > 1 ? 0.5 : 0;
  return clubScore + fixtureBonus;
}

// Competition context makes the same club pairing slightly more important in
// a major tournament or domestic top flight. Keep this as a small modifier so
// club identity remains the primary signal and the result stays a generic
// 0-10-ish media rating rather than pretending to be a fan-vote score.
const HIGH_PROFILE_COMPETITIONS = [
  { match: /champions league|uefa champions league|ucl/i, bonus: 0.5 },
  { match: /premier league|la\s*liga|serie a|bundesliga|ligue 1/i, bonus: 0.25 },
];

function competitionEditorialBonus(match) {
  const leagueName = `${match.leagueName || ''}`;
  return HIGH_PROFILE_COMPETITIONS.find((entry) => entry.match.test(leagueName))
    ?.bonus || 0;
}

function footballEditorialRating(match) {
  const clubRating = topClubEditorialRating(match);
  const competitionBonus = competitionEditorialBonus(match);
  if (clubRating == null) return competitionBonus > 0 ? 5 + competitionBonus : null;
  return clubRating + competitionBonus;
}

// Keep FotMob's response order as the default. A fixture involving two
// configured top clubs comes first, followed by fixtures involving one; ties
// retain their original response order. This gives the app a useful editorial
// lead without replacing the upstream schedule with a hardcoded league order.
function prioritizeTopClubMatches(matches) {
  return matches
    .map((match, index) => ({
      match,
      index,
      priority: topClubMatchRank(match),
    }))
    .sort((a, b) => {
      if (a.priority == null && b.priority == null) return a.index - b.index;
      if (a.priority == null) return 1;
      if (b.priority == null) return -1;
      if (a.priority.clubs !== b.priority.clubs) {
        return b.priority.clubs - a.priority.clubs;
      }
      if (a.priority.rank !== b.priority.rank) {
        return a.priority.rank - b.priority.rank;
      }
      return a.index - b.index;
    })
    .map((entry) => entry.match);
}

// --- status / relevance ---

function kickoffMs(match) {
  if (match.utcTime == null) return null;
  const parsed = new Date(match.utcTime);
  return isNaN(parsed.getTime()) ? null : parsed.getTime();
}

function isMatchLive(match, nowMs) {
  if (match.isLive === true) return true;
  if (match.isFinished === true || match.status?.finished === true) return false;
  if (match.status?.cancelled === true) return false;
  const start = kickoffMs(match);
  if (start == null) return false;
  return nowMs >= start && nowMs <= start + ASSUMED_MATCH_DURATION_MS;
}

function isRelevantMatch(match, nowMs) {
  if (isMatchLive(match, nowMs)) return true;
  const start = kickoffMs(match);
  // No kickoff to judge by — keep it rather than discard data this can't
  // evaluate.
  if (start == null) return true;
  const untilStart = start - nowMs;
  return untilStart <= UPCOMING_WINDOW_MS && untilStart >= -RECENT_WINDOW_MS;
}

// --- mapping ---

function fotmobRefId(matchId) {
  return `fotmob:${matchId}`;
}

function footballRefId(match) {
  return fotmobRefId(match.id);
}

function teamLogoUrl(teamId) {
  return `${FOTMOB_IMAGE_BASE}/${teamId}_large.png`;
}

function leagueLogoUrl(leagueId) {
  if (leagueId == null) return null;
  const key = String(leagueId).trim();
  if (!/^\d+$/.test(key)) return null;
  return `${FOTMOB_LEAGUE_IMAGE_BASE}/${key}.png`;
}

function fotmobParticipantsOf(match) {
  const home = match.home;
  const away = match.away;
  const teamName = (team) => team?.name || team?.longName || team?.shortName;
  if (home == null || away == null || teamName(home) == null || teamName(away) == null) {
    return [];
  }
  const side = (team) => {
    const p = { name: teamName(team) };
    const teamId = team.id ?? team.teamId ?? team.team?.id;
    if (teamId != null) p.logo = { url: teamLogoUrl(teamId) };
    if (team.shortName != null) p.shortName = team.shortName;
    return p;
  };
  return [side(home), side(away)];
}

function toMediaItem(match, nowMs, brandingByLeague) {
  const home = match.home || {};
  const away = match.away || {};
  if (match.utcTime == null || kickoffMs(match) == null) return null;
  const item = {
    ref: {
      extensionId: EXTENSION_ID,
      providerId: PROVIDER_ID,
      id: footballRefId(match),
    },
    kind: 'event',
    title: `${home.name == null ? 'Unknown' : home.name} vs ${
      away.name == null ? 'Unknown' : away.name
    }`,
    schedule: eventSchedule(
      kickoffMs(match),
      isFinishedMatch(match)
        ? 'ended'
        : isMatchLive(match, nowMs)
          ? 'live'
          : 'scheduled',
      FOOTBALL.name,
      `${home.name == null ? 'Unknown' : home.name} vs ${
        away.name == null ? 'Unknown' : away.name
      }`,
      match.endsAt || match.endTime || match.status?.endTime,
    ),
  };

  const editorialRating = footballEditorialRating(match);
  if (editorialRating != null) item.rating = editorialRating;

  if (match.leagueName != null) item.subtitle = match.leagueName;
  const participants = fotmobParticipantsOf(match);
  if (participants.length > 0) item.participants = participants;
  const branding = brandingByLeague?.get(brandingLeagueId(match));
  if (branding != null) item.branding = branding;

  return item;
}

// Indonesia observes no daylight saving, so a fixed UTC+7 offset gives the
// exact Asia/Jakarta calendar day with no Intl/timezone database needed in
// this engine.
const WEEKDAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTH_NAMES = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

function jakartaDayIndex(ms) {
  return Math.floor((ms + JAKARTA_OFFSET_MS) / DAY_MS);
}

function jakartaDateLabel(ms) {
  const shifted = new Date(ms + JAKARTA_OFFSET_MS);
  return `${WEEKDAY_NAMES[shifted.getUTCDay()]}, ${shifted.getUTCDate()} ` +
    MONTH_NAMES[shifted.getUTCMonth()];
}

// Chronological order, editorial ranking (prioritizeTopClubMatches) and
// league order set aside: a viewer expects the same "what's on soonest"
// order everywhere football is shown, not just inside the dedicated Football
// subcategory page. Drops entries with no usable kickoff, same as byDate.
function sortedByKickoff(matches) {
  return matches
    .map((match) => ({ match, kickoff: kickoffMs(match) }))
    .filter((entry) => entry.kickoff != null)
    .sort((a, b) => a.kickoff - b.kickoff);
}

// Groups by kickoff day rather than league: league order says nothing about
// when a fixture kicks off, so a distant match from a league that happens to
// come first in the feed could otherwise show ahead of one kicking off soon.
function byDate(matches, nowMs, brandingByLeague) {
  const items = matches
    .map((match) => toMediaItem(match, nowMs, brandingByLeague))
    .filter((item) => item != null);
  return byDateItems(items, nowMs);
}

function byDateItems(items, nowMs) {
  const todayIndex = jakartaDayIndex(nowMs);
  const buckets = new Map();
  const sorted = items
    .map((item) => ({
      item,
      kickoff: Date.parse(item.schedule && item.schedule.startsAt),
    }))
    .filter((entry) => Number.isFinite(entry.kickoff))
    .sort((a, b) => a.kickoff - b.kickoff);
  for (const entry of sorted) {
    const dayIndex = jakartaDayIndex(entry.kickoff);
    let bucket = buckets.get(dayIndex);
    if (bucket == null) {
      bucket = [];
      buckets.set(dayIndex, bucket);
    }
    bucket.push(entry);
  }

  const sections = [];
  for (const dayIndex of [...buckets.keys()].sort((a, b) => a - b)) {
    // The sorted item list already put these in kickoff order; the Map bucket
    // preserves that insertion order, so no second sort is needed here.
    const entries = buckets.get(dayIndex);
    if (entries.length === 0) continue;
    const offset = dayIndex - todayIndex;
    const title =
      offset === 0 ? 'Today'
      : offset === 1 ? 'Tomorrow'
      : offset === -1 ? 'Yesterday'
      : jakartaDateLabel(entries[0].kickoff);
    sections.push({
      id: `date:${dayIndex}`,
      title,
      items: entries.map((entry) => entry.item),
    });
  }
  return sections;
}

// --- catalog navigation ---

const FOOTBALL = { id: 'football', name: 'Football' };
const TENNIS = { id: 'tennis', name: 'Tennis' };
const MOTORSPORT = { id: 'motorsport', name: 'Motorsport' };
const FIGHTING = { id: 'fighting', name: 'Fighting' };
const BADMINTON = { id: 'badminton', name: 'Badminton' };
const BASKETBALL = { id: 'basketball', name: 'Basketball' };
const VOLLEYBALL = { id: 'volleyball', name: 'Volleyball' };
const OTHER_LIVE_SPORTS = {
  id: 'other-live-sports',
  name: 'Other Live Sports',
};

// Keep the Sport page predictable while allowing new upstream categories to
// arrive without creating a new shelf for every spelling or niche sport.
const SPORT_SECTION_ORDER = [
  FOOTBALL,
  TENNIS,
  MOTORSPORT,
  FIGHTING,
  BADMINTON,
  BASKETBALL,
  VOLLEYBALL,
  OTHER_LIVE_SPORTS,
];

function sportIdOf(name) {
  const value = `${name || ''}`.trim().toLowerCase();
  if (value.includes('football') || value.includes('soccer')) {
    return FOOTBALL.id;
  }
  if (value.includes('tennis') || /\batp\b|\bwta\b/.test(value)) {
    return TENNIS.id;
  }
  if (
    value.includes('fighting') ||
    value.includes('boxing') ||
    value.includes('mma') ||
    value.includes('ufc') ||
    value.includes('wwe') ||
    value.includes('wrestling') ||
    value.includes('combat') ||
    value.includes('kickboxing')
  ) {
    return FIGHTING.id;
  }
  if (
    value.includes('motorsport') ||
    value.includes('formula') ||
    value.includes('racing') ||
    value.includes('motogp') ||
    value.includes('nascar') ||
    value.includes('wrc')
  ) {
    return MOTORSPORT.id;
  }
  if (value.includes('badminton') || value.includes('bwf')) {
    return BADMINTON.id;
  }
  if (value.includes('basketball') || /\bnba\b|\bwnba\b/.test(value)) {
    return BASKETBALL.id;
  }
  if (value.includes('volleyball')) return VOLLEYBALL.id;
  return OTHER_LIVE_SPORTS.id;
}

function sportNameOf(name) {
  const id = sportIdOf(name);
  return SPORT_SECTION_ORDER.find((sport) => sport.id === id).name;
}

function isFootballCategory(category) {
  const name = `${category || ''}`.toLowerCase();
  return name.includes('football') || name.includes('soccer');
}

function isExcludedSportCategory(category) {
  const name = `${category || ''}`.toLowerCase();
  return (
    name.includes('cricket') ||
    name.includes('baseball') ||
    name.includes('rugby') ||
    name === 'mlb' ||
    name === 'nfl' ||
    name.includes('american football')
  );
}

const FOOTBALL_DEDUPE_WINDOW_MS = 6 * 60 * 60 * 1000;

function footballNameKey(value) {
  return `${value || ''}`
    .toLowerCase()
    .replace(/&amp;/g, '&')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\b(fc|afc|cf|sc|ac|cd)\b/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const AMBIGUOUS_FOOTBALL_NAMES = new Set([
  'united', 'city', 'town', 'rovers', 'wanderers', 'albion', 'athletic',
  'county', 'real', 'atletico', 'sporting', 'dynamo', 'racing', 'olympique',
]);

const FOOTBALL_NAME_ALIASES = new Map([
  ['atleti', 'atletico madrid'],
  ['barca', 'barcelona'],
  ['birmingham', 'birmingham city'],
  ['derby', 'derby county'],
  ['hsv', 'hamburger sv'],
  ['inter', 'internazionale'],
  ['juve', 'juventus'],
  ['leipzig', 'rb leipzig'],
  ['man city', 'manchester city'],
  ['man united', 'manchester united'],
  ['man utd', 'manchester united'],
  ['nottm forest', 'nottingham forest'],
  ['psg', 'paris saint germain'],
  ['qpr', 'queens park rangers'],
  ['sheff utd', 'sheffield united'],
  ['sheffield utd', 'sheffield united'],
  ['spurs', 'tottenham hotspur'],
  ['west brom', 'west bromwich albion'],
  ['west bromwich', 'west bromwich albion'],
  ['wolves', 'wolverhampton wanderers'],
]);

function footballNameMatches(first, second) {
  first = FOOTBALL_NAME_ALIASES.get(first) || first;
  second = FOOTBALL_NAME_ALIASES.get(second) || second;
  if (first === second) return true;
  const shorter = first.length <= second.length ? first : second;
  const longer = first.length <= second.length ? second : first;
  if (
    shorter.length < 5 ||
    AMBIGUOUS_FOOTBALL_NAMES.has(shorter)
  ) {
    return false;
  }
  return longer.startsWith(`${shorter} `) || longer.endsWith(` ${shorter}`);
}

function footballParticipantsMatch(first, second) {
  if (!Array.isArray(first?.participants) ||
      !Array.isArray(second?.participants) ||
      first.participants.length !== 2 ||
      second.participants.length !== 2) {
    return false;
  }
  const firstNames = first.participants.map((participant) =>
    footballNameKey(participant?.name));
  const secondNames = second.participants.map((participant) =>
    footballNameKey(participant?.name));
  return (
    footballNameMatches(firstNames[0], secondNames[0]) &&
    footballNameMatches(firstNames[1], secondNames[1])
  ) || (
    footballNameMatches(firstNames[0], secondNames[1]) &&
    footballNameMatches(firstNames[1], secondNames[0])
  );
}

function sameFootballEvent(first, second) {
  if (!footballParticipantsMatch(first, second)) return false;
  const firstKickoff = Date.parse(first.schedule?.startsAt);
  const secondKickoff = Date.parse(second.schedule?.startsAt);
  return Number.isFinite(firstKickoff) && Number.isFinite(secondKickoff) &&
    Math.abs(firstKickoff - secondKickoff) <= FOOTBALL_DEDUPE_WINDOW_MS;
}

function isFootballEntry(entry) {
  return sportIdOf(entry.sportName || entry.sportId) === FOOTBALL.id;
}

function isFotmobItem(item) {
  return `${item?.ref?.id || ''}`.startsWith('fotmob:');
}

// FotMob remains the canonical metadata source. Provider-only football events
// are appended after it, and any matching provider event is discarded so the
// FotMob title, branding, participants, status, and editorial ranking win.
function footballCatalogItems(
  matches,
  entries,
  nowMs,
  brandingByLeague,
  requireProviderMatch = false,
  knownFotmobMatches = matches,
) {
  let items = matches
    .map((match) => toMediaItem(match, nowMs, brandingByLeague))
    .filter((item) => item != null);
  const knownFotmobItems = knownFotmobMatches
    .map((match) => toMediaItem(match, nowMs, brandingByLeague))
    .filter((item) => item != null);
  if (requireProviderMatch) {
    items = items.filter((item) =>
      entries.some((entry) => sameFootballEvent(item, entry.item)));
  }
  for (const entry of entries.filter(isFootballEntry)) {
    const item = entry.item;
    if (
      item == null ||
      knownFotmobItems.some((existing) => sameFootballEvent(existing, item)) ||
      items.some((existing) => sameFootballEvent(existing, item))
    ) {
      continue;
    }
    items.push(item);
  }
  return items.sort(
    (first, second) => Date.parse(first.schedule?.startsAt) -
      Date.parse(second.schedule?.startsAt),
  );
}

function cricfyArtworkUrl(value) {
  const url = `${value || ''}`.trim();
  return /^https?:\/\/[^\s/?#]+(?:[/?#][^\s]*)?$/i.test(url) ? url : null;
}

function cricfyEventItem(event, status) {
  let title = `${event.eventName || ''}`.trim();
  const teamA = `${event.teamAName || ''}`.trim();
  const teamB = `${event.teamBName || ''}`.trim();
  const versus = teamA.length > 0 && teamB.length > 0 && teamA !== teamB;
  if (versus) title = `${teamA} vs ${teamB}`;
  if (title.length === 0 || event.linksPath.length === 0) return null;

  const startsAt = cricfyParseEventDateTime(event.date, event.time);
  if (startsAt === null) return null;
  const eventLogo = cricfyArtworkUrl(event.eventLogo);
  const teamALogo = cricfyArtworkUrl(event.teamALogo);
  const teamBLogo = cricfyArtworkUrl(event.teamBLogo);
  const item = {
    ref: {
      extensionId: EXTENSION_ID,
      providerId: PROVIDER_ID,
      id: `cricfy:${event.linksPath}`,
    },
    kind: 'event',
    title,
    subtitle: event.category || 'Other',
    schedule: eventSchedule(
      startsAt,
      status === 'live'
        ? 'live'
        : status === 'ended'
          ? 'ended'
          : 'scheduled',
      event.category || 'Other',
      title,
      event.endsAt || event.endTime,
    ),
  };
  if (eventLogo !== null) {
    item.artwork = { landscape: { url: eventLogo } };
  }
  if (versus) {
    item.participants = [
      {
        name: teamA,
        ...(teamALogo !== null ? { logo: { url: teamALogo } } : {}),
      },
      {
        name: teamB,
        ...(teamBLogo !== null ? { logo: { url: teamBLogo } } : {}),
      },
    ];
  }
  return item;
}

async function getCricfySportEntries(nowMs) {
  if (typeof cricfyFetchEventsMemo !== 'function') return [];
  try {
    const events = await cricfyFetchEventsMemo(nowMs);
    const entries = [];
    for (const event of events) {
      if (!event.visible) continue;
      if (isExcludedSportCategory(event.category)) continue;

      const eventTitle = `${event.teamAName || ''} vs ${event.teamBName || ''}`;
      const status = cricfyEventStatusAt(
        event,
        nowMs,
        eventDurationMinutes(event.category, eventTitle),
      );
      const startsAt = cricfyParseEventDateTime(event.date, event.time);
      if (
        status === 'ended' &&
        (startsAt === null || nowMs - startsAt.getTime() > RECENT_WINDOW_MS)
      ) continue;
      if (
        status !== 'live' &&
        startsAt !== null &&
        startsAt.getTime() - nowMs > UPCOMING_WINDOW_MS
      ) continue;

      const item = cricfyEventItem(event, status);
      if (item === null) continue;
      const sportName = sportNameOf(event.category || 'Other');
      entries.push({
        sportId: sportIdOf(event.category || 'Other'),
        sportName,
        live: status === 'live',
        item,
      });
    }
    return entries;
  } catch (_) {
    return [];
  }
}

async function getRoxieSportEntries(nowMs) {
  if (typeof globalThis.__roxieSportEntries !== 'function') return [];
  try {
    return await globalThis.__roxieSportEntries(nowMs);
  } catch (_) {
    return [];
  }
}

async function getCdnLiveTvSportEntries(nowMs) {
  if (typeof globalThis.__cdnLiveTvSportEntries !== 'function') return [];
  try {
    return await globalThis.__cdnLiveTvSportEntries(nowMs);
  } catch (_) {
    return [];
  }
}

function catalogTitleKey(value) {
  return `${value || ''}`
    .toLowerCase()
    .replace(/&amp;/g, '&')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .replace(/\bformula one\b|\bf1\b/g, 'formula 1')
    .replace(/\bmoto gp\b/g, 'motogp')
    .replace(/^spotv race zone\s*[:|-]?\s*/, '')
    .replace(/\bmotogp\b/g, 'grand prix')
    .replace(/\bformula one\b|\bf1\b/g, 'formula 1')
    .replace(/\bgp\b/g, 'grand prix')
    .replace(/\b(live tracking|on board\d*|helicam|live timing|coverage|warmup|race zone|race)\b/g, '')
    .replace(/\bgrand prix\s+grand prix\b/g, 'grand prix')
    .replace(/\s+/g, ' ')
    .trim();
}

function sameProviderEvent(first, second) {
  const firstKickoff = Date.parse(first.item?.schedule?.startsAt);
  const secondKickoff = Date.parse(second.item?.schedule?.startsAt);
  if (!Number.isFinite(firstKickoff) || !Number.isFinite(secondKickoff)) {
    return false;
  }
  const sameTeams = footballParticipantsMatch(first.item, second.item);
  const sameTitle = catalogTitleKey(first.item?.title) ===
    catalogTitleKey(second.item?.title);
  return (sameTeams || sameTitle) &&
    Math.abs(firstKickoff - secondKickoff) <= FOOTBALL_DEDUPE_WINDOW_MS;
}

function providerEntryIsLive(entry, nowMs) {
  if (entry?.live !== true) return false;
  const schedule = entry.item?.schedule;
  const startsAt = Date.parse(schedule?.startsAt);
  const endsAt = Date.parse(schedule?.endsAt);
  // A provider may refresh its stream flag before refreshing the countdown.
  // Never expose a future item in Live when its start time is known.
  if (Number.isFinite(endsAt) && nowMs >= endsAt) return false;
  return !Number.isFinite(startsAt) || startsAt <= nowMs;
}

function providerEntryStartMs(entry) {
  const startsAt = Date.parse(entry.item?.schedule?.startsAt);
  return Number.isFinite(startsAt) ? startsAt : null;
}

function normalizeProviderEntry(entry, nowMs) {
  const live = providerEntryIsLive(entry, nowMs);
  const schedule = entry.item?.schedule;
  if (schedule == null) return { ...entry, live };
  const state = live
    ? 'live'
    : schedule.state === 'ended'
      ? 'ended'
      : 'scheduled';
  return {
    ...entry,
    live,
    item: {
      ...entry.item,
      schedule: {
        ...schedule,
        state,
      },
    },
  };
}

// Provider-backed catalog contributors are merged by event identity. The
// earliest known kickoff wins the displayed metadata, while live status is
// merged so the retained card remains current when providers refresh at
// slightly different times.
function dedupeProviderEntries(entries, nowMs = Date.now()) {
  const result = [];
  for (const entry of entries.map((value) => normalizeProviderEntry(value, nowMs))) {
    const existingIndex = result.findIndex((candidate) =>
      sameProviderEvent(candidate, entry));
    const existing = existingIndex === -1 ? null : result[existingIndex];
    if (existing == null) {
      result.push(entry);
      continue;
    }

    const existingStart = providerEntryStartMs(existing);
    const entryStart = providerEntryStartMs(entry);
    const preferEntry = entryStart != null &&
      (existingStart == null || entryStart < existingStart);
    const merged = preferEntry ? { ...entry } : { ...existing };
    merged.live = existing.live || entry.live;
    if (merged.item?.schedule != null) {
      const mergedState = merged.live
        ? 'live'
        : (existing.item?.schedule?.state === 'ended' ||
            entry.item?.schedule?.state === 'ended')
          ? 'ended'
          : 'scheduled';
      merged.item = {
        ...merged.item,
        schedule: {
          ...merged.item.schedule,
          state: mergedState,
        },
      };
    }
    result[existingIndex] = merged;
  }
  return result;
}

function sportsOf(matches, providerEntries) {
  const sports = [];
  const available = new Set();
  if (matches.length > 0) available.add(FOOTBALL.id);
  for (const entry of providerEntries) {
    available.add(sportIdOf(entry.sportName || entry.sportId));
  }
  for (const sport of SPORT_SECTION_ORDER) {
    if (available.has(sport.id)) sports.push(sport);
  }
  return sports;
}

function buildPage(
  query,
  matches,
  providerEntries,
  nowMs,
  brandingByLeague,
  requireLiveProviderMatches = false,
  knownFotmobMatches = matches,
) {
  const liveCategory = query.category === LIVE_CATEGORY;
  const excludeEnded = liveCategory && query.catalogId !== SCHEDULE_CATALOG_ID;
  providerEntries = providerEntries.map((entry) =>
    normalizeProviderEntry(entry, nowMs));
  const selected = query.subCategory == null
    ? null
    : sportIdOf(query.subCategory);
  const subCategories = sportsOf(matches, providerEntries);

  // Home's Featured Hero loads catalogs registered for the global `all`
  // category. Keep this separate from the Live Now catalog: a scheduled
  // big match should be eligible for the hero without being mislabeled live.
  if (query.catalogId === FEATURED_CATALOG_ID && query.category === ALL_CATEGORY) {
    const items = footballCatalogItems(
      matches,
      providerEntries,
      nowMs,
      brandingByLeague,
      false,
      knownFotmobMatches,
    )
      .filter((item) => item.schedule?.state !== 'ended')
      .filter((item) => Number(item.rating) >= 8)
      .sort((first, second) =>
        Number(second.rating) - Number(first.rating) ||
        Date.parse(first.schedule?.startsAt) - Date.parse(second.schedule?.startsAt),
      );
    return {
      sections: items.length === 0
        ? []
        : [{ id: 'featured:sports', title: 'Featured Sports', items }],
      subCategories,
    };
  }

  if (selected === FOOTBALL.id) {
    const requireProviderMatch = requireLiveProviderMatches &&
      query.category === ALL_CATEGORY;
    return {
      sections: byDateItems(
        footballCatalogItems(
          matches,
          providerEntries,
          nowMs,
          brandingByLeague,
          requireProviderMatch,
          knownFotmobMatches,
        ).filter(
          (item) => !excludeEnded || item.schedule?.state !== 'ended',
        ),
        nowMs,
      ),
      subCategories,
    };
  }

  if (selected != null) {
    const entries = providerEntries.filter(
      (entry) => sportIdOf(entry.sportName || entry.sportId) === selected,
    ).filter(
      (entry) => !excludeEnded || entry.item?.schedule?.state !== 'ended',
    );
    return {
      sections: entries.length === 0
        ? []
        : [{
            id: `sport:${selected}`,
            title: sportNameOf(entries[0].sportName || entries[0].sportId),
            items: entries.map((e) => e.item),
          }],
      subCategories,
    };
  }

  if (query.category === ALL_CATEGORY) {
    const footballItems = footballCatalogItems(
      matches,
      // FotMob owns event lifecycle. A provider's `live` flag can lag behind
      // it, so use every matched football entry here and filter the resulting
      // FotMob items by live state below.
      providerEntries,
      nowMs,
      brandingByLeague,
      requireLiveProviderMatches,
      knownFotmobMatches,
    ).filter((item) => item.schedule?.state === 'live');

    const items = [
      ...footballItems,
      ...providerEntries
        .filter((entry) => entry.live && !isFootballEntry(entry))
        .map((entry) => entry.item),
    ];
    return {
      sections: items.length === 0
        ? []
        : [{ id: 'live', title: 'Live Now', items }],
      subCategories,
    };
  }

  const sections = [];
  const allFootballItems = footballCatalogItems(
    matches,
    providerEntries,
    nowMs,
    brandingByLeague,
    false,
    knownFotmobMatches,
  ).filter(
    (item) => !excludeEnded || item.schedule?.state !== 'ended',
  );
  const footballItems = allFootballItems.filter(isFotmobItem);
  const otherFootballItems = allFootballItems.filter(
    (item) => !isFotmobItem(item),
  ).map((item) => ({
    ...item,
    subtitle: 'Other',
  }));
  if (footballItems.length > 0) {
    sections.push({ id: `sport:${FOOTBALL.id}`, title: FOOTBALL.name, items: footballItems });
  }
  if (otherFootballItems.length > 0) {
    sections.push({ id: 'sport:other-football', title: 'Other', items: otherFootballItems });
  }
  for (const sport of subCategories) {
    if (sport.id === FOOTBALL.id) continue;
    const items = providerEntries
      .filter(
        (entry) =>
          sportIdOf(entry.sportName || entry.sportId) === sport.id &&
          (!excludeEnded || entry.item?.schedule?.state !== 'ended'),
      )
      .map((entry) => entry.item);
    if (items.length > 0) {
      sections.push({ id: `sport:${sport.id}`, title: sport.name, items });
    }
  }
  return { sections, subCategories };
}

// --- the extension surface the host calls ---

async function fixturesCatalog(query) {
  // One instant for the whole call, so a match right at the window boundary
  // and the other catalog entries are judged against the same "now".
  const nowMs = Date.now();

  let [matches, popularLeagues, roxieEntries, cdnLiveTvEntries] = await Promise.all([
    fetchFixturesMemo(nowMs),
    fetchPopularLeaguesMemo(),
    getRoxieSportEntries(nowMs),
    getCdnLiveTvSportEntries(nowMs),
  ]);
  // Keep the complete FotMob feed as the identity authority for provider
  // dedupe. Finished matches remain available to schedule, but a stale
  // provider must not re-introduce one as live under a new ref.
  const allFotmobMatches = matches;
  matches = matches
    .filter(
      (match) =>
        !isWomenMatch(match) &&
        isRelevantMatch(match, nowMs),
    );
  matches = filterPopularMatches(matches, popularLeagues);
  matches = prioritizeTopClubMatches(matches);
  const knownFotmobMatches = allFotmobMatches;
  const brandingByLeague = await leagueBrandingFor(matches);

  let providerEntries = await getCricfySportEntries(nowMs);
  providerEntries = dedupeProviderEntries([
    ...providerEntries,
    ...roxieEntries,
    ...cdnLiveTvEntries,
  ], nowMs);
  return buildPage(
    query,
    matches,
    providerEntries,
    nowMs,
    brandingByLeague,
    true,
    knownFotmobMatches,
  );
}

// Registers into `__catalogProviders` rather than assigning
// `__extension.catalog` outright, so catalog files can load in either order
// without clobbering each other. This matches the stream provider registry.
globalThis.__catalogProviders = globalThis.__catalogProviders || [];
globalThis.__catalogProviders.push({
  catalogId: CATALOG_ID,
  catalog: fixturesCatalog,
});
globalThis.__catalogProviders.push({
  catalogId: SCHEDULE_CATALOG_ID,
  catalog: fixturesCatalog,
});
globalThis.__catalogProviders.push({
  catalogId: FEATURED_CATALOG_ID,
  catalog: fixturesCatalog,
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
