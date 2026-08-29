# SDK data model

Extensions return plain JSON. Omit optional fields when the upstream does not
provide a useful value. Do not send empty strings as substitutes for missing
data.

## Identity

### `MediaRef`

| Field | Required | Purpose |
|---|---:|---|
| `extensionId` | yes | Identifies the installed extension. It must match the manifest. The app uses it for routing, history, and library records; it is not displayed. |
| `providerId` | yes | Identifies the catalog or metadata provider that owns the item. It must match a provider declared in the manifest; it is not displayed. |
| `id` | yes | Stable item ID owned by the provider. The app stores it and returns it to `meta`, `sources`, and `subtitles` without parsing it. |

The three fields together form the item identity. Do not reuse the same
combination for different content and do not change it when only display data
changes.

## Catalog items

### `MediaItem`

| Field | Required | Where the app uses it |
|---|---:|---|
| `ref` | yes | Routing, library records, playback history, and source lookup. It is not shown to the user. |
| `kind` | yes | Selects the item's validated shape and behavior: `video`, `series`, `episode`, `channel`, or `event`. |
| `title` | yes | Primary text on catalog cards, detail pages, library entries, and the player. |
| `subtitle` | no | Secondary card text and the fallback description on a detail page. Examples include a year, competition, or episode name. |
| `artwork` | no | Shape-specific images. `portrait` is used by narrow cards, `landscape` by wide cards and detail headers, and `logo` for an optional title mark. |

Only `event` accepts `schedule`, `participants`, and optional `branding`. Its
schedule requires a UTC `startsAt`; `state` controls lifecycle indicators and
`label` is optional display text. Branding can provide a competition,
tournament, or organizer logo plus `#RRGGBB` primary and secondary colors for
generated event artwork. Only `episode` accepts `episode`, containing its `parentRef`,
opaque `groupId`, and one-based `position`. Fields from another kind are
rejected instead of ignored.

### `ImageRef`

`url` is an absolute image URL. Its host must be covered by
`manifest.json.permissions.hosts`, including the destination of any redirect.

### `Participant`

| Field | Required | Where the app uses it |
|---|---:|---|
| `name` | yes | Full participant name and matching input. |
| `shortName` | no | Compact card label and an alternative matching input. |
| `logo` | no | Participant logo on event cards. |
| `color` | no | CSS color used when the app generates fallback event artwork. |
| `score` | no | Display-only score. Keep it a string so values such as `145/4` remain intact. |

### `EventBranding`

| Field | Required | Where the app uses it |
|---|---:|---|
| `logo` | no | Competition, tournament, or organizer mark on generated event artwork. |
| `primaryColor` | no | Primary generated event-artwork color as `#RRGGBB`. |
| `secondaryColor` | no | Secondary generated event-artwork color as `#RRGGBB`. |

At least one branding field must be present when `branding` is supplied. The
field is optional so existing event payloads remain valid.

### `CatalogQuery` and `CatalogPage`

The host supplies `providerId` and `catalogId`. `category`, `subCategory`, and
`filters` contain the user's current selection. `page` is the opaque cursor
previously returned by the extension.

Return entries inside explicit `sections`. Every section requires a stable
opaque `id`, may have a displayed `title`, and contains ordered `items`.
Return `nextPage` only when another page is available; the app sends the value
back unchanged. `subCategories` supplies IDs and labels for an optional
secondary selector.

## Detail data

### `MediaDetail`

| Field | Required | Where the app uses it |
|---|---:|---|
| `item` | yes | Current item and detail-header content. It should retain the same `ref` as the requested item. |
| `description` | no | Full synopsis on the detail page. |
| `tags` | no | Short classification labels displayed in extension order. |
| `facts` | no | Display-only `label` and `value` pairs. Use these for metadata the app does not need to interpret. |
| `credits` | no | Credited people or entities with `name`, optional `role`, and optional `image`. |
| `trailers` | no | Preview videos with a display `title`, absolute `url`, optional `site`, `thumbnail`, and `mimeType`. A `video/*` MIME identifies a directly playable preview; otherwise the app opens the URL externally. |
| `recommendations` | no | Related `MediaItem` entries shown in a recommendation shelf at the bottom of detail. Keep references stable so selecting an entry can open its detail or playback route. |
| `episodeGuide` | no | Typed episode navigation grouped by extension-defined IDs and titles. |

Each episode summary has its own stable `ref`, a `title`, and a positive
one-based `position` displayed within its group. `description`, `artwork`,
positive `durationSeconds`, and UTC `availableAt` are optional.
`defaultEpisodeRef`, when supplied, must point to an episode listed in the
guide. Groups are generic and may represent any extension-defined grouping.

## Source discovery and playback

### `StreamSource`

| Field | Required | Where the app uses it |
|---|---:|---|
| `id` | yes | Opaque value passed to `resolve`. Create it with `fvcksubs.sourceId` so it survives an app restart. |
| `label` | yes | Source name shown in loading state and the player source picker. Use a neutral user-facing alias. |
| `provider` | no | Optional display grouping in the source picker. |
| `providerId` | no | Stable source-priority key. `defineStream` fills it from the registered provider, so extension code normally omits it. |

### `PlayableStream`

| Field | Required | Where the app uses it |
|---|---:|---|
| `url` | yes | Final media URL loaded by the player. Resolve it as late as possible when the URL expires. |
| `headers` | no | Headers attached to media requests, including `Referer` or `User-Agent` when required. |
| `format` | no | Player hint: `hls`, `dash`, or `other`. |
| `drm` | no | ClearKey or Widevine configuration used by the native player. |
| `audioUrl` | no | Separate audio track paired with the main media URL. |
| `label` | no | Resolved quality or rendition text shown by the player. |
| `subtitles` | no | Subtitle tracks available with this stream. |

A subtitle track uses `language` for preference matching and display, `url` as
the absolute SRT or VTT location, and optional `label` for extra text such as
`Forced` or `SDH`.

All media, image, subtitle, licence, and redirect hosts must be allowed by the
manifest.
