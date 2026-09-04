import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

void main() {
  const seriesRef = MediaRef(
    extensionId: 'example',
    providerId: 'example.catalog',
    id: 'series-1',
  );
  const episodeRef = MediaRef(
    extensionId: 'example',
    providerId: 'example.catalog',
    id: 'episode-1',
  );
  const recommendationRef = MediaRef(
    extensionId: 'example',
    providerId: 'example.catalog',
    id: 'video-2',
  );
  const collectionItemRef = MediaRef(
    extensionId: 'example',
    providerId: 'example.catalog',
    id: 'video-3',
  );

  test('detail and episode guide round-trip', () {
    const detail = MediaDetailV2(
      item: SeriesItemV2(ref: seriesRef, title: 'Series'),
      description: 'Description',
      tags: ['Drama'],
      facts: [MediaFact(label: 'Year', value: '2026')],
      credits: [
        MediaCredit(
          name: 'Person',
          role: 'Lead',
          image: ImageRef('https://cdn.example/person.jpg'),
        ),
      ],
      trailers: [
        MediaTrailer(
          title: 'Official Trailer',
          url: 'https://www.youtube.com/watch?v=example',
          site: 'YouTube',
          thumbnail: ImageRef(
            'https://img.youtube.com/vi/example/hqdefault.jpg',
          ),
          mimeType: 'video/mp4',
        ),
      ],
      collection: MediaCollectionV2(
        id: '531241',
        name: 'Example Collection',
        items: [
          VideoItemV2(ref: collectionItemRef, title: 'Collection movie'),
        ],
      ),
      recommendations: [
        VideoItemV2(ref: recommendationRef, title: 'Related video'),
      ],
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'volume-1',
            title: 'Volume 1',
            episodes: [
              EpisodeSummary(
                ref: episodeRef,
                title: 'Episode 1',
                position: 1,
                durationSeconds: 1200,
              ),
            ],
          ),
        ],
        defaultEpisodeRef: episodeRef,
      ),
    );

    expect(MediaDetailV2.fromJson(detail.toJson()), detail);
  });

  test('default episode must exist in the guide', () {
    expect(
      () => MediaDetailV2.fromJson({
        'item': const SeriesItemV2(ref: seriesRef, title: 'Series').toJson(),
        'episodeGuide': {
          'groups': [
            {
              'id': 'volume-1',
              'title': 'Volume 1',
              'episodes': [
                {
                  'ref': episodeRef.toJson(),
                  'title': 'Episode 1',
                  'position': 1,
                },
              ],
            },
          ],
          'defaultEpisodeRef': const MediaRef(
            extensionId: 'example',
            providerId: 'example.catalog',
            id: 'missing',
          ).toJson(),
        },
      }),
      throwsFormatException,
    );
  });

  test('rejects unknown fields and non-UTC availability', () {
    expect(
      () => MediaDetailV2.fromJson({
        'item': const VideoItemV2(ref: seriesRef, title: 'Video').toJson(),
        'genres': ['Legacy'],
      }),
      throwsFormatException,
    );
    expect(
      () => MediaDetailV2.fromJson({
        'item': const VideoItemV2(ref: seriesRef, title: 'Video').toJson(),
        'recommendations': 'not-a-list',
      }),
      throwsFormatException,
    );
    expect(
      () => EpisodeSummary.fromJson({
        'ref': episodeRef.toJson(),
        'title': 'Episode 1',
        'position': 1,
        'availableAt': '2026-08-19T18:00:00+07:00',
      }),
      throwsFormatException,
    );
  });

  test('rejects relative credit images and invalid durations', () {
    expect(
      () => MediaCredit.fromJson(const {
        'name': 'Person',
        'image': {'url': '/person.jpg'},
      }),
      throwsFormatException,
    );
    expect(
      () => EpisodeSummary.fromJson({
        'ref': episodeRef.toJson(),
        'title': 'Episode 1',
        'position': 1,
        'durationSeconds': 0,
      }),
      throwsFormatException,
    );
    expect(
      () => MediaTrailer.fromJson(const {
        'title': 'Trailer',
        'url': '/watch?v=example',
      }),
      throwsFormatException,
    );
  });

  test('episode position must be a positive integer', () {
    expect(
      () => EpisodeSummary.fromJson({
        'ref': episodeRef.toJson(),
        'title': 'Episode 1',
        'position': 0,
      }),
      throwsFormatException,
    );
  });
}
