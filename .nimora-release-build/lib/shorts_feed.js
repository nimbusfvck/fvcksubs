// Nimora's unified Shorts feed.
//
// Individual providers remain responsible for preview resolution. This
// catalog only combines their lightweight catalog results so the app receives
// one stable, globally ordered feed instead of one static provider block after
// another.

const NIMORA_SHORTS_PROVIDER_ID = 'nimora.shorts';
const NIMORA_SHORTS_CATALOG_ID = 'shorts';
const NIMORA_SHORTS_MAX_ITEMS = 150;
const NIMORA_SHORTS_MAX_PROVIDER_STREAK = 2;

function nimoraShortsTimestamp(value) {
  if (typeof value !== 'string' || value.trim() === '') return null;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? timestamp : null;
}

function nimoraShortsCandidate(item, providerId, publishedAt, ordinal) {
  if (item == null || item.ref == null) return null;
  return {
    item,
    providerId,
    publishedAt: nimoraShortsTimestamp(publishedAt),
    ordinal,
  };
}

async function nimoraShortsUefaCandidates() {
  if (typeof uefaStorytellerStories !== 'function') return [];
  const stories = await uefaStorytellerStories();
  const candidates = [];
  for (const story of stories) {
    if (
      story == null || story.isPublished === false || story.id == null ||
      (typeof uefaStorytellerIsCuratedStory === 'function' &&
        !uefaStorytellerIsCuratedStory(story))
    ) continue;
    const publishedAt = story.publishAt || story.lastModificationTime || story.creationTime;
    const pages = typeof uefaStorytellerVideoPages === 'function'
      ? uefaStorytellerVideoPages(story)
      : [];
    pages.forEach(({ page }, videoIndex) => {
      if (candidates.length >= UEFA_STORYTELLER_MAX_ITEMS) return;
      const item = uefaStorytellerItem(story, page, videoIndex, pages.length);
      const candidate = nimoraShortsCandidate(
        item,
        'nimora.uefa',
        publishedAt,
        candidates.length,
      );
      if (candidate != null) candidates.push(candidate);
    });
  }
  return candidates;
}

async function nimoraShortsCliproCandidates() {
  if (typeof cliproMoments !== 'function') return [];
  const fetchedMoments = await cliproMoments();
  const moments = typeof cliproCuratedMoments === 'function'
    ? cliproCuratedMoments(fetchedMoments)
    : fetchedMoments;
  const candidates = [];
  for (const moment of moments) {
    const item = typeof cliproMomentItem === 'function'
      ? cliproMomentItem(moment)
      : null;
    const candidate = nimoraShortsCandidate(
      item,
      'nimora.clipro',
      moment && (moment.createTime || moment.updateTime),
      candidates.length,
    );
    if (candidate != null) candidates.push(candidate);
  }
  return candidates;
}

async function nimoraShortsCatalogCandidates() {
  const loaders = [];
  if (typeof nimoraShortsUefaCandidates === 'function') {
    loaders.push(nimoraShortsUefaCandidates().catch(() => []));
  }
  if (typeof nimoraShortsCliproCandidates === 'function') {
    loaders.push(nimoraShortsCliproCandidates().catch(() => []));
  }
  if (typeof tmdbPreviewCatalog === 'function') {
    loaders.push(
      tmdbPreviewCatalog()
        .then((page) => {
          const sections = page && Array.isArray(page.sections) ? page.sections : [];
          const items = sections.flatMap((section) =>
            section && Array.isArray(section.items) ? section.items : [],
          );
          return items
            .map((item, index) => nimoraShortsCandidate(
              item,
              item && item.ref && item.ref.providerId,
              null,
              index,
            ))
            .filter((candidate) => candidate != null);
        })
        .catch(() => []),
    );
  }
  if (typeof dramadevShortsCatalog === 'function') {
    loaders.push(
      dramadevShortsCatalog()
        .then((page) => {
          const sections = page && Array.isArray(page.sections) ? page.sections : [];
          const items = sections.flatMap((section) =>
            section && Array.isArray(section.items) ? section.items : [],
          );
          return items
            .map((item, index) => nimoraShortsCandidate(
              item,
              item && item.ref && item.ref.providerId,
              null,
              index,
            ))
            .filter((candidate) => candidate != null);
        })
        .catch(() => []),
    );
  }
  const groups = await Promise.all(loaders);
  return groups.flat();
}

function nimoraShortsCandidateKey(candidate) {
  const ref = candidate && candidate.item && candidate.item.ref;
  if (ref == null) return null;
  return `${ref.extensionId}/${ref.providerId}/${ref.id}`;
}

function nimoraShortsSortCandidates(candidates) {
  const deduplicated = [];
  const seen = new Set();
  for (const candidate of candidates) {
    const key = nimoraShortsCandidateKey(candidate);
    if (key == null || seen.has(key)) continue;
    seen.add(key);
    deduplicated.push(candidate);
  }
  deduplicated.sort((a, b) => {
    const aDate = a.publishedAt;
    const bDate = b.publishedAt;
    if (aDate != null && bDate == null) return -1;
    if (aDate == null && bDate != null) return 1;
    if (aDate != null && bDate != null && aDate !== bDate) return bDate - aDate;
    return a.ordinal - b.ordinal;
  });
  return deduplicated;
}

// Keep the global freshness ordering, but pull the next candidate from a
// different provider when one source would otherwise dominate the viewport.
function nimoraShortsDiversify(candidates) {
  const remaining = candidates.slice();
  const result = [];
  let lastProvider = null;
  let providerStreak = 0;
  while (remaining.length > 0 && result.length < NIMORA_SHORTS_MAX_ITEMS) {
    let index = remaining.findIndex((candidate) => {
      if (candidate.providerId !== lastProvider) return true;
      return providerStreak < NIMORA_SHORTS_MAX_PROVIDER_STREAK;
    });
    if (index < 0) index = 0;
    const [candidate] = remaining.splice(index, 1);
    if (candidate.providerId === lastProvider) {
      providerStreak++;
    } else {
      lastProvider = candidate.providerId;
      providerStreak = 1;
    }
    result.push(candidate.item);
  }
  return result;
}

async function nimoraShortsCatalog() {
  const candidates = await nimoraShortsCatalogCandidates();
  return {
    sections: [{
      id: 'shorts',
      title: 'Recommended Shorts',
      items: nimoraShortsDiversify(nimoraShortsSortCandidates(candidates)),
    }],
  };
}

globalThis.__catalogProviders = globalThis.__catalogProviders || [];
globalThis.__catalogProviders.push({
  catalogId: NIMORA_SHORTS_CATALOG_ID,
  catalog: nimoraShortsCatalog,
});
