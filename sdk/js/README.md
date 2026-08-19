# fvcksubs JavaScript SDK

This is the dependency-free authoring SDK for fvcksubs extensions. It removes
the repetitive `globalThis.__extension` dispatcher code while keeping the
wire protocol unchanged.

## Use it

Copy `fvcksubs.js` into your extension source tree and concatenate it **first**
when producing `bundle.js`. Copy `fvcksubs.d.ts` beside your source files for
editor autocomplete; it is not included in the shipped extension.

```js
fvcksubs.defineCatalog({
  providerId: 'demo.catalog',
  catalogId: 'main',
  async catalog(query) {
    const response = await fetch('https://api.example.com/items');
    if (response.status !== 200) throw new Error(`catalog failed: ${response.status}`);
    return { items: JSON.parse(response.body).map(toMediaItem) };
  },
});

fvcksubs.defineStream({
  providerId: 'demo.stream',
  providerKey: 'demo',
  async sources({ item }) {
    return {
      sources: [{
        id: fvcksubs.sourceId('demo', { contentId: item.ref.id }),
        label: 'Demo',
        provider: 'Demo',
      }],
    };
  },
  async resolve(sourceId) {
    const { contentId } = fvcksubs.sourcePayload(sourceId, 'demo');
    return { url: `https://cdn.example.com/${contentId}.m3u8`, format: 'hls' };
  },
});
```

The generated source id contains a base64url JSON payload, so `resolve()` can
work after an app restart without relying on an in-memory map.

## Registration API

- `defineCatalog({ providerId, catalogId, catalog })`: routes using both ids.
- `defineMeta({ providerId, meta })`: routes using `ref.providerId`.
- `defineStream({ providerId, providerKey, sources, resolve })`: respects the
  user's enabled-provider set, fans discovery out safely, and routes resolve
  calls by source-id prefix.
- `defineSearch({ providerId, search })`: merges all search providers; one
  failure does not discard other results.
- `defineSubtitles({ providerId, subtitles })`: merges subtitle providers with
  the same failure isolation.
- `sourceId(providerKey, payload)` / `sourcePayload(id, expectedKey)`: create
  and decode restart-safe opaque source ids.

Registration rejects duplicate provider ids/keys immediately. Role return
values receive basic envelope validation, while the host remains responsible
for decoding the complete protocol model.

## Sandbox constraints

There is no Node.js, npm loader, DOM, filesystem, timer, or ambient network.
Use the host-provided `fetch`, `host.codec`, `host.crypto`, and `host.match`
APIs described in `docs/03-js-bridge.md`. Every request and redirect host must
be declared in `manifest.json.permissions.hosts`.

The shipped extension is still exactly two files: `manifest.json` and
`bundle.js`. This SDK is source input to that bundle, not a third runtime file.
