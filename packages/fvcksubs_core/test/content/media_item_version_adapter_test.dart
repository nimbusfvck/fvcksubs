import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:test/test.dart';

void main() {
  const ref = MediaRef(
    extensionId: 'legacy-extension',
    providerId: 'legacy.catalog',
    id: 'item-7',
  );

  test('apiVersion 2 decodes directly without a legacy payload', () {
    final envelope = VersionedMediaItem.fromProtocolJson({
      'ref': ref.toJson(),
      'kind': 'video',
      'title': 'A video',
    }, apiVersion: 2);

    expect(envelope.item, isA<VideoItemV2>());
    expect(envelope.requiresLegacyRequest, isFalse);
    expect(envelope.requestItemForV1, throwsStateError);
  });

  test('apiVersion 1 preserves provider payload outside the v2 item', () {
    final envelope = VersionedMediaItem.fromProtocolJson({
      'ref': ref.toJson(),
      'kind': 'movie',
      'title': 'A video',
      'poster': {'url': 'https://cdn.example/poster.jpg'},
      'extra': {'providerContentId': 'remote-42'},
    }, apiVersion: 1);

    final item = envelope.item as VideoItemV2;
    expect(item.artwork?.portrait?.url, 'https://cdn.example/poster.jpg');
    expect(envelope.requiresLegacyRequest, isTrue);
    expect(envelope.requestItemForV1().extra, {
      'providerContentId': 'remote-42',
    });
    expect(item.toJson(), isNot(contains('extra')));
  });

  test('legacy envelope round-trips without losing request data', () {
    final original = VersionedMediaItem.fromV1(
      const MediaItem(
        ref: ref,
        kind: MediaKind.series,
        title: 'A collection',
        extra: {'opaque': 'value'},
      ),
    );

    expect(VersionedMediaItem.fromJson(original.toJson()), original);
  });

  test('legacy episode receives a distinct deterministic ref', () {
    final first = VersionedMediaItem.fromV1(
      const MediaItem(
        ref: ref,
        kind: MediaKind.episode,
        title: 'Episode four',
        extra: {'season': 2, 'episode': 4, 'opaque': 'kept'},
      ),
    );
    final second = VersionedMediaItem.fromV1(first.requestItemForV1());

    final episode = first.item as EpisodeItemV2;
    expect(episode.ref, isNot(ref));
    expect(episode.ref, (second.item as EpisodeItemV2).ref);
    expect(episode.episode.parentRef, ref);
    expect(episode.episode.groupId, 'season:2');
    expect(episode.episode.position, 4);
    expect(first.requestItemForV1().extra['opaque'], 'kept');
  });

  test('legacy live event maps schedule and participants', () {
    final envelope = VersionedMediaItem.fromV1(
      MediaItem(
        ref: ref,
        kind: MediaKind.liveEvent,
        title: 'Scheduled event',
        startsAt: DateTime.utc(2026, 8, 20, 10),
        status: LiveStatus.live,
        statusLabel: 'In progress',
        participants: const [
          Participant(name: 'Side A'),
          Participant(name: 'Side B'),
        ],
      ),
    );

    final event = envelope.item as EventItemV2;
    expect(event.schedule.state, ScheduleState.live);
    expect(event.schedule.label, 'In progress');
    expect(event.participants, hasLength(2));
  });

  test('legacy event without a start time fails instead of inventing data', () {
    expect(
      () => VersionedMediaItem.fromV1(
        const MediaItem(
          ref: ref,
          kind: MediaKind.liveEvent,
          title: 'Incomplete event',
        ),
      ),
      throwsFormatException,
    );
  });

  test('legacy video with event-only fields is rejected', () {
    expect(
      () => VersionedMediaItem.fromV1(
        MediaItem(
          ref: ref,
          kind: MediaKind.movie,
          title: 'Invalid video',
          startsAt: DateTime.utc(2026, 8, 20),
        ),
      ),
      throwsFormatException,
    );
  });

  test('unsupported protocol version is rejected', () {
    expect(
      () => VersionedMediaItem.fromProtocolJson(const {}, apiVersion: 3),
      throwsFormatException,
    );
  });
}
