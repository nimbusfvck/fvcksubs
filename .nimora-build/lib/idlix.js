// Idlix stream provider for TMDB-backed movies and TV episodes.
//
// The upstream flow is search -> detail -> play-info -> claim -> redeem.
// Search/detail discovery happens in sources(), while the short-lived
// playback URL is deliberately fetched only in resolve().

const IDLIX_BASE_URL =
  globalThis.__idlixBaseUrl || 'https://z1.idlixku.com';
const IDLIX_PROVIDER_KEY = 'idlix';
const IDLIX_PROVIDER_ID = 'nimora.idlix';
const IDLIX_TMDB_PROVIDER_ID = 'nimora.tmdb';
const IDLIX_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  'Chrome/120.0.0.0 Safari/537.36';

function idlixBaseUrl() {
  return IDLIX_BASE_URL.replace(/\/$/, '');
}

function idlixUrl(value) {
  if (typeof value !== 'string' || value.trim() === '') return null;
  const url = value.trim().replace(/\\\//g, '/');
  if (/^https?:\/\//i.test(url)) return url;
  if (url.startsWith('/')) return `${idlixBaseUrl()}${url}`;
  return `${idlixBaseUrl()}/${url}`;
}

function idlixHeaders(referer) {
  return {
    Accept: '*/*',
    'Content-Type': 'application/json',
    Origin: idlixBaseUrl(),
    Referer: referer || `${idlixBaseUrl()}/`,
    'User-Agent': IDLIX_UA,
  };
}

async function idlixJson(url, options) {
  let response;
  try {
    response = await fetch(url, options || {});
  } catch (_) {
    return null;
  }
  if (response == null || response.status < 200 || response.status >= 300) {
    return null;
  }
  try {
    return JSON.parse(response.body || '');
  } catch (_) {
    return null;
  }
}

function idlixRef(item) {
  const ref = item && item.ref;
  if (ref == null || ref.providerId !== IDLIX_TMDB_PROVIDER_ID) return null;
  const id = typeof ref.id === 'string' ? ref.id : '';
  const movie = /^movie:([^:]+)$/.exec(id);
  if (item.kind === 'video' && movie != null) {
    return { mediaType: 'movie', tmdbId: movie[1] };
  }
  const episode = /^series:([^:]+):season:(\d+):episode:(\d+)$/.exec(id);
  if (item.kind === 'episode' && episode != null) {
    return {
      mediaType: 'tv',
      tmdbId: episode[1],
      season: Number(episode[2]),
      episode: Number(episode[3]),
    };
  }
  return null;
}

function idlixTitleOf(item) {
  if (item == null) return '';
  const extra = item.extra && typeof item.extra === 'object' ? item.extra : {};
  if (item.kind === 'episode') {
    if (typeof extra.seriesTitle === 'string' && extra.seriesTitle.trim()) {
      return extra.seriesTitle.trim();
    }
    // The app carries the parent series title as an episode's subtitle.
    return typeof item.subtitle === 'string' ? item.subtitle.trim() : '';
  }
  return typeof item.title === 'string' ? item.title.trim() : '';
}

function idlixTitleKey(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[\s\-_:,.!?()[\]{}]+/g, ' ')
    .trim();
}

function idlixCompatibleResult(result, mediaType) {
  if (result == null) return false;
  if (mediaType === 'movie') return result.contentType === 'movie';
  return result.contentType === 'tv_series' || result.contentType === 'series';
}

function idlixPickSearchResult(results, title, mediaType) {
  if (!Array.isArray(results)) return null;
  const wanted = idlixTitleKey(title);
  const compatible = results.filter((result) =>
    idlixCompatibleResult(result, mediaType) && result.slug && result.title,
  );
  // The search index is regionally noisy. An exact normalized title is the
  // only automatic match; never silently play the first unrelated result.
  return compatible.find((result) => idlixTitleKey(result.title) === wanted) || null;
}

async function idlixFindContent(item) {
  const ref = idlixRef(item);
  if (ref == null) return null;

  // TMDB already produced this item. Reuse its title rather than making a
  // second TMDB request and carrying a duplicate API key in this provider.
  const title = idlixTitleOf(item);
  if (!title) return null;

  const search = await idlixJson(
    `${idlixBaseUrl()}/api/search?q=${encodeURIComponent(title)}&page=1&limit=8`,
    { headers: idlixHeaders() },
  );
  const match = idlixPickSearchResult(search && search.results, title, ref.mediaType);
  if (match == null) return null;

  const detailPath = ref.mediaType === 'tv'
    ? `/api/series/${encodeURIComponent(match.slug)}`
    : `/api/movies/${encodeURIComponent(match.slug)}`;
  const detail = await idlixJson(
    `${idlixBaseUrl()}${detailPath}`,
    { headers: idlixHeaders() },
  );
  if (detail == null) return null;

  if (ref.mediaType === 'movie') {
    return detail.id == null ? null : {
      mediaType: ref.mediaType,
      tmdbId: ref.tmdbId,
      slug: match.slug,
      contentId: String(detail.id),
      contentType: 'movie',
      title,
    };
  }

  const seasonNumber = ref.season;
  const episodeNumber = ref.episode;
  let target = null;
  const firstSeason = detail.firstSeason;
  if (firstSeason != null && Number(firstSeason.seasonNumber) === seasonNumber) {
    target = (firstSeason.episodes || []).find(
      (episode) => Number(episode.episodeNumber) === episodeNumber,
    );
  }
  if (target == null) {
    const seasons = Array.isArray(detail.seasons) ? detail.seasons : [];
    const season = seasons.find(
      (entry) => Number(entry && entry.seasonNumber) === seasonNumber,
    );
    if (season != null) {
      const seasonData = await idlixJson(
        `${idlixBaseUrl()}/api/series/${encodeURIComponent(match.slug)}/season/${seasonNumber}`,
        { headers: idlixHeaders() },
      );
      const seasonObject = seasonData && (seasonData.season || seasonData);
      target = (seasonObject && seasonObject.episodes || []).find(
        (episode) => Number(episode.episodeNumber) === episodeNumber,
      );
    }
  }
  if (target == null || target.id == null) return null;
  return {
    mediaType: ref.mediaType,
    tmdbId: ref.tmdbId,
    slug: match.slug,
    contentId: String(target.id),
    contentType: 'episode',
    season: seasonNumber,
    episode: episodeNumber,
    title,
  };
}

function idlixEncode(value) {
  return host.codec.textToBase64(JSON.stringify(value))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function idlixDecode(value) {
  let encoded = String(value || '').replace(/-/g, '+').replace(/_/g, '/');
  const remainder = encoded.length % 4;
  if (remainder !== 0) encoded += '='.repeat(4 - remainder);
  try {
    return JSON.parse(host.codec.base64ToText(encoded));
  } catch (_) {
    return null;
  }
}

function idlixSourcePayload(sourceId) {
  const prefix = `${IDLIX_PROVIDER_KEY}:`;
  if (typeof sourceId !== 'string' || !sourceId.startsWith(prefix)) return null;
  return idlixDecode(sourceId.slice(prefix.length));
}

function idlixQuality(url) {
  const value = String(url || '').toLowerCase();
  if (value.includes('2160p') || value.includes('4k')) return '4K';
  if (value.includes('1080p')) return '1080p';
  if (value.includes('720p')) return '720p';
  if (value.includes('480p')) return '480p';
  return 'Unknown';
}

function idlixFormat(url) {
  if (/\.m3u8(?:[?#]|$)/i.test(url)) return 'hls';
  if (/\.mpd(?:[?#]|$)/i.test(url)) return 'dash';
  return 'other';
}

function idlixPlayableUrl(url) {
  return typeof url === 'string' && /^https?:\/\/[^\s]+$/i.test(url) &&
    (/[.]m3u8(?:[?#]|$)|[.]mp4(?:[?#]|$)|[.]mkv(?:[?#]|$)|[.]avi(?:[?#]|$)|\/api\/file\/|[.]cloudflarestorage\.com/i.test(url));
}

function idlixUnpack(value) {
  const packed = String(value || '');
  const pattern = /eval\s*\(\s*function\s*\(\s*p\s*,\s*a\s*,\s*c\s*,\s*k\s*,\s*e\s*,\s*d\s*\).*?return\s+p\s*}\s*\(\s*["'](.*?)["']\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*["'](.*?)["']\.split\(["']\|["']\)/s;
  const match = pattern.exec(packed);
  if (match == null) return packed;
  let payload = match[1];
  const radix = Number(match[2]);
  let count = Number(match[3]);
  const words = match[4].split('|');
  const token = (index) => (index < radix ? '' : token(Math.floor(index / radix))) +
    (index % radix > 35 ? String.fromCharCode(index % radix + 29) : (index % radix).toString(36));
  while (count-- > 0) {
    if (words[count]) payload = payload.replace(new RegExp(`\\b${token(count)}\\b`, 'g'), words[count]);
  }
  return payload;
}

function idlixExtractCandidate(body, hostName) {
  const text = idlixUnpack(body);
  const patterns = hostName === 'voe'
    ? [/hls['"]\s*:\s*['"](.*?m3u8.*?)['"]/i]
    : hostName === 'streamhide'
      ? [/sources\s*:\s*\[\s*{\s*file\s*:\s*['"](.*?m3u8.*?)['"]/i]
      : [/file\s*:\s*['"](.*?m3u8.*?)['"]/i];
  for (const pattern of patterns) {
    const match = pattern.exec(text);
    const url = match && match[1] ? match[1].replace(/\\\//g, '/') : null;
    if (idlixPlayableUrl(url)) return url;
  }
  return null;
}

async function idlixExtract(url) {
  if (idlixPlayableUrl(url)) return { url, referer: `${idlixBaseUrl()}/` };
  const lower = String(url || '').toLowerCase();
  const hostName = lower.includes('voe.sx') || lower.includes('voe.network')
    ? 'voe'
    : lower.includes('streamhide') || lower.includes('cloudy.upns') ||
        lower.includes('gdmirrorbot') || lower.includes('emturbovid')
      ? 'streamhide'
      : lower.includes('vidmoly') || lower.includes('filemoon') ||
          lower.includes('abyssplayer') || lower.includes('rubystm')
        ? 'file'
        : null;
  if (hostName == null) return null;
  let response;
  try {
    response = await fetch(url, { headers: { Referer: url, 'User-Agent': IDLIX_UA } });
  } catch (_) {
    return null;
  }
  if (response.status < 200 || response.status >= 300) return null;
  const extracted = idlixExtractCandidate(response.body, hostName);
  return extracted == null ? null : { url: extracted, referer: url };
}

async function idlixSources(args) {
  const item = args && args.item;
  const enabled = args && args.enabledProviders;
  if (enabled != null && enabled.indexOf(IDLIX_PROVIDER_ID) === -1) {
    return { sources: [] };
  }
  const content = await idlixFindContent(item);
  if (content == null) return { sources: [] };
  return {
    sources: [{
      id: `${IDLIX_PROVIDER_KEY}:${idlixEncode(content)}`,
      label: 'Idlix',
      provider: 'Nimora',
      providerId: IDLIX_PROVIDER_ID,
    }],
  };
}

async function idlixWaitForUnlock(playInfo) {
  const waitMs = Math.max(
    0,
    Number(playInfo && playInfo.unlockAt || 0) -
      Number(playInfo && playInfo.serverNow || Date.now()),
  );
  if (waitMs <= 0 || waitMs > 30000 || typeof globalThis.setTimeout !== 'function') return;
  await new Promise((resolve) => globalThis.setTimeout(resolve, waitMs));
}

async function idlixResolveSource(sourceId) {
  const payload = idlixSourcePayload(sourceId);
  if (payload == null || !payload.contentId || !payload.contentType) {
    throw new Error('Malformed Idlix source id');
  }
  const base = idlixBaseUrl();
  const headers = idlixHeaders();
  const playInfo = await idlixJson(
    `${base}/api/watch/play-info/${payload.contentType}/${encodeURIComponent(payload.contentId)}`,
    { headers },
  );
  if (playInfo == null || !playInfo.gateToken) {
    throw new Error('Idlix: no gate token');
  }
  await idlixWaitForUnlock(playInfo);

  const claim = await idlixJson(`${base}/api/watch/session/claim`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ gateToken: playInfo.gateToken }),
  });
  if (claim == null || !claim.claim || !claim.redeemUrl) {
    throw new Error('Idlix: session claim failed');
  }

  const redeem = await idlixJson(idlixUrl(claim.redeemUrl), {
    method: 'POST',
    headers,
    body: JSON.stringify({ claim: claim.claim }),
  });
  const rawUrl = idlixUrl(redeem && redeem.url);
  const extracted = await idlixExtract(rawUrl);
  if (extracted == null) throw new Error('Idlix: no playable stream URL');

  const subtitles = Array.isArray(redeem.subtitles)
    ? redeem.subtitles
        .filter((subtitle) => subtitle && subtitle.path)
        .map((subtitle) => ({
          language: subtitle.label || subtitle.lang || '',
          label: subtitle.label || subtitle.lang || '',
          url: idlixUrl(subtitle.path),
        }))
        .filter((subtitle) => subtitle.url != null)
    : [];
  const quality = idlixQuality(extracted.url);
  return {
    url: extracted.url,
    format: idlixFormat(extracted.url),
    headers: {
      Origin: base,
      Referer: extracted.referer || `${base}/`,
      'User-Agent': IDLIX_UA,
    },
    ...(quality !== 'Unknown' ? { quality } : {}),
    subtitles,
  };
}

globalThis.__streamProviders = globalThis.__streamProviders || [];
globalThis.__streamProviders.push({
  providerKey: IDLIX_PROVIDER_KEY,
  sources: idlixSources,
  resolve: idlixResolveSource,
});
