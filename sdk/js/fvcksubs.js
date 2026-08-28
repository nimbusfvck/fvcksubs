// fvcksubs JavaScript Extension SDK
//
// Load this file before provider files in bundle.js. It installs one global,
// `fvcksubs`, and the protocol surface expected by the host. The SDK has no
// module loader, DOM, timer, Node.js, or npm dependency, so it runs unchanged
// in fvcksubs' QuickJS sandbox.
(() => {
  'use strict';

  if (globalThis.fvcksubs) return;

  const catalogs = [];
  const metas = [];
  const streams = [];
  const searches = [];
  const subtitles = [];
  const previews = [];

  function requiredString(value, name) {
    if (typeof value !== 'string' || value.trim().length === 0) {
      throw new Error(`${name} must be a non-empty string`);
    }
    return value;
  }

  function requiredFunction(value, name) {
    if (typeof value !== 'function') throw new Error(`${name} must be a function`);
    return value;
  }

  function unique(list, predicate, description) {
    if (list.some(predicate)) throw new Error(`${description} is already registered`);
  }

  function objectResult(value, role) {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error(`${role} must return an object`);
    }
    return value;
  }

  function listResult(value, key, role) {
    const result = objectResult(value, role);
    if (!Array.isArray(result[key])) {
      throw new Error(`${role} must return { ${key}: [...] }`);
    }
    return result;
  }

  function catalogPage(value, role) {
    const result = objectResult(value, role);
    if (!Array.isArray(result.sections)) {
      throw new Error(`${role} must return { sections: [...] }`);
    }
    for (const section of result.sections) {
      if (section === null || typeof section !== 'object' || Array.isArray(section)) {
        throw new Error(`${role}.sections must contain objects`);
      }
      requiredString(section.id, `${role}.sections[].id`);
      if (!Array.isArray(section.items)) {
        throw new Error(`${role}.sections[].items must be a list`);
      }
    }
    return result;
  }

  function enabled(args, providerId) {
    return !Array.isArray(args.enabledProviders) || args.enabledProviders.indexOf(providerId) !== -1;
  }

  function providerPrefix(sourceId) {
    const separator = sourceId.indexOf(':');
    if (separator <= 0) throw new Error(`Malformed source id: ${sourceId}`);
    return sourceId.slice(0, separator);
  }

  function base64UrlEncode(value) {
    const json = JSON.stringify(value);
    return host.codec
      .textToBase64(json)
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/g, '');
  }

  function base64UrlDecode(value) {
    const base64 = value.replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(host.codec.base64ToText(base64));
  }

  /**
   * Creates an opaque, restart-safe source ID from a provider key and JSON payload.
   * Pass the returned value as `StreamSource.id`, then decode it in `resolve()`.
   *
   * @param {string} providerKey Short key registered with `defineStream`.
   * @param {*} payload JSON-serializable data needed to resolve the stream.
   * @returns {string}
   */
  function sourceId(providerKey, payload) {
    return `${requiredString(providerKey, 'providerKey')}:${base64UrlEncode(payload)}`;
  }

  /**
   * Decodes a source ID created by `sourceId` and optionally checks its provider key.
   *
   * @param {string} id Source ID received by `resolve()`.
   * @param {string} [expectedProviderKey] Expected prefix, such as `demo`.
   * @returns {*}
   */
  function sourcePayload(id, expectedProviderKey) {
    requiredString(id, 'sourceId');
    const prefix = providerPrefix(id);
    if (expectedProviderKey !== undefined && prefix !== expectedProviderKey) {
      throw new Error(`Expected source provider "${expectedProviderKey}", got "${prefix}"`);
    }
    return base64UrlDecode(id.slice(prefix.length + 1));
  }

  /**
   * Registers a catalog handler. The pair of provider ID and catalog ID must be unique.
   *
   * @param {object} definition Catalog registration.
   */
  function defineCatalog(definition) {
    const providerId = requiredString(definition && definition.providerId, 'catalog.providerId');
    const catalogId = requiredString(definition && definition.catalogId, 'catalog.catalogId');
    const catalog = requiredFunction(definition && definition.catalog, 'catalog.catalog');
    unique(
      catalogs,
      (entry) => entry.providerId === providerId && entry.catalogId === catalogId,
      `catalog ${providerId}/${catalogId}`,
    );
    catalogs.push({ providerId, catalogId, catalog });
  }

  /**
   * Registers the detail handler for a provider ID.
   *
   * @param {object} definition Metadata registration.
   */
  function defineMeta(definition) {
    const providerId = requiredString(definition && definition.providerId, 'meta.providerId');
    const meta = requiredFunction(definition && definition.meta, 'meta.meta');
    unique(metas, (entry) => entry.providerId === providerId, `meta provider ${providerId}`);
    metas.push({ providerId, meta });
  }

  /**
   * Registers stream discovery and resolution handlers.
   * `providerKey` becomes the prefix of every source ID owned by this handler.
   *
   * @param {object} definition Stream registration.
   */
  function defineStream(definition) {
    const providerId = requiredString(definition && definition.providerId, 'stream.providerId');
    const providerKey = requiredString(definition && definition.providerKey, 'stream.providerKey');
    const sources = requiredFunction(definition && definition.sources, 'stream.sources');
    const resolve = requiredFunction(definition && definition.resolve, 'stream.resolve');
    unique(streams, (entry) => entry.providerId === providerId, `stream provider ${providerId}`);
    unique(streams, (entry) => entry.providerKey === providerKey, `stream key ${providerKey}`);
    streams.push({ providerId, providerKey, sources, resolve });
  }

  /**
   * Registers a search handler. Results from all enabled handlers are merged.
   *
   * @param {object} definition Search registration.
   */
  function defineSearch(definition) {
    const providerId = requiredString(definition && definition.providerId, 'search.providerId');
    const search = requiredFunction(definition && definition.search, 'search.search');
    unique(searches, (entry) => entry.providerId === providerId, `search provider ${providerId}`);
    searches.push({ providerId, search });
  }

  /**
   * Registers a fallback subtitle lookup handler.
   *
   * @param {object} definition Subtitle registration.
   */
  function defineSubtitles(definition) {
    const providerId = requiredString(definition && definition.providerId, 'subtitles.providerId');
    const lookup = requiredFunction(definition && definition.subtitles, 'subtitles.subtitles');
    unique(subtitles, (entry) => entry.providerId === providerId, `subtitle provider ${providerId}`);
    subtitles.push({ providerId, subtitles: lookup });
  }

  /**
   * Registers a just-in-time preview handler for a provider ID (e.g. a
   * Shorts feed card). Unlike the other `define*` calls, this is the one
   * that installs `globalThis.__extension.preview` — and only on first use.
   * An extension that never calls `definePreview` leaves that function
   * entirely absent, so the host's optional-method probe treats it exactly
   * like a bundle built before preview existed, rather than a registered
   * dispatcher with zero providers behind it.
   *
   * @param {object} definition Preview registration.
   */
  function definePreview(definition) {
    const providerId = requiredString(definition && definition.providerId, 'preview.providerId');
    const preview = requiredFunction(definition && definition.preview, 'preview.preview');
    unique(previews, (entry) => entry.providerId === providerId, `preview provider ${providerId}`);
    previews.push({ providerId, preview });
    globalThis.__extension.preview = async (args) => {
      const provider = previews.find((entry) => entry.providerId === args.item.ref.providerId);
      if (!provider) throw new Error(`No preview provider registered for ${args.item.ref.providerId}`);
      return listResult(await provider.preview(args.item), 'sources', 'preview');
    };
  }

  function pageState(cursor) {
    if (cursor === undefined || cursor === null || cursor === '') return {};
    try {
      const decoded = sourcePayload(cursor, 'sdk-page');
      return decoded && typeof decoded === 'object' ? decoded : {};
    } catch (_) {
      // A cursor not created by the SDK belongs to a single-provider search.
      return { __single: cursor };
    }
  }

  async function tolerantPages(entries, role, args) {
    const cursors = pageState(args.page);
    const settled = await Promise.all(
      entries.map((entry) => {
        const cursor = cursors[entry.providerId] ?? cursors.__single;
        const providerArgs = Object.assign({}, args);
        if (cursor === undefined) delete providerArgs.page;
        else providerArgs.page = cursor;
        return Promise.resolve()
          .then(() => entry[role](providerArgs))
          .then((value) => catalogPage(value, role))
          .catch(() => null);
      }),
    );
    const pages = settled.filter((page) => page !== null);
    const next = {};
    for (let i = 0; i < settled.length; i++) {
      const page = settled[i];
      if (page && typeof page.nextPage === 'string' && page.nextPage.length > 0) {
        next[entries[i].providerId] = page.nextPage;
      }
    }
    const sections = [];
    for (let i = 0; i < settled.length; i++) {
      const page = settled[i];
      if (!page) continue;
      for (const section of page.sections) {
        sections.push({
          ...section,
          id: `${entries[i].providerId}:${section.id}`,
        });
      }
    }
    return {
      sections,
      ...(Object.keys(next).length > 0 ? { nextPage: sourceId('sdk-page', next) } : {}),
      ...(pages.some((page) => Array.isArray(page.subCategories))
        ? { subCategories: pages.flatMap((page) => page.subCategories || []) }
        : {}),
    };
  }

  globalThis.__extension = globalThis.__extension || {};
  globalThis.__extension.catalog = async (query) => {
    const provider = catalogs.find(
      (entry) => entry.providerId === query.providerId && entry.catalogId === query.catalogId,
    );
    if (!provider) throw new Error(`No catalog registered for ${query.providerId}/${query.catalogId}`);
    return catalogPage(await provider.catalog(query), 'catalog');
  };
  globalThis.__extension.meta = async (args) => {
    const provider = metas.find((entry) => entry.providerId === args.ref.providerId);
    if (!provider) throw new Error(`No meta provider registered for ${args.ref.providerId}`);
    return objectResult(await provider.meta(args), 'meta');
  };
  globalThis.__extension.sources = async (args) => {
    const perProvider = await Promise.all(
      streams.map((provider) => {
        if (!enabled(args, provider.providerId)) return Promise.resolve({ sources: [] });
        return Promise.resolve().then(() => provider.sources(args)).then(
          (value) => {
            const result = listResult(value, 'sources', 'sources');
            return {
              sources: result.sources.map((source) => ({
                ...source,
                providerId: provider.providerId,
              })),
            };
          },
          () => ({ sources: [] }),
        );
      }),
    );
    return { sources: perProvider.flatMap((result) => result.sources) };
  };
  globalThis.__extension.resolve = async ({ sourceId: id }) => {
    const key = providerPrefix(id);
    const provider = streams.find((entry) => entry.providerKey === key);
    if (!provider) throw new Error(`No stream provider registered for "${key}"`);
    return objectResult(await provider.resolve(id), 'resolve');
  };
  globalThis.__extension.search = async (args) => tolerantPages(searches, 'search', args);
  globalThis.__extension.subtitles = async (args) => {
    const settled = await Promise.all(
      subtitles.map((provider) =>
        Promise.resolve().then(() => provider.subtitles(args)).then(
          (value) => listResult(value, 'subtitles', 'subtitles').subtitles,
          () => [],
        ),
      ),
    );
    return { subtitles: settled.flat() };
  };

  globalThis.fvcksubs = Object.freeze({
    defineCatalog,
    defineMeta,
    defineStream,
    defineSearch,
    defineSubtitles,
    definePreview,
    sourceId,
    sourcePayload,
  });
})();
