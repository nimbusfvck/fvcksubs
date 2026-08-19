# 10. Hardcode Audit

The audit separates stable protocol constants from values that belong to an
extension, user preference, platform capability, or app configuration.

## 10.1 Rules

Allowed in code:

- versioned protocol enum values;
- security limits and platform capability tables;
- design-system dimensions and semantic colors;
- user-facing shell actions owned by the app.

Not allowed in the shell:

- extension and provider IDs;
- upstream or source names;
- catalog category and filter IDs;
- matching aliases or domain vocabulary;
- a fixed set of subtitle languages;
- provider-private keys inside an untyped map;
- display labels used as cache or routing identities.

## 10.2 Findings

| Location | Finding | Target |
|---|---|---|
| `player/stream_player_mapping.dart` | Subtitle tracks are filtered to `en` and `id`. | Accept every valid language and use the saved preference only for default selection. |
| `detail/episode_target.dart` | `season`, `episode`, and `seriesTitle` are magic keys in `MediaItem.extra`. | Typed episode identity and a stable reference per episode. |
| `player/player_page.dart` | Playback equality reads episode magic keys. | Compare stable item references. |
| `content/media_item.dart` | Flat optional schedule and participant fields allow invalid combinations. | Strict item variants. |
| `content/media_item.dart` | Artwork orientation is encoded as separate top-level fields. | `Artwork` capability. |
| `protocol/catalog.dart` | Repeated `group` values require contiguous ordering. | Explicit catalog sections. |
| `content/stream.dart` | `StreamSource.provider` duplicates manifest display metadata. | Display through `ProviderDecl.name`; retain `providerId` only. |
| `stream_player_mapping.dart` | `PlayableStream.label` is used as a cache key. | Use the selected `StreamSource.id`. |
| `content/stream.dart` | `audioUrl` crosses the protocol but is not forwarded by the native mapping. | Implement per-platform forwarding or reject the combination explicitly. |
| `detail/detail_page.dart` | Only two tags are rendered through `take(2)`. | Responsive metadata layout with an explicit UI overflow policy. |
| `stream_player_mapping.dart` | Cache sizes are literals in player construction. | Named app configuration, independently testable from protocol data. |
| Core documentation and tests | Several examples name historical providers and domains. | Neutral fixture names outside tests specifically covering domain matching. |

## 10.3 Fields that are used but should change

| Field | Decision | Reason |
|---|---|---|
| `startsAt` | Move to `EventItem.schedule` | Required for schedule display and matching, but invalid on unrelated variants. |
| `status`, `statusLabel` | Move to `Schedule` | Same lifecycle as `startsAt`. |
| `participants` | Move to `EventItem` | General across events, invalid on ordinary video content. |
| `poster`, `thumbnail` | Merge into `Artwork` | They describe orientation, not separate behavior. |
| `kind` | Replace `movie` with `video` | Describes standalone playback without a content-domain assumption. |
| `genres` | Rename to `tags` | Display grouping is broader than genre. |
| `runtimeMinutes` | Replace with seconds or a fact | Avoid unit-specific naming and extension-formatted values. |
| `certification` | Move to `facts` | Display-only metadata does not require shell behavior. |
| `cast` | Generalize to `credits` | Supports any credited person and role. |
| `seasons` | Generalize to `EpisodeGuide.groups` | Does not require every collection to use numbered seasons. |
| last-aired pair | Replace with `defaultEpisodeRef` | One checked identity cannot form a half-populated pair. |
| `extra` | Remove after migration | Hidden keys defeat static and runtime validation. |

## 10.4 Fields requiring a product decision

- `Participant.score` is in the protocol but not rendered. Remove it unless a
  general event-result UI is part of v2.
- `audioUrl` is promised by the current protocol. Keep and implement it unless
  supported native players cannot consume separate audio; in that case reject
  it explicitly and remove it only in a documented breaking release.
- Generic `facts` must remain display-only. Routing, playback, availability,
  identity, and resume data may not be hidden inside it.

## 10.5 Required regression tests

- A new extension/provider ID works without a Flutter code change.
- Unknown category, section, and filter IDs round-trip unchanged.
- Every subtitle language reaches the picker.
- Matching behavior changes through extension profile data only.
- A video cannot carry event schedule fields.
- An event cannot omit its required start time.
- Every episode can be addressed, resumed, and resolved through its own ref.
- Display labels can change without changing routing, cache, or preferences.
