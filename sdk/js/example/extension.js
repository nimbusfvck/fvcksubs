fvcksubs.defineCatalog({
  providerId: 'hello.catalog',
  catalogId: 'main',
  async catalog() {
    return {
      sections: [{
        id: 'main',
        items: [{
          ref: { extensionId: 'hello', providerId: 'hello.catalog', id: 'welcome' },
          kind: 'video',
          title: 'Hello fvcksubs',
        }],
      }],
    };
  },
});

fvcksubs.defineStream({
  providerId: 'hello.stream',
  providerKey: 'hello',
  async sources({ item }) {
    return {
      sources: [{
        id: fvcksubs.sourceId('hello', { id: item.ref.id }),
        label: 'Hello CDN',
        provider: 'Hello',
      }],
    };
  },
  async resolve(sourceId) {
    const payload = fvcksubs.sourcePayload(sourceId, 'hello');
    return {
      url: `https://cdn.example.com/${payload.id}.m3u8`,
      format: 'hls',
      label: 'Hello CDN',
    };
  },
});
