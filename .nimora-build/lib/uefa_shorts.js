// UEFA Champions League Storyteller stories exposed as Shorts.
//
// Storyteller returns a story containing several pages. Only video pages are
// useful to the Shorts player, so each video page becomes one independent
// preview item while keeping the API's story/page order.

const UEFA_STORYTELLER_BASE =
  globalThis.__uefaStorytellerBaseUrl || 'https://api.usestoryteller.com';
const UEFA_STORYTELLER_API_KEY =
  globalThis.__uefaStorytellerApiKey ||
  'bcd199d7-77df-4e23-8035-e3542d56ebb4';
const UEFA_STORYTELLER_CATEGORY = 'ucl-top-stories';
const UEFA_STORYTELLER_CLIENT_VERSION = '10.13.12';
const UEFA_STORYTELLER_PROVIDER_ID = 'nimora.uefa';
const UEFA_STORYTELLER_CATALOG_ID = 'uefa_shorts';
const UEFA_STORYTELLER_CACHE_TTL_MS = 5 * 60 * 1000;
const UEFA_STORYTELLER_MAX_ITEMS = 20;
const UEFA_SITE_URL = 'https://www.uefa.com/';
const UEFA_STORYTELLER_USER_AGENT =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';

let uefaStorytellerMemo = null;

function uefaStorytellerUrl() {
  const query = {
    categories: UEFA_STORYTELLER_CATEGORY,
    ClientPlatform: 'Web',
    ClientVersion: UEFA_STORYTELLER_CLIENT_VERSION,
    'userAttributes[locale]': 'en',
    'x-storyteller-api-key': UEFA_STORYTELLER_API_KEY,
  };
  const encoded = Object.entries(query)
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
    .join('&');
  return `${UEFA_STORYTELLER_BASE}/api/app/story/stories/default?${encoded}`;
}

function uefaStorytellerHttpUrl(value) {
  if (typeof value !== 'string') return null;
  const url = value.trim();
  return /^https?:\/\//i.test(url) ? url : null;
}

function uefaStorytellerText(value) {
  return String(value || '').replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
}

function uefaStorytellerCleanTitle(value) {
  return uefaStorytellerText(value)
    .replace(/^UCL(?:\s+\d{4}\/\d{2})?\s*-\s*/i, '')
    .replace(/\s*-\s*EN$/i, '')
    .trim();
}

function uefaStorytellerTitleHasClip(value) {
  return /\bclips?\b/i.test(uefaStorytellerText(value));
}

function uefaStorytellerIsCuratedStory(story) {
  const title = uefaStorytellerCleanTitle(uefaStorytellerDisplayTitle(story));
  if (!title || uefaStorytellerTitleHasClip(title)) return false;
  return ![
    /\bquiz\b/i,
    /\bfantasy\b/i,
    /\bpredict(?:s|ion)?\b/i,
    /\bvot(?:e|es|ing)?\b/i,
    /\bnominees?\b/i,
    /\bjoin\b/i,
    /\baccess days?\b/i,
    /\bphotoshoot\b/i,
    /\bred carpet\b/i,
    /\bpatches?\b/i,
  ].some((pattern) => pattern.test(title));
}

function uefaStorytellerIsCuratedPage(page) {
  return !uefaStorytellerTitleHasClip(page && page.title);
}

async function uefaStorytellerStories() {
  const nowMs = Date.now();
  if (
    uefaStorytellerMemo != null &&
    nowMs - uefaStorytellerMemo.fetchedAt < UEFA_STORYTELLER_CACHE_TTL_MS
  ) {
    return uefaStorytellerMemo.promise;
  }

  const promise = (async () => {
    const response = await fetch(uefaStorytellerUrl(), {
      headers: {
        Accept: 'application/json',
        Origin: UEFA_SITE_URL,
        Referer: UEFA_SITE_URL,
        'User-Agent': UEFA_STORYTELLER_USER_AGENT,
      },
    });
    if (response.status < 200 || response.status >= 300) {
      throw new Error(`UEFA Storyteller request failed: ${response.status}`);
    }
    const data = JSON.parse(response.body);
    return data != null && Array.isArray(data.stories) ? data.stories : [];
  })().catch(() => []);

  uefaStorytellerMemo = { fetchedAt: nowMs, promise };
  return promise;
}

function uefaStorytellerDisplayTitle(story) {
  const titles = story && story.titles;
  const title = titles && (
    titles.longDisplay || titles.shortDisplay || titles.internal
  );
  return uefaStorytellerText(title || (story && story.title)) ||
    'UEFA Champions League';
}

function uefaStorytellerVideoPages(story) {
  if (story == null || !Array.isArray(story.pages)) return [];
  return story.pages
    .map((page, index) => ({ page, index }))
    .filter(({ page }) => {
      if (page == null || String(page.type || '').toLowerCase() !== 'video') {
        return false;
      }
      const background = page.background;
      return uefaStorytellerHttpUrl(page.url) != null ||
        uefaStorytellerHttpUrl(background && background.url) != null;
    });
}

function uefaStorytellerPageUrl(page) {
  const background = page && page.background;
  return uefaStorytellerHttpUrl(page && page.url) ||
    uefaStorytellerHttpUrl(background && background.url);
}

function uefaStorytellerPageThumbnail(story, page) {
  const background = page && page.background;
  const storyThumbnails = story && story.thumbnails;
  return uefaStorytellerHttpUrl(page && page.playcardUrl) ||
    uefaStorytellerHttpUrl(background && background.playcardUrl) ||
    uefaStorytellerHttpUrl(story && story.thumbnailUrl) ||
    uefaStorytellerHttpUrl(storyThumbnails && (
      storyThumbnails.medium || storyThumbnails.small || storyThumbnails.large
    ));
}

function uefaStorytellerItem(story, page, videoIndex, pageCount) {
  const storyId = story && story.id != null ? String(story.id) : '';
  const pageId = page && page.id != null ? String(page.id) : '';
  if (!uefaStorytellerIsCuratedStory(story) || !uefaStorytellerIsCuratedPage(page)) {
    return null;
  }
  const storyTitle = uefaStorytellerCleanTitle(uefaStorytellerDisplayTitle(story));
  const pageTitle = uefaStorytellerCleanTitle(page && page.title);
  const title = pageTitle || storyTitle || 'UEFA Champions League';
  const item = {
    ref: {
      extensionId: EXTENSION_ID,
      providerId: UEFA_STORYTELLER_PROVIDER_ID,
      id: `story:${storyId}:page:${pageId || videoIndex + 1}`,
    },
    kind: 'video',
    title: pageCount > 1 && !pageTitle
      ? `${title} · Highlight ${videoIndex + 1}`
      : title,
    subtitle: 'UEFA Champions League',
    tags: ['sports', 'football', 'champions-league'],
  };
  const thumbnail = uefaStorytellerPageThumbnail(story, page);
  if (thumbnail != null) item.artwork = { portrait: { url: thumbnail } };
  return item;
}

function uefaStorytellerItems(stories) {
  const seen = new Set();
  const items = [];
  for (const story of stories) {
    if (
      story == null || story.isPublished === false || story.id == null ||
      !uefaStorytellerIsCuratedStory(story)
    ) continue;
    const pages = uefaStorytellerVideoPages(story);
    for (let videoIndex = 0; videoIndex < pages.length; videoIndex++) {
      const page = pages[videoIndex].page;
      const pageId = page.id == null ? String(videoIndex + 1) : String(page.id);
      const key = `${String(story.id)}:${pageId}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const item = uefaStorytellerItem(story, page, videoIndex, pages.length);
      if (item != null) items.push(item);
      if (items.length >= UEFA_STORYTELLER_MAX_ITEMS) return items;
    }
  }
  return items;
}

function uefaStorytellerRefParts(ref) {
  const id = ref && typeof ref.id === 'string' ? ref.id : '';
  const match = /^story:([^:]+):page:(.+)$/.exec(id);
  return match == null ? null : { storyId: match[1], pageId: match[2] };
}

async function uefaStorytellerPreview(args) {
  const item = args && args.item;
  if (
    item == null || item.ref == null ||
    item.ref.providerId !== UEFA_STORYTELLER_PROVIDER_ID
  ) {
    return { sources: [] };
  }
  const parts = uefaStorytellerRefParts(item.ref);
  if (parts == null) return { sources: [] };

  const stories = await uefaStorytellerStories();
  for (const story of stories) {
    if (story == null || String(story.id) !== parts.storyId) continue;
    const videoPages = uefaStorytellerVideoPages(story);
    for (let videoIndex = 0; videoIndex < videoPages.length; videoIndex++) {
      const page = videoPages[videoIndex].page;
      const pageId = page.id == null ? String(videoIndex + 1) : String(page.id);
      if (pageId !== parts.pageId) continue;
      const url = uefaStorytellerPageUrl(page);
      if (url == null) return { sources: [] };
      return {
        sources: [{
          id: `preview:uefa:${parts.storyId}:${parts.pageId}`,
          type: 'direct',
          stream: {
            url,
            format: /\.m3u8(?:[?#]|$)/i.test(url) ? 'hls' : 'other',
            label: 'UEFA Storyteller',
          },
        }],
      };
    }
  }
  return { sources: [] };
}

async function uefaStorytellerCatalog(query) {
  const stories = await uefaStorytellerStories();
  const items = uefaStorytellerItems(stories);
  return { sections: [{ id: 'uefa', title: 'UEFA Champions League', items }] };
}

globalThis.__catalogProviders = globalThis.__catalogProviders || [];
globalThis.__catalogProviders.push({
  catalogId: UEFA_STORYTELLER_CATALOG_ID,
  catalog: uefaStorytellerCatalog,
});

globalThis.__previewProviders = globalThis.__previewProviders || [];
globalThis.__previewProviders.push({
  providerId: UEFA_STORYTELLER_PROVIDER_ID,
  preview: uefaStorytellerPreview,
});
