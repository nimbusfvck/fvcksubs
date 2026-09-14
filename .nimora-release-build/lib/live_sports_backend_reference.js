// Reference-only adapter for the upstream live-sport-plugin.
//
// This file is intentionally not included by tool/build_bundle.dart and does
// not register a Nimora catalog or stream provider. It documents the smallest
// compatible boundary if Nimora later consumes a self-hosted sports server:
//
//   GET /catalog/tv/nuvio_sports_live.json
//   GET /stream/tv/{meta.id}.json
//
// The server performs the provider-specific work (including native Node/WASM
// resolution) and returns a fresh direct HLS URL or a server-relative proxy
// URL. Signed media URLs are never placed in this module's source ids.

const LIVE_SPORTS_REFERENCE_PROVIDER_ID = 'nimora.live.sports.reference';
const LIVE_SPORTS_REFERENCE_PROVIDER_KEY = 'live-sports-reference';
const LIVE_SPORTS_REFERENCE_DEFAULT_CATALOG = 'nuvio_sports_live';

function liveSportsReferenceText(value) {
  return value == null ? '' : String(value).trim();
}

function liveSportsReferenceBaseUrl(value) {
  const base = liveSportsReferenceText(
    value || globalThis.__liveSportsBackendReferenceBaseUrl,
  ).replace(/\/+$/, '');
  if (!/^https?:\/\//i.test(base)) {
    throw new Error('Live sports reference base URL is not configured');
  }
  return base;
}

function liveSportsReferenceCatalogUrl(baseUrl, catalogId, search) {
  const base = liveSportsReferenceBaseUrl(baseUrl);
  const catalog = liveSportsReferenceText(catalogId) ||
    LIVE_SPORTS_REFERENCE_DEFAULT_CATALOG;
  let url = `${base}/catalog/tv/${encodeURIComponent(catalog)}.json`;
  const query = liveSportsReferenceText(search);
  if (query) url += `?search=${encodeURIComponent(query)}`;
  return url;
}

function liveSportsReferenceStreamUrl(baseUrl, pluginMetaId) {
  const base = liveSportsReferenceBaseUrl(baseUrl);
  const id = liveSportsReferenceText(pluginMetaId);
  if (!id) throw new Error('Live sports reference meta id is empty');
  return `${base}/stream/tv/${encodeURIComponent(id)}.json`;
}

function liveSportsReferenceAbsoluteUrl(baseUrl, value) {
  const url = liveSportsReferenceText(value);
  if (/^https?:\/\//i.test(url)) return url;
  const base = liveSportsReferenceBaseUrl(baseUrl);
  if (url.startsWith('//')) {
    return `${base.split('://')[0]}:${url}`;
  }
  if (url.startsWith('/')) return `${base}${url}`;
  return `${base}/${url.replace(/^\/+/, '')}`;
}

function liveSportsReferenceFormat(url) {
  const value = liveSportsReferenceText(url).toLowerCase();
  if (/\.m3u8(?:[?#]|$)/.test(value) || value.includes('/api/manifest')) {
    return 'hls';
  }
  if (/\.mpd(?:[?#]|$)/.test(value)) return 'dash';
  return null;
}

function liveSportsReferenceProxyHeaders(stream) {
  const request = stream && stream.behaviorHints &&
    stream.behaviorHints.proxyHeaders &&
    stream.behaviorHints.proxyHeaders.request;
  if (request == null || typeof request !== 'object') return {};
  return Object.fromEntries(
    Object.entries(request).map(([key, value]) => [key, String(value)]),
  );
}

function liveSportsReferenceSourceId(baseUrl, pluginMetaId) {
  const payload = JSON.stringify({
    baseUrl: liveSportsReferenceBaseUrl(baseUrl),
    pluginMetaId: liveSportsReferenceText(pluginMetaId),
  });
  const encoded = host.codec.textToBase64(payload)
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
  return `${LIVE_SPORTS_REFERENCE_PROVIDER_KEY}:${encoded}`;
}

function liveSportsReferenceDecodeSourceId(sourceId) {
  const prefix = `${LIVE_SPORTS_REFERENCE_PROVIDER_KEY}:`;
  const value = liveSportsReferenceText(sourceId);
  if (!value.startsWith(prefix)) {
    throw new Error(`Invalid live sports reference source id: ${sourceId}`);
  }
  let encoded = value.slice(prefix.length).replace(/-/g, '+').replace(/_/g, '/');
  while (encoded.length % 4) encoded += '=';
  const payload = JSON.parse(host.codec.base64ToText(encoded));
  if (payload == null || typeof payload !== 'object') {
    throw new Error('Invalid live sports reference source payload');
  }
  return {
    baseUrl: liveSportsReferenceBaseUrl(payload.baseUrl),
    pluginMetaId: liveSportsReferenceText(payload.pluginMetaId),
  };
}

function liveSportsReferenceCatalogItem(meta) {
  if (meta == null || typeof meta !== 'object') return null;
  const pluginMetaId = liveSportsReferenceText(meta.id);
  const title = liveSportsReferenceText(meta.name)
    .replace(/^(?:🔴 LIVE:|⏱️|📺)\s*/u, '');
  if (!pluginMetaId || !title) return null;

  const item = {
    ref: {
      extensionId: typeof EXTENSION_ID === 'string' ? EXTENSION_ID : 'nimora',
      providerId: LIVE_SPORTS_REFERENCE_PROVIDER_ID,
      id: `plugin:${pluginMetaId}`,
    },
    kind: 'event',
    title,
    subtitle: Array.isArray(meta.genres) && meta.genres.length > 0
      ? liveSportsReferenceText(meta.genres[0])
      : 'Live Sports',
  };
  if (meta.poster && /^https?:\/\//i.test(String(meta.poster))) {
    item.artwork = { landscape: { url: String(meta.poster) } };
  }
  if (meta.released && !isNaN(Date.parse(String(meta.released)))) {
    item.schedule = {
      startsAt: new Date(String(meta.released)).toISOString(),
      state: String(meta.releaseInfo || '').toUpperCase() === 'LIVE'
        ? 'live'
        : 'scheduled',
    };
  }
  return item;
}

function liveSportsReferenceMapCatalogPayload(payload) {
  const metas = payload && Array.isArray(payload.metas) ? payload.metas : [];
  return {
    sections: [{
      id: 'live-sports-reference',
      title: 'Live Sports Backend (reference)',
      items: metas.map(liveSportsReferenceCatalogItem).filter(Boolean),
    }].filter((section) => section.items.length > 0),
  };
}

async function liveSportsReferenceFetchJson(url) {
  const response = await fetch(url, {
    headers: { Accept: 'application/json' },
  });
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Live sports reference request failed: ${response.status}`);
  }
  const body = response && typeof response.body === 'string'
    ? response.body
    : '';
  const payload = JSON.parse(body);
  if (payload == null || typeof payload !== 'object') {
    throw new Error('Live sports reference response is not an object');
  }
  return payload;
}

async function liveSportsReferenceCatalog(baseUrl, catalogId, search) {
  const payload = await liveSportsReferenceFetchJson(
    liveSportsReferenceCatalogUrl(baseUrl, catalogId, search),
  );
  return liveSportsReferenceMapCatalogPayload(payload);
}

function liveSportsReferenceMapStreamPayload(baseUrl, payload) {
  const streams = payload && Array.isArray(payload.streams) ? payload.streams : [];
  for (const stream of streams) {
    const candidates = [stream && stream.url, stream && stream.externalUrl]
      .filter(Boolean);
    for (const rawUrl of candidates) {
      const url = liveSportsReferenceAbsoluteUrl(baseUrl, rawUrl);
      const format = liveSportsReferenceFormat(url);
      // A /watch page is a browser fallback, not a native media URL. Do not
      // report it as playable; the caller can keep it as a separate web option.
      if (format == null) continue;
      return {
        url,
        headers: liveSportsReferenceProxyHeaders(stream),
        format,
        label: liveSportsReferenceText(stream.title || stream.name) ||
          'Live Sports Backend',
      };
    }
  }
  throw new Error('Live sports reference returned no direct HLS/DASH stream');
}

async function liveSportsReferenceResolve(sourceId) {
  const decoded = liveSportsReferenceDecodeSourceId(sourceId);
  const payload = await liveSportsReferenceFetchJson(
    liveSportsReferenceStreamUrl(decoded.baseUrl, decoded.pluginMetaId),
  );
  return liveSportsReferenceMapStreamPayload(decoded.baseUrl, payload);
}

const liveSportsBackendReference = {
  providerId: LIVE_SPORTS_REFERENCE_PROVIDER_ID,
  providerKey: LIVE_SPORTS_REFERENCE_PROVIDER_KEY,
  catalogUrl: liveSportsReferenceCatalogUrl,
  streamUrl: liveSportsReferenceStreamUrl,
  sourceId: liveSportsReferenceSourceId,
  decodeSourceId: liveSportsReferenceDecodeSourceId,
  fetchJson: liveSportsReferenceFetchJson,
  catalog: liveSportsReferenceCatalog,
  resolve: liveSportsReferenceResolve,
  mapCatalogPayload: liveSportsReferenceMapCatalogPayload,
  mapStreamPayload: liveSportsReferenceMapStreamPayload,
};

globalThis.__liveSportsBackendReference = liveSportsBackendReference;
