# 1. Architecture

## 1.1 Design constraints

Five rules shape every boundary in the system:

1. **Extension-first.** Content and provider-specific logic live in extensions. The
   application binary contains only shared models and behavior.
2. **One protocol, no privileged path.** Bundled and downloaded extensions use the same
   loading path.
   If a first-party extension cannot operate through the public API, the API is incomplete.
3. **JSON-only boundary.** Everything crossing the extension boundary is JSON-compatible.
   No domain object, no URI type, no date type, no enum crosses unserialized.
4. **Discovery is separate from resolution.** Listing sources is cheap and cacheable;
   resolving one produces a signed, short-lived URL that must never be treated as durable
   content data.
5. **Lazy boundaries.** Add a package or abstraction when an existing use case requires it.

## 1.2 Layers

```mermaid
flowchart TB
    subgraph L1["① Presentation — the shell"]
        direction LR
        SHELL["Navigation shell"]
        SCREENS["Browse · Search · Detail<br/>Library · Addons · Player"]
        CTRL["Controllers — settings, library,<br/>selection, install"]
        CACHE["Session caches"]
    end

    subgraph L2["② Extension host"]
        REG["Registry — install, route, enable/disable"]
        BIND["Catalog bindings"]
        WRAP["Extension wrapper — protocol ⇄ JS"]
        INST["Installer — fetch, verify, persist"]
        API["Host function dispatcher"]
    end

    subgraph L3["③ Contract — the shared core"]
        MODEL["Content model"]
        PROTO["Protocol types + manifest"]
        MATCH["Matcher"]
    end

    subgraph L4["④ Runtime"]
        ENGINE["Engine wrapper — eval, limits, fetch, allowlist"]
        NATIVE["Embedded JS engine (vendored, native)"]
    end

    subgraph L5["⑤ Extensions"]
        M["manifest.json"]
        B["bundle.js"]
    end

    subgraph L6["⑥ Persistence"]
        STORES["Key–value stores for app-owned state"]
    end

    L1 --> L2
    L1 --> L3
    L1 --> L6
    L2 --> L3
    L2 --> L4
    L4 --> L5
    L5 -->|"host-provided fetch"| NET([Upstream services])

    style L3 fill:#1f2933,stroke:#7b8794,color:#fff
    style L5 fill:#1f3d2b,stroke:#5ba97b,color:#fff
```

**Dependencies point downward.** The contract layer only uses value-type utilities. The
extension host has no UI framework dependency, which keeps routing, installation, and
protocol handling testable without a device. Types shared by the host and persistence layer
belong in the contract layer.

## 1.3 Responsibilities

| Layer | Owns | Never contains |
|---|---|---|
| **Presentation** | Navigation, screens, playback, user-facing state | Any knowledge of a specific upstream |
| **Extension host** | Which extensions exist, routing calls to them, install/verify | Content logic, UI |
| **Contract** | Content model, protocol types, matcher algorithm | Content or provider-specific behavior |
| **Runtime** | Executing untrusted JS under limits; the host function surface | Protocol semantics |
| **Extensions** | Catalogs, metadata, source discovery and resolution | Anything about the user |
| **Persistence** | Library, settings, installed extensions, caches | Any reading of extension-owned data — an extension's own cache is stored as an opaque blob under its id, never interpreted |

## 1.4 Package layout

```mermaid
graph BT
    APP["application"]
    HOST["extension host"]
    CORE["core — model · protocol · matcher"]
    RT["JS runtime"]
    STORE["storage"]
    EXT["extension bundles<br/><i>assets or downloads</i>"]

    HOST --> CORE
    HOST --> RT
    STORE --> CORE
    APP --> CORE
    APP --> HOST
    APP --> STORE
    APP -.->|loads at runtime| EXT

    classDef ui fill:#0b3d5c,stroke:#4a90d9,color:#fff
    classDef pure fill:#1f2933,stroke:#7b8794,color:#fff
    classDef ext fill:#1f3d2b,stroke:#5ba97b,color:#fff
    class APP,STORE ui
    class CORE,HOST,RT pure
    class EXT ext
```

| Package | UI framework? | Role |
|---|---|---|
| core | no | Content model, protocol types, manifest parsing, matcher. The contract everything shares. |
| extension host | no | Registry, routing, the protocol⇄JS wrapper, host functions, installer. |
| JS runtime | no (FFI) | The embedded engine: eval, resource limits, `fetch`, host-callback bridge. |
| storage | yes | Key–value persistence for app-owned state. |
| application | yes | Shell, screens, controllers, caches, player. |

The workspace resolves as a single unit — one dependency resolution, one lockfile — so a
change to the contract is compiled against every consumer at once.

## 1.5 Runtime topology

Everything runs on **one isolate/thread**. There is no worker thread and no separate JS
thread.

```mermaid
flowchart LR
    subgraph MAIN["Application isolate"]
        direction TB
        UI["UI + controllers"]
        REG["Registry"]
        WRAP["Extension wrapper"]
        ENG["Engine wrapper"]
        HTTP["HTTP client"]
    end

    subgraph NAT["Native, same thread (FFI)"]
        JSE["JS engine runtime + context"]
        JS["bundle.js"]
    end

    UI --> REG --> WRAP --> ENG
    ENG -->|eval / evalAsync| JSE
    JSE --> JS
    JS -->|host call — synchronous| ENG
    JS -->|fetch — asynchronous| ENG
    ENG --> HTTP
    HTTP -->|"future completes → resolve the JS promise"| JSE
```

Runtime behavior:

- **Asynchrony in JS is host asynchrony.** A `fetch` from JS becomes an ordinary host
  future, interleaved with synchronous native calls on the same isolate. The JS engine
  itself stays single-threaded.
- **Concurrent role calls are supported.** Several calls may be in flight; they interleave
  on one shared JS event loop, the way concurrent work in a browser does. A fan-out across
  providers needs **one engine instance**, not one per call.
- **One engine per extension.** Each installed extension gets its own engine, created with
  its own host allowlist. Extensions therefore cannot see each other's globals.
- **Scripts within one extension share global scope.** That is what lets a bundle carrying
  several providers coordinate — see
  [Extension Protocol §2.7](02-extension-protocol.md#27-one-bundle-many-providers).

## 1.6 Who decides what

```mermaid
flowchart TB
    subgraph APPOWNS["The shell decides"]
        A1["Navigation structure — fixed, app-owned"]
        A2["Grid column count, spacing, typography"]
        A3["Library: favourites, history, progress"]
        A4["Which extensions and providers are enabled"]
        A5["Whether a stream is playable on this platform"]
        A6["The matching <b>algorithm</b>"]
        A7["Caching and refresh policy"]
    end

    subgraph EXTOWNS["The extension decides"]
        E1["Which categories exist"]
        E2["Catalog contents, ordering, grouping"]
        E3["Subcategories, per response"]
        E4["Layout hint: row · grid · list"]
        E5["Which sources exist, and how to resolve one"]
        E6["The matching <b>profile</b> — aliases, stop tokens"]
        E7["Its own upstream protocols"]
    end

    A6 -.->|host function| E6
```

Matching a catalog item to a source must be consistent across extensions. The host provides
the algorithm, while extensions provide aliases and normalization rules as data.

## 1.7 Failure model

Failures are isolated to the smallest affected unit.

```mermaid
flowchart LR
    F1["A catalog fails"] --> R1["that shelf shows an error and a retry;<br/>the page does not blank"]
    F2["A search provider fails"] --> R2["it contributes nothing;<br/>other results still render"]
    F3["A source provider fails"] --> R3["the fan-out continues without it"]
    F4["One source will not resolve"] --> R4["that source is dropped"]
    F5["No source resolves"] --> R5["show an actionable error<br/>on the current screen"]
    F6["An extension will not load"] --> R6["it is skipped; the app still launches"]
```

A failure is contained to its own scope. Empty results are reported instead of leaving a
loading state active.

## 1.8 Non-goals

| Not built | Reason |
|---|---|
| A backend | Extensions execute on-device, so requests carry the user's own IP — required for IP-bound signed URLs and region-locked streams. A server route would break both. |
| A capability object layer (`stream` / `download` / `children`) | The current protocol has one active capability. Add the layer when another capability is implemented. |
| Realtime push (WebSocket/SSE) | No current feature requires it. |
| Content-specific types in the core | These types belong in extensions. |
