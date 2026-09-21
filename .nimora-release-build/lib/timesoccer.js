// Time Soccer TV football highlights catalog and Videa HLS resolver.
//
// The public homepage is a WordPress page whose video cards come from the
// `Video` category. The REST API gives us the same post stream without
// depending on the theme's generated HTML layout. Each post contains a Videa
// iframe; the iframe page carries the actual CDN master playlist.

const TIMESOCCER_BASE =
  globalThis.__timesoccerBaseUrl || 'https://timesoccertv.com';
const TIMESOCCER_PROVIDER_ID = 'nimora.timesoccer';
const TIMESOCCER_PROVIDER_KEY = 'timesoccer';
const TIMESOCCER_CATALOG_ID = 'timesoccer';
const TIMESOCCER_VIDEO_CATEGORY = 4;
const TIMESOCCER_PAGE_SIZE = 20;
const TIMESOCCER_USER_AGENT =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 ' +
  '(KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1';

function timesoccerWithQuery(url, query) {
  const parts = Object.entries(query).map(
    ([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`,
  );
  return parts.length > 0 ? `${url}?${parts.join('&')}` : url;
}

function timesoccerDecodeHtml(value) {
  return String(value || '')
    .replace(/&amp;|&#038;/gi, '&')
    .replace(/&quot;|&#034;/gi, '"')
    .replace(/&#39;|&#x27;|&apos;/gi, "'")
    .replace(/&#8211;|&#x2013;/gi, '-')
    .replace(/&#8212;|&#x2014;/gi, '-')
    .replace(/&#([0-9]+);/g, (_, decimal) =>
      String.fromCharCode(Number(decimal)),
    )
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) =>
      String.fromCharCode(parseInt(hex, 16)),
    );
}

function timesoccerCleanTitle(value) {
  return timesoccerDecodeHtml(value)
    .replace(/<[^>]*>/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function timesoccerContentOf(post) {
  if (post == null || typeof post !== 'object') return '';
  const content = post.content;
  if (typeof content === 'string') return content;
  if (content != null && typeof content === 'object') {
    return String(content.rendered || content.raw || '');
  }
  return '';
}

function timesoccerEmbedUrlFromHtml(html) {
  const frames = /<iframe\b[^>]*\bsrc\s*=\s*["']([^"']+)["']/ig;
  let match;
  while ((match = frames.exec(html || '')) != null) {
    const url = timesoccerDecodeHtml(match[1]).trim();
    if (/^https?:\/\/[^/]+\/embed\/media\/[A-Za-z0-9-]+(?:[/?#]|$)/i.test(url)) {
      return url;
    }
  }
  return null;
}

function timesoccerHasVideaEmbed(post) {
  return timesoccerEmbedUrlFromHtml(timesoccerContentOf(post)) != null;
}

function timesoccerHlsUrlFromEmbed(html) {
  const decoded = timesoccerDecodeHtml(html);
  const matches = decoded.match(
    /https?:\/\/[^"'<>\\\s]+\.m3u8(?:\?[^"'<>\\\s]*)?/ig,
  );
  if (!matches || matches.length === 0) return null;
  const url = matches[0].trim();
  return /^https?:\/\//i.test(url) ? url : null;
}

function timesoccerArtworkUrl(post) {
  if (post == null || typeof post !== 'object') return null;
  const embedded = post._embedded;
  const media = embedded && embedded['wp:featuredmedia'];
  const sourceUrl = Array.isArray(media) && media[0] && media[0].source_url;
  if (typeof sourceUrl === 'string' && /^https?:\/\//i.test(sourceUrl)) {
    return sourceUrl;
  }
  return null;
}

function timesoccerPostToItem(post) {
  if (post == null || post.id == null) return null;
  if (!timesoccerHasVideaEmbed(post)) return null;
  const title = timesoccerCleanTitle(
    post.title && typeof post.title === 'object'
      ? post.title.rendered
      : post.title,
  );
  if (title.length === 0) return null;

  const item = {
    ref: {
      extensionId: EXTENSION_ID,
      providerId: TIMESOCCER_PROVIDER_ID,
      id: `post:${String(post.id)}`,
    },
    kind: 'video',
    title,
    subtitle: 'Football Highlights',
  };
  const artworkUrl = timesoccerArtworkUrl(post);
  if (artworkUrl != null) item.artwork = { portrait: { url: artworkUrl } };
  return item;
}

function timesoccerPostsToItems(posts) {
  if (!Array.isArray(posts)) return [];
  const seen = new Set();
  const items = [];
  for (const post of posts) {
    const item = timesoccerPostToItem(post);
    if (item == null || seen.has(item.ref.id)) continue;
    seen.add(item.ref.id);
    items.push(item);
  }
  return items;
}

async function timesoccerFetchJson(url) {
  const response = await fetch(url, {
    headers: {
      Accept: 'application/json',
      'User-Agent': TIMESOCCER_USER_AGENT,
    },
  });
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Time Soccer request failed: ${response.status}`);
  }
  const data = JSON.parse(response.body);
  if (data == null || typeof data !== 'object') {
    throw new Error('Time Soccer response is not an object');
  }
  return { data, headers: response.headers || {} };
}

function timesoccerResponseHeader(response, name) {
  const headers = response && response.headers;
  if (headers == null || typeof headers !== 'object') return '';
  const wanted = String(name).toLowerCase();
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() === wanted) return String(headers[key] || '');
  }
  return '';
}

function timesoccerHasNextPage(response, page, rawPosts) {
  const totalPages = Number(timesoccerResponseHeader(response, 'x-wp-totalpages'));
  if (Number.isInteger(totalPages) && totalPages > 0) {
    return page < totalPages;
  }
  // WordPress normally sends X-WP-TotalPages. If an intermediary strips it,
  // a full page is still a safe signal to request one more batch; the first
  // short page ends the nested load.
  return Array.isArray(rawPosts) && rawPosts.length >= TIMESOCCER_PAGE_SIZE;
}

async function timesoccerCatalog(query) {
  if (
    query.category !== 'all' &&
    query.category !== 'sport' &&
    query.category !== 'schedule'
  ) {
    return { sections: [] };
  }
  const requestedPage = query.page == null ? 1 : Number(query.page);
  const page = Number.isFinite(requestedPage) && requestedPage > 0
    ? Math.floor(requestedPage)
    : 1;
  const url = timesoccerWithQuery(
    `${TIMESOCCER_BASE}/wp-json/wp/v2/posts`,
    {
      categories: String(TIMESOCCER_VIDEO_CATEGORY),
      per_page: String(TIMESOCCER_PAGE_SIZE),
      page: String(page),
      orderby: 'date',
      order: 'desc',
      _embed: '1',
      _fields: 'id,date,modified,slug,link,title,content,featured_media,_embedded,_links',
    },
  );

  let posts;
  let response;
  try {
    response = await timesoccerFetchJson(url);
    posts = response.data;
  } catch (_) {
    return { sections: [] };
  }
  const items = timesoccerPostsToItems(posts);
  const result = {
    sections: items.length === 0
      ? []
      : [{ id: 'timesoccer-latest', title: 'Football Highlights', items }],
  };
  if (timesoccerHasNextPage(response, page, posts)) {
    result.nextPage = String(page + 1);
  }
  return result;
}

async function timesoccerSources(args) {
  const item = args.item;
  const enabled = args.enabledProviders;
  if (enabled != null && enabled.indexOf(TIMESOCCER_PROVIDER_ID) === -1) {
    return { sources: [] };
  }
  if (item == null || item.ref == null ||
      item.ref.providerId !== TIMESOCCER_PROVIDER_ID) {
    return { sources: [] };
  }
  const itemId = String(item.ref.id || '');
  if (!/^post:\d+$/.test(itemId)) return { sources: [] };
  return {
    sources: [{
      id: `${TIMESOCCER_PROVIDER_KEY}:${itemId.slice('post:'.length)}`,
      label: 'Videa HLS',
      provider: 'Nimora',
      providerId: TIMESOCCER_PROVIDER_ID,
    }],
  };
}

function timesoccerPostIdFromSource(sourceId) {
  const prefix = `${TIMESOCCER_PROVIDER_KEY}:`;
  const value = sourceId.startsWith(prefix)
    ? sourceId.slice(prefix.length)
    : sourceId;
  if (!/^\d+$/.test(value)) {
    throw new Error(`Malformed Time Soccer source id: ${sourceId}`);
  }
  return value;
}

async function timesoccerResolveSource(sourceId) {
  const postId = timesoccerPostIdFromSource(sourceId);
  const postUrl = timesoccerWithQuery(
    `${TIMESOCCER_BASE}/wp-json/wp/v2/posts/${encodeURIComponent(postId)}`,
    { _fields: 'content' },
  );
  const postResponse = await timesoccerFetchJson(postUrl);
  const post = postResponse.data;
  const embedUrl = timesoccerEmbedUrlFromHtml(timesoccerContentOf(post));
  if (embedUrl == null) {
    throw new Error(`Time Soccer post ${postId} has no Videa embed`);
  }

  const embedResponse = await fetch(embedUrl, {
    headers: {
      Accept: 'text/html,application/xhtml+xml',
      'User-Agent': TIMESOCCER_USER_AGENT,
    },
  });
  if (embedResponse.status < 200 || embedResponse.status >= 300) {
    throw new Error(`Videa embed request failed: ${embedResponse.status}`);
  }
  const hlsUrl = timesoccerHlsUrlFromEmbed(embedResponse.body);
  if (hlsUrl == null) throw new Error('Videa embed has no HLS playlist');

  const playlistResponse = await fetch(hlsUrl, {
    headers: {
      Accept: 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*',
      'User-Agent': TIMESOCCER_USER_AGENT,
    },
  });
  if (playlistResponse.status < 200 || playlistResponse.status >= 300) {
    throw new Error(`Videa playlist request failed: ${playlistResponse.status}`);
  }
  const playlist = String(playlistResponse.body || '');
  if (!playlist.includes('#EXTM3U') ||
      !(/#EXT-X-STREAM-INF|#EXTINF/.test(playlist))) {
    throw new Error('Videa response is not a playable HLS playlist');
  }

  // The CDN sample is public and CORS-enabled; returning no forced Referer
  // keeps native iOS HLS from being pushed through an unnecessary request
  // header path. The User-Agent is still forced, though: every request up
  // to here (post, embed, playlist) used the spoofed one above, but the
  // native player's own segment fetches otherwise fall back to the
  // platform default — a mismatch a CDN that treats non-browser clients
  // differently would only start showing once real playback begins, not
  // during this validation fetch.
  return {
    url: hlsUrl,
    headers: { 'User-Agent': TIMESOCCER_USER_AGENT },
    format: 'hls',
    label: 'Videa HLS',
  };
}

globalThis.__catalogProviders = globalThis.__catalogProviders || [];
globalThis.__catalogProviders.push({
  catalogId: TIMESOCCER_CATALOG_ID,
  catalog: timesoccerCatalog,
});

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: TIMESOCCER_PROVIDER_KEY,
  sources: timesoccerSources,
  resolve: (sourceId) => timesoccerResolveSource(sourceId),
});

globalThis.__extension = globalThis.__extension || {};
if (!globalThis.__extension.catalog) {
  globalThis.__extension.catalog = async (query) => {
    const provider = globalThis.__catalogProviders.find(
      (entry) => entry.catalogId === query.catalogId,
    );
    if (!provider) {
      throw new Error(`No catalog provider registered for "${query.catalogId}"`);
    }
    return provider.catalog(query);
  };
}
if (!globalThis.__extension.sources) {
  globalThis.__extension.sources = async (args) => {
    const calls = globalThis.__streamProviders.map((provider) =>
      Promise.resolve()
        .then(() => provider.sources(args))
        .catch(() => ({ sources: [] })),
    );
    if (args.fast !== true) {
      const perProvider = await Promise.all(calls);
      return { sources: perProvider.flatMap((result) => result.sources) };
    }
    return new Promise((resolve) => {
      let remaining = calls.length;
      let returned = false;
      for (const call of calls) {
        call.then((result) => {
          if (returned) return;
          const sources = Array.isArray(result.sources) ? result.sources : [];
          if (sources.length > 0) {
            returned = true;
            resolve({ sources });
            return;
          }
          remaining -= 1;
          if (remaining === 0) resolve({ sources: [] });
        });
      }
    });
  };
  globalThis.__extension.resolve = async (args) => {
    const sourceId = args.sourceId;
    const separator = sourceId.indexOf(':');
    if (separator < 0) throw new Error(`Malformed source id: ${sourceId}`);
    const providerKey = sourceId.slice(0, separator);
    const provider = globalThis.__streamProviders.find(
      (entry) => entry.providerKey === providerKey,
    );
    if (!provider) {
      throw new Error(`No stream provider registered for "${providerKey}"`);
    }
    return provider.resolve(sourceId);
  };
}
