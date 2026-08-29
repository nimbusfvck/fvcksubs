# Shorts Preview Feed — Implementation Plan

Status: planning only. No application or extension behavior is implemented by
this document.

## 1. Goal

Replace Addons in the primary navigation with a Shorts destination and move
Addons into Settings. Shorts presents a vertically paged, autoplaying preview
feed whose data is supplied by extensions.

The initial producer is a Nimora editorial mix led by Coming Soon and filled
with released Trending Movie/TV items, with official trailer metadata sourced
from TMDB. The feature contract must remain general enough for another
extension to provide either an embedded video or a directly playable MP4,
HLS, or DASH preview.

The intended handheld navigation order is:

```text
Home · Shorts · Library · Settings
```

## 2. Decisions

### 2.1 Provider-agnostic shell

Flutter must not check for the Nimora extension id, the TMDB provider id, or
the `coming_soon` catalog/section id. An extension opts into the preview
surface through protocol data, and the registry discovers eligible catalogs.

### 2.2 Additive protocol changes only

The work must remain backward compatible:

- keep protocol `apiVersion` at 2;
- do not add a strict `ProviderRole.preview` value;
- do not add a new `MediaKind`;
- do not add required fields to `MediaItemV2`;
- keep existing extensions valid when they do not provide previews;
- let an older app ignore the new catalog surface and optional JavaScript
  method.

A preview-only catalog has no browse categories, so an older app does not show
it as a Home shelf:

```json
{
  "id": "previews",
  "name": "Previews",
  "categories": [],
  "surface": "preview"
}
```

### 2.3 Preview and full playback are separate workflows

Preview playback is not a source for the full movie, episode, event, or
channel:

```text
preview(item)                 sources(item) -> resolve(sourceId)
      |                                      |
      v                                      v
app player module                       main player
```

The Watch action sends the item into the existing full-content discovery and
resolution workflow. It must never treat a trailer as the full content.

### 2.4 General preview source contract

Catalog items keep using `MediaItemV2` for identity and display data. A preview
is resolved just in time through an optional extension operation:

```dart
Future<PreviewResponse> preview(MediaItemV2 item);
```

The response contains sources in extension-defined preference order:

```dart
sealed class PreviewSource {
  const PreviewSource({required this.id});

  final String id;
}

class EmbeddedPreviewSource extends PreviewSource {
  const EmbeddedPreviewSource({
    required super.id,
    required this.provider,
    required this.mediaId,
  });

  final String provider;
  final String mediaId;
}

class DirectPreviewSource extends PreviewSource {
  const DirectPreviewSource({
    required super.id,
    required this.stream,
  });

  final PlayableStream stream;
}

class PreviewResponse {
  const PreviewResponse({this.sources = const []});

  final List<PreviewSource> sources;
}
```

`DirectPreviewSource` reuses `PlayableStream`, including its URL, request
headers, format, audio, subtitles, and DRM declaration. Preview responses are
session-only and must not be persisted because a direct URL may be signed or
short-lived.

The initial embedded provider is YouTube. Unknown embedded providers remain
decodable but unsupported until the app has a matching adapter. Extensions
must not be allowed to inject arbitrary HTML or JavaScript into a generic
WebView.

### 2.5 Initial Nimora behavior

Nimora contributes a dedicated preview catalog that merges three candidate
pools:

- Coming Soon as the primary identity of the feed;
- released Trending Movie items;
- released Trending TV items.

The merge policy belongs entirely to Nimora. Flutter renders the declared
order and must not re-sort by release state, kind, popularity, or provider.
The initial policy should interleave two Coming Soon candidates with one
released candidate, alternating movie and TV candidates when both are
available. It then de-duplicates the merged result by `MediaRef` while
preserving the first occurrence. This keeps upcoming discovery dominant while
making the full-content Watch action useful throughout the feed.

The catalog provides:

- `MediaRef`/opaque id;
- title;
- artwork;
- media kind;
- release date;
- rating and descriptive subtitle when available.

When an item becomes active or is next in the feed, Nimora reads its TMDB
Videos endpoint:

```text
movie  -> /movie/{id}/videos
series -> /tv/{id}/videos
```

Selection order is official Trailer, official Teaser, non-official Trailer,
then the newest publication date. Nimora returns the YouTube video key as an
`EmbeddedPreviewSource`; the app does not parse a YouTube watch URL.

Items without a supported trailer are skipped lazily by the Shorts workflow;
the catalog must not issue one videos request per candidate up front merely to
filter them. Shegu is not part of the Shorts data path.

## 3. Player architecture

Shorts reuses the existing app-owned player module, lifecycle rules, platform
selection, diagnostics, and test seams. It must not introduce a second player
framework or duplicate the full player page. The initial YouTube experiment
uses `youtube_explode_dart` to resolve a TMDB YouTube video id into short-lived
media URLs that the existing native players can consume.

This resolver is an explicit spike before production integration. Its
performance, stream availability, 403/rate-limit behavior, and physical-device
audio/video handling must be measured. Resolved URLs are never persisted and
every retry obtains a fresh manifest. If the extractor proves too unreliable,
the contract remains unchanged and its YouTube adapter can be replaced by the
official iframe path.

### Initial extractor spike (2026-08-28)

The isolated probe compiled and fetched metadata successfully, but both a
public YouTube API sample (`M7lc1UVf-VE`) and an official movie trailer
(`TcMBFSGVi1c`) failed during manifest resolution with
`VideoUnplayableException: Sign in to confirm you're not a bot`. The movie
trailer metadata took about 1.5 seconds and the failed manifest attempt took
about 10.2 seconds on the test connection. No stream URL was returned, so the
byte-range and native playback stages could not run.

This does not meet the production reliability gate. Keep
`youtube_explode_dart` as a dev-only probe for now; do not wire it into
`AppPreviewPlayer` until manifest resolution succeeds consistently on the
target networks and physical platforms. The generic preview contract remains
valid regardless of whether the eventual YouTube adapter uses extraction or
the official iframe player.

### `darttubefix` comparison probe (2026-08-28)

`darttubefix` (a Dart port of `pytubefix`, pub.dev v1.0.6) was probed as an
alternative extractor because its client-fallback design (`WEB`, `WEB_MUSIC`,
`IOS`, `ANDROID_VR`) looked purpose-built for the exact bot-detection failure
above, and it ships a typed `BotDetection` exception for that case.

Against the same two video ids, `darttubefix` resolved metadata and a stream
manifest successfully in ~1.1-1.3s with no bot-detection error. However, every
returned format (all 30 video/audio itags checked, across both videos) was
flagged `isSabr=true`. A byte-range GET against the selected stream URLs
returned `403` with `content-type: application/vnd.yt-ump` for both video and
audio — YouTube now serves all formats through the SABR/UMP delivery
protocol, which rejects plain HTTP range requests. This is a YouTube
platform-side change, not a library defect, and it means the resolved URLs
cannot be handed to `BetterPlayer`/`MediaKit` as a `DirectPreviewSource`
regardless of which Dart extractor library performs the resolution.

`darttubefix` was removed from `apps/app/pubspec.yaml` after this result; it
did not meet the reliability gate either.

### `youtube_explode_dart` visionOS-client spike (2026-08-28)

An unmerged upstream PR,
[Hexer10/youtube_explode_dart#390](https://github.com/Hexer10/youtube_explode_dart/pull/390),
switches the default InnerTube client from `androidSdkless` to a spoofed
`VISIONOS` (Apple Vision Pro) client, which its author reports avoids
PoToken/JS-challenge requirements entirely. This was probed via a temporary
`dependency_overrides` entry pointing at the PR's fork/branch
(`its-ashutosh-pathak/youtube_explode_dart` @ `fix-visionos-403`).

Using `ytClients: [YoutubeApiClient.visionos]`, every probe in this session
succeeded:

- 4 distinct videos (`M7lc1UVf-VE`, `TcMBFSGVi1c`, `dQw4w9WgXcQ`,
  `9bZkp7q19f0`), including a repeat run on the first two, all resolved a
  manifest in ~1.2-1.9s with no bot-detection error.
- 6 back-to-back resolutions (simulating fast Shorts scrolling) all
  succeeded with no throttling.
- Byte-range GETs against the resolved video/audio URLs returned `206
  Partial Content` with correct `video/mp4`/`audio/mp4` content types. The
  first 64KB were verified to contain a valid MP4 `ftyp` box, not an error
  page.
- Seeking mid-file and near end-of-file (not just byte 0) on a 26MB video
  both returned valid `206` responses, confirming the URLs are ordinary
  range-servable CDN URLs rather than SABR/UMP-gated like the `darttubefix`
  result above.
- Resolved URLs carry the standard ~360-minute (6-hour) `expire` window, and
  required no special request headers — a bare `curl` with no `User-Agent`,
  after following the CDN's normal 2-hop redirect, also returned a valid
  `206` response. Native players (which follow redirects automatically) need
  no header customization to consume these URLs.

This meets the CLI-level reliability gate cleanly, which the original
`youtube_explode_dart` default-client probe and the `darttubefix` probe both
failed. Two caveats remain before promoting this into `AppPreviewPlayer`:

- The fix lives on an **unmerged, third-party fork**, not a pub.dev release.
  Depending on it means pinning a `git` dependency to someone else's branch,
  which YouTube's ongoing anti-extraction changes could break without
  warning, same as any reverse-engineered client spoof.
- Physical-device audio/video playback through `BetterPlayer`/`MediaKit`
  (the remaining item in the §7 reliability gate) has not been tested — only
  CLI-level metadata/manifest/byte-range checks have run.

Do not remove the `dependency_overrides` entry in the root `pubspec.yaml`
until this is either promoted (pin to a specific commit, not a mutable
branch) or abandoned in favor of the official iframe path.

Feature widgets depend on an injected app preview-player entry point rather
than constructing BetterPlayer, MediaKit, or a YouTube controller directly:

```text
existing player module
└── AppPreviewPlayer
    ├── YouTube video id
    │   └── youtube_explode_dart resolver
    │       └── PlayableStream
    └── direct PlayableStream
        └── existing platform player builder
            ├── BetterPlayer on Android
            └── MediaKit on iOS and macOS
```

`AppPreviewPlayer` is a small dispatcher inside `apps/app/lib/player`, not a
parallel player stack. Its YouTube branch resolves late and then delegates the
result to the same native player mapping as a direct extension preview. Both
branches therefore share the current play, pause, mute, readiness, lifecycle,
capability, diagnostics, and disposal behavior and expose no transport
controls on the Shorts surface.

Only the active page constructs a native player or WebView. Adjacent items may
prefetch catalog and preview metadata but must not hold additional active
decoders by default.

## 4. Shorts state ownership

Create a feature-first module:

```text
apps/app/lib/shorts/
├── shorts_cubit.dart
├── shorts_state.dart
├── shorts_page.dart
├── shorts_feed_item.dart
└── widgets/
```

`ShortsCubit` owns asynchronous workflow state:

- preview-catalog discovery;
- loading, usable data, refresh, empty, and recoverable error states;
- item de-duplication by `MediaRef`;
- lazy preview resolution;
- current/next metadata prefetch;
- selection of the first platform-supported source;
- skipping items without a usable preview;
- retry and refresh;
- stale-request protection.

The page keeps short-lived presentation state locally:

- current page index;
- whether a vertical drag is active;
- feed-session muted state;
- transient sound/readiness feedback.

The feed starts muted. A tap on the video toggles sound, and that selection is
kept across subsequent pages for the current Shorts session. Leaving and
re-entering Shorts starts muted again.

## 5. User experience

- Use a vertical `PageView`, one item per viewport.
- Pause playback as soon as scrolling starts and autoplay only after the next
  page settles.
- Pause and dispose playback when the route is covered, the app is backgrounded,
  or another destination is selected.
- Loop the active preview when the backend supports it.
- Use a black background and `BoxFit.contain` for landscape trailers so they
  are not aggressively cropped.
- Show artwork while the preview initializes or when autoplay is blocked.
- Provide semantic, minimum-size actions for the availability-aware primary
  action, Favorite, and Sound.
- Show title, kind, release date/year, rating, and a bounded synopsis.
- Cover loading, empty, error, retry, long text, narrow screens, and text
  scaling without overflow.
- On larger screens and TV, center a bounded portrait feed viewport and retain
  keyboard/remote up-down navigation.

## 6. Watch workflow

The primary action is derived from typed item state rather than a fixed label:

- a future release shows **Remind Me**;
- an available standalone video shows **Watch** or **Continue**;
- a series shows **Watch** or **Continue** after selecting its playback target;
- a live event or channel shows **Watch Live**;
- an item whose playable state cannot be determined shows **Details**.

Watch and Watch Live are explicit full-playback intents:

- `VideoItemV2`: call `playItemV2` directly;
- `EventItemV2`, `ChannelItemV2`, and `EpisodeItemV2`: use the existing direct
  playback workflow;
- `SeriesItemV2`: fetch metadata, choose the resume/default available episode
  through a shared primary-episode resolver, then call `playItemV2`;
- if no full source is available, show the existing usable error and remain on
  Shorts.

The primary series-target logic currently private to Detail should move into a
tested helper shared by Detail and Shorts. Navigation and snackbars remain
outside Cubit state.

## 7. Navigation and Settings

Navigation changes are made only after the preview contract, producer, and
player adapters work in tests:

1. Replace `AppDestination.addons` with `AppDestination.shorts`.
2. Map Shorts to `ShortsPage` and make it edge-to-edge on handhelds.
3. Keep the same destination set on bottom navigation and the TV/desktop rail.
4. Add an Addons tile at the top of Settings.
5. Let the tile push the existing `AddonsPage` and optionally show installed
   extension count and available-update state.
6. Preserve all existing install, consent, update, toggle, and nested-dialog
   behavior.

## 8. Implementation order

### Phase 0 — Protect the baseline

- Inspect the existing uncommitted player changes and identify overlapping
  files.
- Preserve those changes; do not reset, stash, or overwrite them.
- Run the smallest existing player and Addons tests needed to establish the
  starting point.

### Phase 1 — Core compatibility tests and models

- Write tests for legacy manifests, preview-surface manifests, empty-category
  catalogs, old extensions without `preview`, and unknown embedded providers.
- Add `CatalogSurface` with `browse` as the default.
- Add the preview-source JSON union and response decoder.

Completion gate: all old protocol fixtures still pass without modification.

### Phase 2 — Extension host and SDK

- Add optional `ContentExtension.preview` with an empty default.
- Make `JsExtension` check for the optional JS method before calling it.
- Add registry discovery/routing for preview catalogs.
- Add JS SDK registration helpers and TypeScript declarations.
- Cover embedded, direct, absent, malformed, and unsupported preview results.

Completion gate: fake QuickJS extensions can return both YouTube and direct
preview sources while old bundles still load.

### Phase 3 — Nimora producer

- Declare a preview-only catalog with no browse categories.
- Merge Coming Soon with released Trending Movie/TV candidates in
  extension-owned editorial order.
- De-duplicate the merged feed by `MediaRef` while preserving first occurrence.
- Add a TMDB-only preview resolver.
- Add captured fixture tests for movie/series video responses and failure
  isolation.
- Regenerate `lib/bundle.js` after source changes.

Completion gate: the real QuickJS engine returns the deterministic merged and
de-duplicated feed plus typed YouTube preview sources without any Shorts
request to Shegu.

### Phase 4 — Extend the existing player module

- Run the isolated `youtube_explode_dart` manifest and byte-range probe first.
- Record metadata/manifest latency, available stream shapes, selected quality,
  URL expiry, and whether the selected URLs return media bytes.
- Add an injectable `AppPreviewPlayer` entry point to app composition while
  keeping it inside the existing player module.
- Implement a late, non-persistent YouTube resolver behind that entry point
  only if the spike meets the reliability gate.
- Delegate direct `PlayableStream` previews to the existing Android, iOS, and
  macOS platform player builder rather than creating another direct player.
- Make mute, play/pause, loop, initialization failure, and disposal testable
  without native views.

Completion gate: widget tests demonstrate one active fake player, reactive
mute/play state, and source fallback.

### Phase 5 — Shorts feature

- Implement the Cubit, state, page, feed cards, prefetch, and fallback logic.
- Add Watch, Favorite, and Sound actions.
- Extract and test the shared primary series-target resolver.
- Cover vertical paging, autoplay, mute persistence within the session, error,
  refresh, narrow layout, and long content.

Completion gate: Shorts works end-to-end with fake registry and fake players.

### Phase 6 — Navigation, Settings, and documentation

- Replace the Addons destination with Shorts.
- Add the nested Addons entry to Settings.
- Update navigation, Settings, Addons, app-layer, protocol, SDK, and user-journey
  tests/documentation.

Completion gate: the fixed navigation is Home, Shorts, Library, Settings on
both bottom bar and rail, and Addons remains fully reachable from Settings.

### Phase 7 — Integrated validation

Run the relevant package tests during each phase, then finish with:

- core tests and analysis;
- extension-host tests and analysis;
- JS SDK and real QuickJS fixture tests;
- Nimora tests and generated-bundle verification;
- full Flutter test suite;
- `flutter analyze` from `apps/app`;
- `git diff --check`.

Physical verification remains separate and required on Android, iOS, and
macOS for autoplay policy, sound toggling, WebView/native decoder disposal,
background/foreground behavior, rapid swiping, and Watch handoff to the full
player.

## 9. Acceptance criteria

- No Flutter branch checks Nimora, TMDB, Coming Soon, or a provider-specific
  catalog id.
- Feed composition, interleaving, and de-duplication remain extension-owned;
  Flutter preserves the returned order.
- Existing extensions load and browse exactly as before.
- An extension may return a YouTube embed or direct playable preview without a
  Shorts UI change.
- Unknown embed providers fail safely and may fall through to another source.
- Direct preview headers and stream format reach the native player unchanged.
- Only the visible page plays; leaving or covering Shorts stops playback.
- Shorts starts muted and tap toggles sound without exposing transport
  controls.
- The primary action is availability-aware, and Watch resolves full content
  through the existing source workflow.
- Addons is absent from primary navigation and fully functional from Settings.
- Automated checks pass, with physical player behavior reported separately.
