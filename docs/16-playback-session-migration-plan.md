# 16. Playback Session Migration Plan

This plan migrates playback ownership incrementally. Each phase keeps the
existing user journey intact and must leave the worktree in a testable state.

## 16.1 Success criteria

The migration is complete when:

- source discovery and resolution have no UI or navigation dependency;
- one route-independent playback session owns the active native controller;
- `PlayerPage` renders the session and forwards user intent instead of owning the
  complete playback workflow;
- fullscreen, mini-player, and native PiP observe the same session;
- late discovery, fallback, fresh signed-URL resolution, subtitles, quality,
  progress, and episode behavior remain unchanged;
- source switching and renewal can replace a native controller without losing
  the logical session;
- tests cover session transitions and stale asynchronous work;
- fresh physical iOS validation confirms playback, mini-player, and PiP behavior.

## 16.2 Phase 0 — Freeze the contract

Document and test the ownership contract before moving behavior.

Scope:

- add the architecture document in `docs/15-playback-session-architecture.md`;
- identify the current source, controller, presentation, and UI responsibilities;
- write characterization tests for the existing startup, late-source, fallback,
  retry, source-switch, and PiP transitions;
- preserve the existing persistent overlay and native surface key behavior;
- capture the minimal refactor baseline from
  [Playback Performance Plan §17.3](17-playback-performance-plan.md#173-prerequisites-before-implementation)
  before Phase 1; full thermal experiments are required only for relevant claims;
- characterize the discrepancy between current post-renewal automatic source
  fallback and documented post-start retry/user-selection behavior. Settle the
  intended contract before migrating recovery, without silently changing policy.

Exit criteria:

- current behavior is captured by tests or an explicit device-validation list;
- the tested build, affected behavior, available startup/resource observations,
  and native smoke-test sequence are recorded; unavailable measurements and
  physical validation stay pending without blocking unrelated pure extraction;
- no production behavior changes are needed to complete this phase.

## 16.3 Phase 1 — Extract the source resolver

Create an injected source-resolution service from the non-UI portions of
`workflow/play_item.dart`.

Scope:

- move discovery, cache reads/writes, provider filtering, fan-out, resolution,
  bounded waits, and partial-result streaming behind a service contract;
- keep `playItemV2` as a thin orchestration entry point temporarily;
- keep `_PlayerLaunchPage` and route handoff behavior unchanged;
- preserve descriptor persistence and the single secure last-used VOD resume
  record; keep resolved alternatives in the active player only, with live bypass
  and enabled-provider filtering;
- add request identity/cancellation guards so an old resolution cannot publish to
  a newer playback attempt.

The pending play workflow owns each initial request and transfers its remaining
result subscription to the accepted session once. Test Back before resolution,
Back during handoff, immediate/late results, repeated Play, and shared discovery
with one consumer cancelled. Keep current fast/full discovery separation. A
subscription cancellation must not be represented as a proven transport abort.

Do not:

- move snackbar, route, overlay, or `BuildContext` logic into the service;
- change source ordering or live/VOD policy;
- add a second resolver path for the mini-player.

Exit criteria:

- resolver unit tests cover cached descriptors, fresh resolution, provider
  failure isolation, partial results, empty results, timeout, and stale requests;
- `play_item.dart` no longer contains the implementation of provider fan-out;
- existing player workflow tests pass unchanged or with only seam updates.

## 16.4 Phase 2 — Extract the playback session

Create the route-independent owner for one active playback in two reviewable
steps. Both steps retain the current overlay and rendering backend.

### Phase 2a — Move native lifecycle at its actual owner

`VideoPlayerView` currently creates, initializes, replaces, and disposes the
native controller. `PlayerPage` only receives its adapter. Extract a focused
lifecycle adapter from the view before claiming session ownership:

- introduce the minimal route-independent session owner for this handle first;
  retain page policy temporarily through explicit commands/subscriptions until
  Phase 2b, without creating a second disposal owner;
- inject a factory that creates a handle with playback commands, observations,
  and a surface binding; preserve `AppPlayerController` commands;
- move open/configuration, native event binding, variant replacement, and
  asynchronous disposal out of widget lifecycle;
- let session ownership authorize create/open/replace/dispose, while the adapter
  executes native work and the surface borrows its handle;
- make replacement transactional: reject stale completions, clean up failed
  candidates, preserve valid state, and dispose superseded resources once;
- allow measured temporary controller overlap for candidate preparation; avoid
  duplicate steady playback and release both paths correctly on close;
- evolve the injected player builder into factory plus surface test seams through
  a temporary compatibility adapter. Inventory app, preview, and fake-player
  callers so each intermediate change compiles without native widget tests.

Exit criteria: fake lifecycle tests verify open failure, close during open,
replacement failure, stale completion, and exactly-once cleanup. Native resources
have one lifecycle owner; disposing a presentation widget alone cannot dispose
active playback. Keep previews explicitly owned by their own preview lifetime.

### Phase 2b — Move playback policy and state

Scope:

- move source list, active source, playback event handling, position tracking,
  retry, renewal, and source-switch policy out of `PlayerPage`;
- implement `PlaybackSessionCubit` with immutable state, injected dependencies,
  and active-playback scope; consume native observations through narrow listeners;
- expose intent-based commands such as `retry`, `selectSource`, `renewSource`,
  `seek`, `togglePlayback`, and `close`;
- use the native lifecycle adapter and updated test seams from Phase 2a;
- keep progress persistence and external subtitle lookup as collaborators unless
  extraction proves they belong in the session;
- model stale attempts explicitly so disposed sessions cannot receive callbacks.

Important policy boundaries:

- before playback initializes, a failed source may fall back to another usable
  source;
- after playback has started, do not silently auto-advance;
- fresh resolution is required for signed/tokenized retry;
- source replacement may recreate the native controller while preserving the
  logical session.

Exit criteria:

- session tests cover initial state, ready, buffering, playback error, retry,
  pre-start fallback, post-start failure, source switch, renewal, completion,
  disposal, and stale callbacks;
- `PlayerPage` has no native lifecycle authority or source-recovery timers;
- no native surface is recreated because of position/buffering/control ticks.

### Recovery contract gate

Document 13's target is pre-start fallback, bounded same-source recovery where
supported, and explicit retry/source selection after terminal post-start failure.
Never advance to another episode because of an error. The current
`_fallBackAfterFailedRenewal` automatic alternative-source switch conflicts with
that target. Before Phase 2b recovery extraction, record the disposition in its
work item: preserve current behavior for a characterized extraction and schedule
the policy correction separately, or land an explicitly scoped correction first.
Do not use a new session abstraction to silently remove or expand fallback.
Until resolved, unaffected resolver/lifecycle work can proceed; recovery migration
cannot be marked complete. An alternative product policy requires an explicit
decision and updates to the governing behavior docs/tests.

## 16.5 Phase 3 — Extract the player surface

Make the native rendering boundary explicit without changing its backend.

Scope:

- define a surface that consumes the session's current native player handle;
- preserve the persistent `_videoSurface`/platform-view identity strategy;
- keep viewport, fit, aspect ratio, clipping, and hit testing in the surface;
- keep custom controls outside the high-frequency native surface subtree;
- ensure surface replacement occurs only for a new controller/source variant.

Exit criteria:

- widget tests use a fake surface/player builder;
- structural surface identity is stable across playback ticks and presentation
  mode changes;
- source replacement is the only expected path that changes native surface
  identity.

## 16.6 Phase 4 — Extract presentation ownership

Evolve the current `MiniPlayerSession`/PiP host into an explicitly named
presentation coordinator while preserving its overlay mechanics.

Scope:

- move fullscreen/mini mode, drag state, dock, route ordering, and interaction
  gating behind presentation state;
- keep the surface mounted in the persistent overlay where required by native
  platform-view behavior;
- connect native PiP callbacks to the same playback session;
- keep PiP close and player close as explicit lifecycle events;
- make `video_player_mini_player` consume only generic presentation/surface
  contracts.

Do not:

- make the mini-player call source discovery;
- create a second native controller for mini mode;
- pop or dispose the player route before native PiP has taken ownership;
- assume Flutter controls/subtitles are available in the OS PiP window.

Exit criteria:

- presentation tests cover full → dragging → mini → full, dock changes,
  interaction blocking, route pushes, and close;
- iOS validation confirms inline playback → PiP → restore without audio restart,
  position loss, or native surface flicker;
- Android/macOS behavior remains unchanged where PiP is unsupported or different.

## 16.7 Phase 5 — Thin `PlayerPage` and cleanup

Reduce `PlayerPage` to a route/view composition layer.

Target responsibilities:

- compose surface, controls, overlays, and episode UI;
- listen to session state;
- forward user intent;
- trigger navigation and one-off UI effects from explicit callbacks;
- provide the route's accessibility and keyboard bindings.

Remove from the page:

- source discovery and provider fan-out;
- source cache mutation;
- controller lifecycle delegation and page-owned playback subscriptions (native
  construction/disposal is extracted from `VideoPlayerView` in Phase 2a);
- source renewal/fallback policy;
- long-lived playback timers and event subscriptions.

Exit criteria:

- the page is below the repository's 500-line class limit;
- `dart run tool/check_class_length.dart` passes;
- app analyzer, player tests, and full app tests pass;
- `git diff --check` passes;
- no unrelated generated or user-owned worktree change is staged.

## 16.8 Validation matrix

| Scenario | Required result |
|---|---|
| First source resolves | Player opens without a second loading route |
| Late source resolves | Picker receives it; current playback remains untouched |
| First source fails before initialization | Another usable source may start automatically |
| Source fails after playback starts | Retry/source selection remains available; no silent advance |
| Signed URL expires | Fresh resolution occurs; stale URL is not replayed |
| Fullscreen to mini | Same session and native player continue |
| Mini to fullscreen | Position, audio, subtitle, and quality state remain |
| Inline to native PiP | Native playback continues through handoff |
| PiP restore | Same logical session and surface resume inline |
| PiP close | Player pauses/disposes only after explicit close lifecycle |
| Back during PiP handoff | No premature route disposal |
| Detail/Home route push while mini | Player remains below the new route |
| Session disposal | Timers, subscriptions, overlay entry, and native resources release |
| Repeated Play taps | No duplicate playback workflow or player route |
| Back during initial resolve/handoff | No late session activation; shared consumers remain valid |
| Close/reopen VOD | Existing app-session cache reuse is preserved; fresh retry still re-resolves |
| Close during native open/replacement | No stale activation, leaked candidate, or double disposal |
| Presentation unmount while session remains active | Native player survives under the session owner |

## 16.9 Rollback boundaries

Each phase must be revertible without changing the extension protocol. If a phase
causes a device-only regression:

1. keep the resolver/session contract and tests if they are independently valid;
2. restore the previous adapter at the presentation boundary;
3. do not bypass native lifecycle or relax capability/security checks;
4. record the failing platform sequence and native logs before retrying;
5. continue only after the regression is reproducible or bounded by a test.

The persistent surface strategy is safety-critical. A refactor that preserves
logical state but recreates the native surface during ordinary playback ticks is
not a successful migration.

## 16.10 Deferred work

The following are intentionally outside this migration:

- casting or remote playback;
- background audio policy changes;
- multiple simultaneous full playback sessions;
- download/offline playback;
- extension protocol changes;
- replacement of the current native backend;
- broad package renaming unrelated to ownership or lifecycle.
