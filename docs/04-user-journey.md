# 4. User Journey

What the user does, and what happens underneath at each step. Every diagram traces a real
path through the system.

## 4.1 The journey at a glance

```mermaid
journey
    title From install to playback
    section Set up
      Open the app for the first time: 3: User
      Add an extension source: 4: User
      Review what it may reach, accept: 4: User
    section Find something
      Pick a category: 5: User
      Scan the shelves: 5: User
      Narrow, or search across everything: 4: User
    section Watch
      Open an item: 5: User
      Wait briefly while sources are found: 3: User
      Watch, switch source or quality freely: 5: User
    section Come back
      Resume where they left off: 5: User
      Find it again in the library: 5: User
```

## 4.2 First launch

An installation with no extensions shows an empty state and a link to Addons.

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant A as App
    participant S as Stores
    participant R as Registry

    U->>A: opens the app
    A->>S: read settings, library, selections
    A->>R: load every previously-installed extension
    Note over A,R: an extension that no longer loads is skipped<br/>without preventing application startup
    A->>R: ask for categories
    alt no extensions
        R-->>A: none
        A-->>U: "No extensions installed" + a route to Addons
    else has extensions
        R-->>A: categories, in install order
        A-->>U: the browse screen, on the last-used category
    end
```

Everything the first frame depends on is read **before** the UI is built, so the app opens
on the user's actual last state rather than picking a default and correcting itself a frame
later.

## 4.3 Adding an extension

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant AD as Addons screen
    participant IC as Install controller
    participant N as Extension index
    participant R as Registry

    U->>AD: pastes an index URL, taps Check
    AD->>IC: refresh
    IC->>N: fetch the index
    N-->>IC: list of extensions: id, version, urls, hash, hosts
    IC->>IC: compare against installed versions
    IC-->>AD: rows marked Install or Update

    U->>AD: taps Install or Update
    AD-->>U: version, release notes, and permission changes
    AD->>IC: install
    IC->>IC: which hosts are new versus already granted?
    alt the install would widen access
        IC-->>U: consent sheet — what it may reach, and what is new
        U-->>IC: accept or decline
        Note over IC: declining stops here — nothing is downloaded
    end
    IC->>N: download manifest + bundle
    IC->>IC: verify the bundle against the declared hash;<br/>verify the manifest's id matches
    Note over IC: all-or-nothing — a partially verified download<br/>is never handed onward
    IC->>R: load and register it, live
    IC-->>U: its categories appear immediately — no restart
```

Install behavior:

- **The prompt happens before the download.** Everything the user needs in order to decide
  is readable from the index alone, which is why the index repeats the hosts the manifest
  will declare.
- **Only what actually widens access is highlighted.** Re-listing permissions the user
  already granted trains them to click through; the sheet separates new from already
  granted.
- **Consent defaults to refusal.** If no way to ask exists, the answer is no.

Every update shows its version and release notes before installation. Permission details
highlight only newly requested hosts; previously granted hosts remain visually secondary.

## 4.4 Browsing

```mermaid
flowchart TB
    U(["User opens the app"]) --> CAT["Category chips<br/><i>declared by installed extensions</i>"]
    CAT --> PICK["Plugin selector<br/><i>whose data, when several extensions serve this category</i>"]
    PICK --> SHELF["One shelf per catalog<br/><i>each loads and fails independently</i>"]
    SHELF --> SEC["Sections within a shelf<br/><i>each capped on its own</i>"]
    SEC --> MORE["'See more' → the full catalog,<br/>already narrowed to that section"]
    MORE --> CHIPS["Subcategory chips + filters + endless scroll"]
```

Three narrowings, and **only the first is the shell's**:

| Level | Chosen by | Behaviour |
|---|---|---|
| Category | the user, from chips the extensions declare | There is no shell-invented "All" chip and no "featured" flag. An extension wanting a curated front page declares its own category, and it lands first. |
| Subcategory | the user, from chips the extension **returned** | Ids are opaque and echoed straight back. The list arrives with every response, so the chips stay put while the user moves between them. |
| Group | the extension | Headings inside one response. Shown on the full screen, hidden in previews where a handful of items across as many groups would be mostly headings. |

Sections are capped independently so each section remains visible in previews.

Each shelf loads independently. A failed catalog shows an error and retry action in its own
shelf.

### What the user does not see

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant H as Browse screen
    participant C as Session cache
    participant R as Registry
    participant X as Extension

    U->>H: taps a different category
    H->>C: already have this catalog + category?
    alt yes
        C-->>H: hand it back synchronously
        Note over H: no spinner, no round trip, scroll position kept
    else no
        H->>C: load
        C->>R: catalog query
        R->>X: catalog(query)
        X-->>R: a page of items
        C-->>H: page
    end
    U->>H: taps the same category again later
    H->>C: served from cache again
    U->>H: pulls to refresh
    H->>C: reload — the old content stays visible until the new lands
```

Switching category never refetches. **Asking for fresh data is something the user does**, not
a side effect of navigating — and while a refresh runs, what is already on screen stays on
screen instead of blanking.

## 4.5 Searching

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant S as Search screen
    participant R as Registry
    participant A as Extension A
    participant B as Extension B

    U->>S: opens search from the browse screen, types a query
    S->>R: search
    par every enabled extension that declares the role
        R->>A: search(query)
        R->>B: search(query)
    end
    A-->>R: results
    B--xR: fails → contributes nothing
    R-->>S: merged results
    S-->>U: one grid, no categories, no attribution needed
```

Search is reached from a field at the top of the browse screen, **not** from the navigation
bar. Search spans every extension without applying the selected category, while
browsing shows *one* extension's take on *one* category. Answering both on the same screen
produces a result set whose extent contradicts the chips above it.

## 4.6 Opening an item

```mermaid
flowchart TD
    T["User taps a card"] --> K{"Does this item support<br/>a detail screen?"}
    K -->|"a film or a series"| D["Detail screen<br/>hero art · synopsis · cast · episodes · Play"]
    K -->|"a live event or a channel"| P["The tap <b>is</b> play"]
    D -->|Play| P
```

Long-form content opens a detail screen, and source discovery is deferred until the user
selects Play. Live events and channels start the playback flow directly.

### On the detail screen

```mermaid
flowchart LR
    subgraph LABEL["The Play button says what will actually happen"]
        A["nothing watched yet"] --> A1["Play — the most sensible starting point"]
        B["partly watched"] --> B1["Continue, naming where"]
        C["a specific episode tapped"] --> C1["that episode, no second-guessing"]
    end
```

For episodic content the shell's own best guess (from catalog metadata) is confirmed against
what is actually available before playing, so a viewer is never dropped onto something that
has not been released yet. A viewer who taps a *specific* episode is never second-guessed —
that tap already is their answer.

## 4.7 Play

Playback follows this sequence:

```mermaid
flowchart TD
    START(["User presses Play"]) --> C1{"Already resolved<br/>this session?"}

    C1 -->|yes| OPEN1["Open the player immediately — no wait at all"]
    OPEN1 --> ST{"refresh required?"}
    ST -->|yes| REV["Quietly re-discover in the background,<br/>while the user is already watching"]
    ST -->|no| D1([done])
    REV --> D1

    C1 -->|no| C2{"Do we know which sources<br/>exist, from an earlier run?"}

    C2 -->|yes| FAST["Resolve the first source"]
    FAST --> F2{"worked?"}
    F2 -->|yes| OPEN2["Start playing on it,<br/>fill in the rest in the background"]
    F2 -->|no| FULL
    OPEN2 --> D2([done])

    C2 -->|no| FULL["Ask every enabled source provider<br/>what it has for this item"]
    FULL --> REC["Remember which sources exist — kept across restarts"]
    REC --> RES["Resolve <b>all</b> of them, in parallel"]
    RES --> CAP["Drop anything this device cannot play"]
    CAP --> E{"anything left?"}
    E -->|no| SAY["Say so plainly, on the screen<br/>the user is already on"]
    E -->|yes| ORD["Order by the user's subtitle preference"]
    ORD --> PLAY["Open the player on the first"]
```

### Play overlay

Pressing Play is **one action**. A titled page that exists only to hold a spinner turns it
into two: somewhere the back button can land, and something that flashes past on a fast
connection. It also has nothing to show — the item is already on screen behind it. So the
wait is an overlay over what the user was already looking at, and backing out of it is
treated as a change of mind, not as a request to be dropped into a player once the network
finally answers.

### Source resolution before playback

```mermaid
flowchart LR
    A["All sources resolved up front"] --> B["Switching source inside the player is instant —<br/>the picker moved <i>into</i> the player"]
    A --> C["'Nothing playable' is discovered while the user<br/>is still somewhere that can say so"]
    A --> D["Play stays one action"]
    A -.->|the cost| E["A slow source delays a fast one"]
```

The trade is accepted knowingly: with a handful of sources per item it buys more than it
costs.

### Honest capability handling

An unplayable stream produces an explicit message, never an endless spinner. Capability is
listed **positively** per platform, so a newly-encountered format or protection scheme is
never silently assumed playable — it is dropped, and if nothing survives, the user is told.

## 4.8 Watching

```mermaid
stateDiagram-v2
    [*] --> Playing: opens on the best available source
    Playing --> Playing: change quality
    Playing --> Playing: change or load subtitles
    Playing --> Switching: change source
    Switching --> Playing: instant — already resolved
    Playing --> Playing: position saved periodically
    Playing --> UpNext: nearing the end of an episode
    UpNext --> Playing: continue to the next one
    UpNext --> [*]: dismissed
    Playing --> Error: playback fails
    Error --> Playing: retry, or pick another source
    Playing --> [*]: back
    note right of Error
        Never auto-advances on error.
        Live streams report spurious errors,
        and auto-advancing skips good sources.
    end note
```

| Behaviour | Reason |
|---|---|
| The source picker lives in the player | Everything is pre-resolved, so switching is instant. Standing between the viewer and playback would waste that. |
| Quality options collapse to one row per resolution | The choice offered is "which resolution", not "which encode". |
| Continuing an episode replaces the player rather than stacking one | A binge session leaves one screen to back out of, not twenty. |
| Progress is saved periodically | Force-quitting loses seconds, not the session. |
| A position very near the start or the end does not resume | Resuming three seconds in reads as "start over"; resuming past the last frame is a trap. |

## 4.9 Coming back

```mermaid
flowchart LR
    subgraph L["Library"]
        F["Favourites"]
        H["History"]
        CW["Continue watching"]
    end

    U(["User"]) --> L
    L --> ITEM["Open an item and pick up where they left off"]
    L -.-> UNAVAIL["An item whose extension is gone<br/>stays listed, dimmed and marked unavailable"]
```

The library is application-owned state. Removing an extension does not delete its history;
affected records remain marked as unavailable.

## 4.10 Managing extensions

```mermaid
flowchart TB
    AD["Addons screen"] --> E1["Per-extension switch"]
    AD --> E2["Per-provider switch — e.g. one source off, the rest on"]
    AD --> E3["Index URL, check for updates, install"]

    E1 --> EFF["Turning an extension off empties whatever it contributed,<br/>immediately, on whatever screen is showing"]
    E2 --> EFF2["Turning one source off removes it from every future<br/>source list, without touching the rest of the extension"]
```

Extension-level and provider-level switches are **independent**: an extension can stay on
with one of its sources disabled. Enabling it again restores the previous configuration.
The disabled state is stored by id and retained across updates.

The index URL is retained across launches. If it is available, the app checks it in the
background at startup, so each installed extension card can show `Up to date` or an `Update`
action before the user opens the repository section.

## 4.11 What the user never has to think about

| Hidden work | Effect they notice |
|---|---|
| Session caching of catalog responses | Switching category is instant |
| Persisting which sources exist for an item | A cold start goes straight to playing |
| Background re-discovery after a cached hit | Links stay fresh without a wait |
| Per-provider failure tolerance | One broken upstream never empties a screen |
| Capability filtering before the player opens | No player that opens onto a dead stream |
| Ordering sources by subtitle preference | The first source played is usually the readable one |
