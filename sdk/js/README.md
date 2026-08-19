# fvcksubs JavaScript SDK

This is the dependency-free authoring SDK for fvcksubs extensions. It removes
the repetitive `globalThis.__extension` dispatcher code while keeping the
wire protocol unchanged.

## Use it

Copy `fvcksubs.js` into your extension source tree and concatenate it **first**
when producing `bundle.js`. Copy `fvcksubs.d.ts` beside your source files for
editor autocomplete; it is not included in the shipped extension.

See [Data model](DATA_MODEL.md) for every request and response field, where it
appears in the app, and which values must remain stable.

```js
fvcksubs.defineCatalog({
  providerId: 'demo.catalog',
  catalogId: 'main',
  async catalog(query) {
    const response = await fetch('https://api.example.com/items');
    if (response.status !== 200) throw new Error(`catalog failed: ${response.status}`);
    return {
      sections: [{ id: 'main', items: JSON.parse(response.body).map(toMediaItem) }],
    };
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

`defineStream` adds its stable `providerId` to every returned source. The app
uses that value for source priority, so source IDs stay opaque and extension
authors should not encode UI preferences into them.

## Manifest provider names

Declare every registered provider in `manifest.json`. A provider may include a
user-facing `name`; its `id` remains the stable value used by registration,
routing, saved settings, and source priority.

```json
{
  "providers": [
    {
      "id": "demo.stream",
      "name": "Atlas",
      "roles": ["stream"]
    }
  ]
}
```

Use a neutral `name` when the upstream identity should not be displayed. Do
not change `id` merely to rename a provider, because that discards the user's
enabled state and saved priority. The SDK handles `StreamSource.providerId`
automatically; `provider` remains an optional user-facing grouping label.

## Registration API

- `defineCatalog({ providerId, catalogId, catalog })`: routes using both ids.
- `defineMeta({ providerId, meta })`: routes using `ref.providerId`.
- `defineStream({ providerId, providerKey, sources, resolve })`: respects the
  user's enabled-provider set, fans discovery out safely, and routes resolve
  calls by source-id prefix. Returned sources receive the registered
  `providerId` automatically.
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

## Publish updates

Users install extensions through a `repo.json` index. The index describes the
download before the app fetches or evaluates the extension files. See
[`example/repo.json`](example/repo.json) for a complete entry.

Keep these values synchronized for every release:

- `version` must match `manifest.json`.
- `hosts` must mirror `manifest.json.permissions.hosts`.
- `bundleSha256` must be the lowercase SHA-256 of the exact published
  `bundle.js` bytes.
- `manifestUrl` and `bundleUrl` must resolve over HTTPS.

Add concise user-facing changes to `releaseNotes`:

```json
{
  "releaseNotes": [
    "Added Motorsport events.",
    "Fixed source selection for live streams."
  ]
}
```

`releaseNotes` belongs to `repo.json`, not `manifest.json` or
`fvcksubs.d.ts`. It is distribution metadata shown before an update; the
extension runtime never receives it. An absent or empty list remains valid.

Increase the version whenever published behavior or metadata changes. The app
only offers an update when the repository version is newer than the installed
version.
