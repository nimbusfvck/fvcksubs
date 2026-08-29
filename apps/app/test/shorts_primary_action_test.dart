import 'package:flutter_test/flutter_test.dart';
import 'package:fvcksubs_app/library/library_controller.dart';
import 'package:fvcksubs_app/shorts/shorts_primary_action.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_storage/fvcksubs_storage.dart';

const _ref = MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'x');

void main() {
  test('an upcoming item shows Remind Me regardless of kind', () {
    final item = VideoItemV2(
      ref: _ref,
      title: 't',
      releaseDate: DateTime.utc(2099),
    );

    final action = primaryActionFor(item, detail: null, library: LibraryState());

    expect(action.kind, ShortsActionKind.remindMe);
    expect(action.label, 'Remind Me');
  });

  test('an available standalone video shows Watch, then Continue once in progress', () {
    const item = VideoItemV2(ref: _ref, title: 't');

    final fresh = primaryActionFor(item, detail: null, library: LibraryState());
    expect(fresh.kind, ShortsActionKind.watch);
    expect(fresh.label, 'Watch');

    final inProgress = primaryActionFor(
      item,
      detail: null,
      library: LibraryState(
        records: {
          UserMediaState.keyFor(_ref): const UserMediaState(
            item: item,
            progress: Duration(minutes: 3),
          ),
        },
      ),
    );
    expect(inProgress.label, 'Continue');
  });

  test('an event or channel shows Watch Live', () {
    final event = EventItemV2(
      ref: _ref,
      title: 't',
      schedule: Schedule(startsAt: DateTime.utc(2026, 1, 1)),
    );
    const channel = ChannelItemV2(ref: _ref, title: 't');

    expect(
      primaryActionFor(event, detail: null, library: LibraryState()).kind,
      ShortsActionKind.watchLive,
    );
    expect(
      primaryActionFor(channel, detail: null, library: LibraryState()).kind,
      ShortsActionKind.watchLive,
    );
  });

  test('a series shows Details while detail has not resolved yet', () {
    const series = SeriesItemV2(ref: _ref, title: 't');

    final action = primaryActionFor(series, detail: null, library: LibraryState());

    expect(action.kind, ShortsActionKind.details);
    expect(action.label, 'Details');
  });

  test('a series with episodes announced but none released yet shows Details', () {
    const series = SeriesItemV2(ref: _ref, title: 't');
    const episodeRef = MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'unreleased');
    final detail = MediaDetailV2(
      item: series,
      episodeGuide: EpisodeGuide(
        groups: [
          EpisodeGroup(
            id: 'g',
            title: 'Season 1',
            episodes: [
              EpisodeSummary(
                ref: episodeRef,
                title: 'e',
                position: 1,
                availableAt: DateTime.utc(2099),
              ),
            ],
          ),
        ],
      ),
    );

    final action = primaryActionFor(series, detail: detail, library: LibraryState());

    expect(action.kind, ShortsActionKind.details);
  });

  test('a series with a resolvable episode shows Watch, or Continue while resuming', () {
    const episodeRef = MediaRef(extensionId: 'fake', providerId: 'fake.p', id: 'e1');
    const series = SeriesItemV2(ref: _ref, title: 't');
    const guide = EpisodeGuide(
      groups: [
        EpisodeGroup(
          id: 'g',
          title: 'Season 1',
          episodes: [EpisodeSummary(ref: episodeRef, title: 'e', position: 1)],
        ),
      ],
    );
    const detail = MediaDetailV2(item: series, episodeGuide: guide);

    final fresh = primaryActionFor(series, detail: detail, library: LibraryState());
    expect(fresh.kind, ShortsActionKind.watch);
    expect(fresh.label, 'Watch');

    final resumingLibrary = LibraryState(
      records: {
        UserMediaState.keyFor(episodeRef): UserMediaState(
          item: const EpisodeItemV2(
            ref: episodeRef,
            title: 'e',
            episode: EpisodeIdentity(parentRef: _ref, groupId: 'g', position: 1),
          ),
          progress: const Duration(minutes: 1),
          lastWatched: DateTime.utc(2026, 1, 1),
        ),
      },
    );
    final resuming = primaryActionFor(series, detail: detail, library: resumingLibrary);
    expect(resuming.label, 'Continue');
  });

  test('an episode item follows the same Watch/Continue rule as a video', () {
    const episode = EpisodeItemV2(
      ref: _ref,
      title: 't',
      episode: EpisodeIdentity(parentRef: _ref, groupId: 'g', position: 1),
    );

    final action = primaryActionFor(episode, detail: null, library: LibraryState());

    expect(action.kind, ShortsActionKind.watch);
    expect(action.label, 'Watch');
  });
}
