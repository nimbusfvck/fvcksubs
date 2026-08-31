# 9. Protocol v2

This document defines the production contract. The shell, host, extensions,
and persisted library records use protocol version 2 only.

## 9.1 Goals

- Invalid field combinations fail at the extension boundary.
- The shell renders capabilities without checking extension or provider IDs.
- Values owned by an extension remain data, not constants in Flutter code.
- Fields that affect behavior are typed. Display-only metadata stays generic.
- Every playable item has its own stable reference.
- Existing library and playback records survive the upgrade.

The app may contain versioned protocol enums and universal UI policy. It must
not contain provider aliases, category IDs, matching vocabulary, source names,
or private extension payload keys.

## 9.2 Item variants

An item has a common identity and exactly one variant. The discriminator is
strict: fields belonging to a different variant are rejected.

```ts
interface MediaBase {
  ref: MediaRef;
  title: string;
  /** Extension-authored descriptive text, not composed metadata. */
  subtitle?: string;
  releaseYear?: number;
  rating?: number;
  artwork?: Artwork;
}

type MediaItem =
  | VideoItem
  | SeriesItem
  | EpisodeItem
  | ChannelItem
  | EventItem;

interface VideoItem extends MediaBase {
  kind: 'video';
}

interface SeriesItem extends MediaBase {
  kind: 'series';
}

interface EpisodeItem extends MediaBase {
  kind: 'episode';
  episode: EpisodeIdentity;
}

interface ChannelItem extends MediaBase {
  kind: 'channel';
}

interface EventItem extends MediaBase {
  kind: 'event';
  schedule: Schedule;
  participants?: Participant[];
  branding?: EventBranding;
}
```

`video` describes a standalone playable work without assuming a film. `event`
describes scheduled content without assuming a particular competition.
`branding` is optional display data for a competition, tournament, or organizer;
it does not change event matching or playback behavior.

`subtitle` is extension-authored descriptive text. `releaseYear` and `rating`
are optional structured values; the shell composes their card and detail
presentation with the subtitle. Ratings are non-negative numbers and do not
imply a particular scale.

## 9.3 Shared capabilities

```ts
interface Artwork {
  portrait?: ImageRef;
  landscape?: ImageRef;
  logo?: ImageRef;
}

interface Schedule {
  startsAt: string;
  state?: 'scheduled' | 'live' | 'ended' | 'unknown';
  label?: string;
}

interface EventBranding {
  logo?: ImageRef;
  primaryColor?: string;
  secondaryColor?: string;
}
```

Schedule fields cannot appear on another variant. `label` is display text;
logic uses `state` and `startsAt`.

Catalog grouping belongs to the response rather than each item:

```ts
interface CatalogSection {
  id: string;
  title?: string;
  items: MediaItem[];
}

interface CatalogPage {
  sections: CatalogSection[];
  nextPage?: string;
  subCategories?: SubCategory[];
}
```

This removes the adjacency rule and makes an unlabelled section explicit.

## 9.4 Detail and episode guide

Behavioral data remains typed. Metadata that is only rendered is expressed as
tags, facts, credits, and trailers.

```ts
interface MediaDetail {
  item: MediaItem;
  description?: string;
  tags?: string[];
  facts?: Fact[];
  credits?: Credit[];
  trailers?: Trailer[];
  recommendations?: MediaItem[];
  episodeGuide?: EpisodeGuide;
}

interface Fact {
  label: string;
  value: string;
}

interface Credit {
  name: string;
  role?: string;
  image?: ImageRef;
}

interface Trailer {
  /** User-facing preview title. */
  title: string;
  /** Absolute URL opened by the app's trailer action. */
  url: string;
  /** Optional platform label, such as YouTube. */
  site?: string;
  /** Optional preview image. */
  thumbnail?: ImageRef;
  /** Optional MIME type; `video/*` identifies a directly playable preview. */
  mimeType?: string;
}

interface EpisodeGuide {
  groups: EpisodeGroup[];
  defaultEpisodeRef?: MediaRef;
}

interface EpisodeGroup {
  id: string;
  title: string;
  episodes: EpisodeSummary[];
}

interface EpisodeSummary {
  ref: MediaRef;
  title: string;
  description?: string;
  artwork?: Artwork;
  durationSeconds?: number;
  availableAt?: string;
}
```

The protocol does not assume that groups are numbered seasons. An extension
may use seasons, volumes, years, or another grouping. `defaultEpisodeRef`
replaces a pair of positional season and episode numbers.

An episode reference must contain every stable identifier needed by metadata,
source, subtitle, history, and resume calls. The shell does not parse its `id`.

## 9.5 Stream contract

`StreamSource.providerId` is the stable source preference key. Its display
name comes from `ProviderDecl.name`; a second provider label is not returned by
the source.

`StreamSource.id` is the identity passed to `resolve` and the cache identity.
A resolved stream does not repeat a source label.

The optional `segments` role returns item-level playback intervals separately from stream
resolution. Its response is `{ "segments": [...] }`, with integer millisecond boundaries;
extensions may omit the role, and the host treats failures as an empty result.

Separate audio remains supported only when the native mapping forwards it. A
platform that cannot play a declared combination must reject the source before
opening the player and provide a usable error.

## 9.6 Strict validation

The host rejects:

- unknown item discriminators;
- fields from a different item variant;
- relative media and artwork URLs;
- non-UTC protocol timestamps;
- an episode without its own reference;
- `defaultEpisodeRef` that is absent from the guide;
- an empty source ID or source label;
- provider IDs not declared by the manifest;
- incompatible DRM fields;
- numbers outside their declared range.

`EventItem.branding` is an optional additive field. Existing extensions that do
not send it remain valid. An extension that sends it requires a host build that
understands the field because item decoding remains strict.

SDK registration performs the same structural checks before a value reaches
the Dart decoder. Error messages include the role and field path.

## 9.7 Version 1 migration

The adapter is selected by `apiVersion`, never by extension ID.

| Version 1 | Version 2 |
|---|---|
| `movie` | `video` |
| `poster`, `thumbnail` | `artwork.portrait`, `artwork.landscape` |
| `startsAt`, `status`, `statusLabel` | `schedule` on an event |
| `group` on each item | one `CatalogSection` |
| `genres` | `tags` |
| `runtimeMinutes` | a duration fact during compatibility decoding |
| `certification` | a certification fact |
| `cast` | `credits` |
| `seasons` | `episodeGuide.groups` |
| `lastAiredSeason` and `lastAiredEpisode` | `defaultEpisodeRef` |
| episode values in `extra` | typed `EpisodeIdentity` and episode `MediaRef` |

Persisted records use the `library.records.v2` schema. Unsupported records are
ignored and never passed into playback.

## 9.8 Delivery order

1. Add v2 types and validators.
2. Keep extension and persistence adapters on v2.
3. Move app consumers to the v2 in-memory model.
4. Update the JavaScript SDK and examples.
5. Migrate Nimora and rebuild its bundle.
6. Keep all producer paths on v2.
