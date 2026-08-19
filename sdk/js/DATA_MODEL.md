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
| `kind` | yes | Selects the card and detail layout. Supported values are `liveEvent`, `channel`, `movie`, `series`, and `episode`. |
| `title` | yes | Primary text on catalog cards, detail pages, library entries, and the player. |
| `subtitle` | no | Secondary card text and the fallback description on a detail page. Examples include a year, competition, or episode name. |
| `poster` | no | Portrait artwork used by movie and series cards. It is also a detail-header fallback. |
| `thumbnail` | no | Landscape artwork used by event and channel cards. It is also a detail-header fallback. |
| `startsAt` | no | ISO-8601 time used for schedule labels and time-aware matching. Use a UTC value such as `2026-08-19T12:30:00Z`. |
| `status` | no | Controls scheduled, live, and ended presentation. Defaults to `unknown`. |
| `statusLabel` | no | Short text shown verbatim beside the item, such as `HT` or `Lap 12/20`. |
| `participants` | no | Supplies names, logos, colors, and scores for event cards. Exactly two participants enable the two-sided event layout and matcher. |
| `group` | no | Section heading in a catalog. Keep items from the same group adjacent because the app preserves extension order. |
| `extra` | no | JSON carried into later extension calls; it is never rendered. Episode items use `season`, `episode`, and `seriesTitle` for resume and playback. |

Use `poster` for portrait images and `thumbnail` for landscape images. When
both are available, send both rather than putting the same cropped image in
both fields.

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

### `CatalogQuery` and `CatalogPage`

The host supplies `providerId` and `catalogId`. `category`, `subCategory`, and
`filters` contain the user's current selection. `page` is the opaque cursor
previously returned by the extension.

Return catalog entries in `items`. Return `nextPage` only when another page is
available. The app sends the value back unchanged. `subCategories` supplies
the IDs and labels for an optional secondary category selector.

## Detail data

### `MediaDetail`

| Field | Required | Where the app uses it |
|---|---:|---|
| `item` | yes | Current item and detail-header content. It should retain the same `ref` as the requested item. |
| `description` | no | Full synopsis on the detail page. |
| `genres` | no | Genre labels in the detail metadata row. |
| `runtimeMinutes` | no | Runtime shown on movie details. Supply an integer number of minutes. |
| `certification` | no | Content rating shown in detail metadata, such as `PG-13`. |
| `cast` | no | Cast section on the detail page, in the supplied order. |
| `seasons` | no | Season and episode selector for a series. Keep seasons and episodes in display order. |
| `lastAiredSeason` | no | Season selected by default when the user starts or resumes a series. |
| `lastAiredEpisode` | no | Episode selected by default within `lastAiredSeason`. Supply both last-aired fields together. |

`CastMember.name` is the displayed person name, `character` is the role below
it, and `photoUrl` is the headshot. An episode uses `title` as its primary row,
`description` as its synopsis, `thumbnailUrl` as its landscape still,
`duration` as display-ready text such as `57m`, and `releaseDate` to determine
whether it is available yet.

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
