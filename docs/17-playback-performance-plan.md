# 17. Playback Performance and Watching Experience Plan

Status: proposed work; no performance improvement or thermal cause is proven yet.

First work item: D0 in §17.7. Diagnose the reported heat/freeze before selecting
an optimization. Resolver limits, buffer settings, and quality tradeoffs remain
to be selected from the relevant baseline and experiment.

This plan covers slow startup, UI lag, video stutter, buffering, recovery,
heat, and battery use. Read it alongside [Playback Session Architecture](15-playback-session-architecture.md),
[Migration Plan](16-playback-session-migration-plan.md), and
[Issue Fix Workflow](13-issue-fix-workflow.md).

## 17.1 Outcome and scope

The viewer should start watching promptly, keep watching without interruptions,
use controls without lag, and move between fullscreen, mini-player, and PiP
without losing playback. Long viewing sessions should avoid unnecessary work and
resource accumulation.

Architecture extraction makes ownership easier to test. It does not by itself
reduce decoding cost, improve upstream delivery, or guarantee a cooler device.
Measure architecture changes and performance changes separately. A focused,
proven performance fix need not wait for the full session migration.

Work starts with the reported phone and source. Physical iOS is the first native
validation target given the current playback/PiP work; confirm the affected device
when capturing the report. Shared player changes also need Android/macOS checks.

## 17.2 Evidence currently available

The inspected checkout provides investigation leads, not a thermal diagnosis:

- `workflow/play_item.dart` starts resolutions in parallel and can continue
  discovery after initial playback. `_revalidate` already filters
  `excludeSourceKeys`; duplicate WebViews must be measured, not inferred from its
  explanatory comment. No new provider classification is assumed.
- `_resolveOne` uses a Future timeout. `_appendResolvedSources` cancels stream
  subscriptions. Neither observation establishes that underlying host requests,
  JavaScript work, or WebViews are aborted when a viewer closes playback.
- `widgets/video_player_view.dart` keeps a persistent `_videoSurface`, but the
  surrounding layout/subtitle builder still listens to player values. Its CPU
  or raster cost requires a trace before further extraction.
- Player health, stall detection, and progress use periodic sampling. The
  existence of timers alone does not establish excessive energy use.
- Native player and app files have concurrent worktree edits. Record the exact
  tested build and diff; older notes are not a stable performance baseline.

There is also a behavior discrepancy to resolve before recovery changes:
`PlayerPage._fallBackAfterFailedRenewal` currently can switch to an alternative
source after playback has started, while the numbered documents prescribe retry
or user source selection. Characterize current behavior and explicitly settle
the intended contract before that work item. Episode auto-advance and switching
providers for the same media are distinct actions; neither may change silently
as part of an optimization.

## 17.3 Prerequisites before implementation

These are engineering readiness gates for each work item. Baseline collection and
minimal diagnostic instrumentation may begin before the cause is known. A
production optimization requires the relevant gates below; an unavailable DRM
fixture, for example, blocks DRM claims rather than unrelated clear-video work.

Use three levels of evidence rather than requiring every measurement for every
edit:

| Work type | Required before starting | Required to finish/claim success |
|---|---|---|
| Behavior-preserving extraction | Exact build, ownership/behavior characterization, focused tests, available before observations and native smoke-test plan | Affected tests pass; native lifecycle changes receive device validation; no unmeasured thermal claim |
| Performance experiment | Reproduced symptom/trace, relevant baseline, primary metric, predeclared guardrails | Comparable runs support or reject the hypothesis; prototype result is not a release claim |
| Viewer-facing performance release | Validated candidate and relevant device/network scenarios | Required native checks, product target evaluation, rollback criteria, and traceable results |

The checklist below applies to performance tuning. Missing advanced GPU or thermal
measurements does not block a pure resolver extraction; it limits the performance
conclusions that can be made. Missing physical verification still prevents
declaring a native lifecycle change fully validated.

- [ ] Record device model/OS, app version, build mode, commit plus local diff,
  native dependency versions, and extension version/bundle hash.
- [ ] Identify media/source, live or VOD, codec/resolution/frame rate/bitrate when
  available, subtitle mode, and clear or protected playback. Missing data is
  recorded as unavailable rather than guessed.
- [ ] Describe the user-visible failure and timing: before first frame, stable
  playback, seeking, controls, transition, renewal, or after close.
- [ ] Capture a repeatable failing case or concrete production trace and a
  known-good comparison. Separate upstream availability from app behavior.
- [ ] Collect comparable baseline runs using the protocol below, with metrics
  supported by the device and tools.
- [ ] Name the suspected cause, owning layer, proposed change, and a test or
  experiment that can disprove the hypothesis.
- [ ] Set the primary metric, acceptable regression margins, and rollback
  condition before comparing the candidate. Populate numbers from the baseline;
  do not invent universal buffer, timeout, concurrency, or temperature targets.
- [ ] Resolve behavior conflicts relevant to the work item, including recovery,
  source priority, quality preference, and live latency expectations.
- [ ] Preserve concurrent edits and retain a reproducible baseline artifact or
  isolated checkout. Never discard user work to obtain a clean baseline.
- [ ] Identify focused regression tests and physical-device verification needed
  for the affected native path.

## 17.4 Measurement protocol

Use a physical device in profile mode for Flutter performance investigation and
a comparable release build for viewer-facing confirmation. Debug-mode timings
are diagnostic only; Flutter recommends physical devices and profile mode for
performance analysis. Record instrumentation overhead and compare runs with the
same instrumentation settings. [Flutter performance profiling](https://docs.flutter.dev/perf/ui-performance)

Keep device, OS, brightness, display refresh setting, network conditions,
charging state, power mode, case, and starting thermal state comparable. Allow
the device to return to a comparable starting state between thermal runs.
Record ambient conditions where practical. Use the same media and rendition for
renderer comparisons; quality/ABR experiments deliberately vary rendition and
must report that difference.

Use both a controlled playable fixture and the affected real provider. The fixture
isolates the app/backend; production confirms the extension, signed URLs, headers,
redirects, and actual delivery path. Re-resolve signed URLs when needed rather
than treating an expired URL as a benchmark asset. Record real-provider variance.

Suggested initial run protocol, not a shipped performance target:

1. Run at least three comparable baseline and candidate runs per selected case;
   alternate their order to reduce thermal/network bias.
2. Separate cold launch/cache-miss, warm descriptor-cache, and warm resolved-cache
   startup. Preserve the existing live cache policy.
3. Match run length to the hypothesis. Startup experiments finish after stable
   playback and initial background work are observed; UI experiments repeat the
   affected interaction. Thermal/steady-playback experiments observe the first
   two minutes and at least 15 minutes of playback, extended to the reported
   failure duration when needed. A 15-minute run is not a prerequisite for every
   source extraction or controls edit.
4. Exercise pause/resume, repeated seeks, controls/sheets, source/quality switch,
   fullscreen/mini, supported PiP enter/restore/close, and close/reopen.
5. Observe resource release after close and repeat the lifecycle enough times to
   detect accumulation. Pausing and closing are separate scenarios.
6. Repeat selected cases with controlled bandwidth limits, latency, short outages,
   and network recovery; record the impairment rather than calling it "slow Wi-Fi".

For small samples report individual results, median, range, and sample count.
Use percentiles only with enough observations to support them. Do not claim a
reliable p95 from three playback runs.

## 17.5 Metrics and interpretation

| Viewer concern | Metric | Interpretation guard |
|---|---|---|
| Waiting after Play | Tap-to-first-visible-frame; discovery, resolve, native initialize, and render stages | Resolve success, buffered bytes, and controller initialization are not first-frame proof; label proxies |
| Repeated buffering | Stall count, total and longest stall duration; rebuffer ratio | Count involuntary post-start interruptions; exclude user pauses and classify seek/renewal waits separately |
| Slow recovery | Failure-to-resumed-playback time, attempts, success/failure, abandoned sessions | Failed starts and terminal errors remain in results, not only successful sessions |
| Laggy controls/drag | Input response and UI/raster frame time against the device frame budget | Flutter frame timing is not native video frame timing |
| Video stutter | Native dropped/late frames where exposed, visible freezes, audio/video sync | Distinguish low source frame rate, network starvation, and rendering/decoding stalls |
| Seeking/switching | Intent-to-visible-target-frame time, position error, audio/subtitle continuity | Account for live window and rendition/keyframe behavior |
| Heat and battery | CPU/GPU activity, energy estimates, thermal-state changes, longer-run battery trend | Thermal state is not a Celsius reading; battery percentages are coarse and profiler results are tool-specific |
| Resource waste | Native controller count, resolver/WebView work, network bytes, memory and release time | Include owned web/native processes where visible; retained caches differ from leaked active players |
| Live viewing | Distance from seekable edge; end-to-end latency only when source timestamps support it | A seekable-window offset does not prove broadcast-to-screen latency |
| Quality | Actual rendition/bitrate, quality changes, selected cap/manual preference | Lower energy from lower quality is a tradeoff, not an equal-quality performance win |

Define rebuffer ratio as involuntary post-start stall wall time divided by wall
time spent advancing playback plus those stalls. Never use media-position deltas
as the denominator: seeks and non-1x speed would distort it. Keep pause,
seek, source-switch, renewal, and PiP
handoff durations in separate categories; also report their total visible
interruption cost so moving a wait between categories cannot hide it.

UI/raster traces can be inspected with the Flutter Performance view. Use native
instrumentation for the video/backend work it cannot attribute.
[Flutter DevTools Performance view](https://docs.flutter.dev/tools/devtools/performance)

### Measurement availability before adding instrumentation

This inventory describes code paths to verify in the exact test build, not
measurements already collected. Debug-only logs need an opt-in, bounded diagnostic
equivalent for a profile experiment; do not enable verbose production logging.

| Signal | Existing starting point | Gap and collection action |
|---|---|---|
| Discovery/resolve elapsed time | `play_item.dart` stage logs and timeouts | Correlate pending request, source, and attempt; capture counts in the profiled build |
| Position, buffering, ranges | `AppPlayerValue`, underlying `VideoPlayerValue`, playback health samples | No proof of fresh displayed frames; collect contiguous buffer and native waiting context |
| UI/raster timing | Flutter profiling tools | Record the exact gesture/control interval; avoid profiling overlays during final energy comparison |
| Native controllers | `VideoPlayerView` create/open/replace/dispose sites, platform lifecycle | Add bounded lifecycle IDs/counters if not exposed; distinguish preview, active, and prepared candidate |
| Resolver/WebView work | Workflow/host/browser start, settle, cancel, cleanup boundaries | Trace actual work and owning consumers; workflow future count is not WebView count |
| Fresh video frames | Native rendering path plus visible playback | Verify any existing native diagnostic fields first; add timestamps/counters only for the affected path, or use a timed visual observation labelled as such |
| Thermal/CPU/GPU/energy | Device/native profiler facilities available on the test host | Record tool, process coverage, sampling, and unsupported signals; no inferred Celsius value |
| Active rendition | Track selection and native player metadata | Verify actual selected bitrate/resolution; a requested cap is not proof it was applied |

Before edits, inventory current thresholds and their callers, including discovery
and resolve timeouts, first-source/subtitle grace, startup health timeout, stall
sampling, renewal limits, and native live options. Record their values from the
tested revision in the work item. This avoids tuning a stale default or changing
two different timeout layers without knowing it.

### Product targets and engineering parameters

Track absolute viewing targets separately from improvement over the baseline.
Reducing startup from 20 to 18 seconds could pass a relative-improvement test
while still missing the viewing target. Parameters such as buffer duration,
concurrency, and grace periods are experimental inputs, not user-experience goals.

Populate the numeric target and acceptance statistic after D0, before production
tuning for that scenario. An unset target permits diagnosis but not a claim that
the viewing goal has been achieved. These are project targets, not industry-wide
guarantees; account for source/network conditions explicitly.

| Viewing goal / cohort | Absolute target to record | Guardrail |
|---|---|---|
| VOD, descriptor cache miss | Play-to-first-frame budget and startup success rate | Priority and fallback availability |
| VOD, warm descriptor cache | Separate first-frame budget | Fresh resolve correctness |
| VOD, reusable resolved cache | Separate first-frame budget | Enabled sources and freshness policy |
| Live, fresh discovery/resolve | First-frame budget plus live-edge distance budget | Avoid excessive latency or loss of fastest usable source |
| Stable playback, per network profile | Maximum stall count, longest stall and rebuffer ratio | Quality and total visible interruption time |
| Controls, seek and presentation changes | Input/target-frame response budget and continuity requirement | No controller recreation solely for mode changes |
| Longer viewing at fixed rendition | Thermal/energy objective and resource-release deadline | Same quality, playback duration, and controlled conditions |

Record baseline, target, allowed regression, actual result, sample size, and
pass/fail/pending for the selected cohort. Report "improved, target unmet" when
appropriate. Broader rollout can require more samples than the initial experiment.

## 17.6 Symptom-to-investigation routing

| Observed symptom | Evidence to inspect first | Candidate response if confirmed |
|---|---|---|
| Long wait before source exists | Discovery/resolve stages, queue depth, provider failures | Deduplicate requests; tune bounded scheduling and optional work |
| Source resolves fast but first frame is late | Manifest/segment delivery, license request, native initialize/render | Fix the slow stage and preserve stream configuration |
| Buffer empty and segment delivery slow | Request status/timing, throughput relative to active bitrate | ABR/load-control investigation or provider fix |
| Buffer available but picture freezes | Contiguous buffer at current position, native frame/decoder and GPU traces | Investigate native pipeline; do not assume signed URL expiry |
| Controls stutter while video progresses | Dart/UI/raster trace and background work | Isolate measured rebuild/layout/processing hotspots |
| Stall follows a seek or LIVE action | Target, seekable window, overlapping seeks, buffer invalidation | Coalesce obsolete seeks and validate live target behavior |
| Heat persists after closing | Active controllers, web tasks, subscriptions, timers, network | Repair lifecycle/cancellation at the actual owner |

Use the contiguous buffered range containing the current playhead when measuring
forward cushion. The furthest buffered endpoint can overstate usable media if
there is a gap. Native buffering flags need context: AVPlayer exposes a waiting
state, but that alone does not identify a broken or expired source.
[Apple AVPlayer timeControlStatus](https://developer.apple.com/documentation/avfoundation/avplayer/timecontrolstatus-swift.property)

## 17.7 Optimization workstreams

### D0 — First diagnosis: reported heat, lag, or frozen picture

This is the immediate priority. The P1/P2 groups below classify candidate changes;
they do not postpone thermal diagnosis or require implementing every group.

1. Identify the exact reported device/build, media/source, rendition, subtitle
   state, and whether the issue is startup-only or persists after discovery.
   Retain an artifact/diff so concurrent native edits cannot change the baseline.
2. Reproduce the symptom unchanged. Capture a timeline from Play through first
   frame, active discovery, steady playback, and close. Correlate errors to the
   active source before treating alternative-provider errors as playback failures.
3. Inventory available signals in §17.5. Add only missing diagnostics needed to
   distinguish resolver activity, native rendering, and UI work. The first
   deliverable is a trace plus gaps, not a new scheduler or buffer configuration.
4. Compare the same run while alternatives resolve and after they settle, tracking
   thermal lag and changing playback conditions. This correlation is not yet
   causal proof. If needed, use a controlled experiment that suppresses only
   additional background alternatives after initial selection. Keep source,
   rendition, headers and playback path equivalent; this experiment is not a
   shipped fallback policy. Record fallback unavailability in that run.
5. If audio or playback position advances while the picture freezes, inspect
   fresh-frame evidence and native rendering before changing network buffers.
   If contiguous buffer drains, inspect actual playlist/segment delivery and
   bitrate instead. Use the controlled fixture to help separate upstream issues.
6. Check active/prepared/preview controllers and outstanding work after close;
   record normal bounded cleanup separately from accumulating resources.
7. Produce one work item with a supported hypothesis, target cohort, primary
   metric, absolute target, regression margins, and next smallest experiment.
   If evidence is inconclusive, state the next missing signal rather than selecting
   a speculative production fix.

Exit: a reproducible report, baseline observations, instrumentation gaps, and one
ranked next action. Diagnosis can finish with an inconclusive cause; optimization
success requires subsequent evidence. UI or thermal work becomes P1 if this
diagnosis identifies it as the primary viewer-impacting problem.

### P1 — Resource lifecycle and background resolution

Measure peak and steady-state resolver work before choosing a concurrency limit.
Investigate sharing identical in-flight resolves using extension/media/source
identity and request generation, while respecting fresh-resolution intent and
provider enablement changes. Preserve existing exclusion filtering.

Give active playback recovery precedence over speculative alternatives where the
measured scheduler supports it. Compare limits against first-frame time, provider
priority, live fastest-source selection, and availability of late fallbacks.
Avoid provider-specific rules in the shell or new extension capabilities merely
to label a resolver as expensive.

Trace cancellation through workflow, host, transport, and browser work. Separate
"result ignored", "queued work removed", and "underlying operation aborted".
Where abort is unsupported, document the bounded remaining work and its cleanup.
Do not destroy the shared extension engine to cancel one role call.

Keep one active full-playback controller during steady playback and presentation
changes. An intentional replacement may temporarily prepare a second controller;
measure its overlap and verify cleanup on success and failure. Inspect hidden
previews independently. Verify resource release after close without terminating
the session merely because it enters mini-player or PiP.

### P1 — Faster time to watch

Break startup into stages before shortening any wait. Preserve fast playback on
a usable source and progressive alternatives. Audit optional metadata, subtitle
grace, duplicate track inspection, and repeated initialization if they dominate
the trace. Subtitle errors must release playback; selected subtitles must remain
available and correctly applied when the work finishes.

Cached descriptors and app-session-only resolved streams retain their existing
policies, including eligible VOD reuse across playback close/reopen.
Readiness must be based on playback evidence; hiding a loading surface earlier
does not constitute a faster first frame.

### P1 — Fewer stalls and bounded recovery

Measure stream delivery through final playlists and segments, including headers,
redirects, DRM requirements, and signed-URL lifetime. Provider defects belong in
extensions; native decode/load-control defects belong in their player adapter.

Test VOD and live separately. Compare startup buffer, rebuffer threshold,
read-ahead, memory/network use, and live-edge distance as a group. A larger buffer
can trade startup/latency/resources for resilience; do not prescribe a universal
duration or disable native waiting behavior without an experiment.

For adaptive streams, verify the native adaptive selection and actual rendition
before adding quality policy. Preserve explicit quality preferences. Fixed-URL
renditions need separate switching measurements; do not treat them as native ABR.
Any automatic quality reduction beyond existing behavior needs a documented
product decision and a measured quality/stall tradeoff.

Recovery must distinguish transport failure, delivery starvation, genuine native
stall, expired authorization, seek, intentional pause, and end of content.
Use existing signals plus focused diagnostics; no universal expiry diagnosis
from a frozen position. Keep one recovery attempt in flight with a bounded
attempt/time budget, stale-result protection, and an actionable terminal state.
Define those budgets from evidence before implementation. Preserve valid VOD
position and an appropriate live target; never restart another episode on error.

### P2 — Responsive controls and smooth video presentation

Use traces to isolate structural layout, captions, progress, and controls.
Keep the native surface stable; select only relevant state for expensive UI.
If measured, avoid reparsing unchanged subtitle text on each position tick and
avoid expensive work for hidden controls while keeping captions/progress correct.

Profile drag, sheets, fit, and mini-player compositing before adding render layers,
changing clipping, or switching texture/platform-view paths. Preserve protected
playback and PiP support. Coalesce obsolete seek intents where safe, and test
rapid scrubbing, release, pause, and live-edge behavior; do not issue repeated
native seeks just to animate the thumb.

### Evidence-ranked — Heat and energy during longer viewing

Compare startup/background activity with steady playback at the same rendition.
Inspect CPU/GPU and decoder evidence before blaming codec or Flutter structure.
Measure diagnostic overhead, polling, redundant native calls, background previews,
and tasks retained after disposal. Do not remove stall detection or progress saves
merely because they use timers.

Power mode or temperature-based quality changes are deferred product decisions.
Playback and user preferences must not change silently to produce a lower thermal
reading. Platform-specific buffer/decoder behavior requires current official API
documentation and physical verification before configuration changes.

## 17.8 Watching-experience guardrails

- Keep first-source startup and late-source fallback usable. A lower resolver
  count is not a success if viewers wait longer or lose working alternatives.
- Pre-start fallback remains within the active play flow with one neutral loading
  indication. Do not return to Detail or stack another loading route.
- Preserve retry, source selection, and Back/close during recoverable failures;
  avoid infinite spinners, repeated error overlays, and uncontrolled retry loops.
- Preserve position, audio, subtitles, quality, and speed across presentation
  transitions. Keep subtitle selection/rendering checks in acceptance evidence.
- Preserve protocol headers, DRM, supported audio behavior, and live/VOD state.
  No TLS bypass, relaxed host allowlist, or secondary decoder fallback.
- Changes to controls follow semantic labels, focus, contrast, text scaling, and
  touch-target requirements in the app engineering guidelines.

## 17.9 Execution and release gates

| Stage | Deliverable | Exit condition |
|---|---|---|
| O0 — Baseline | D0 reproduction, exact build, traces/gaps, metric table, behavior conflicts | Relevant tuning prerequisites satisfied; primary metric, absolute viewing target, and margins filled |
| O1 — Cause | Focused experiment/fixture and ownership diagnosis | Evidence supports the proposed fix or rejects the hypothesis |
| O2 — Candidate | Small independently reviewable change and regression tests | Targeted checks pass; no bundled unrelated behavior change |
| O3 — Comparison | Repeated baseline/candidate measurements | Improvement exceeds observed noise; absolute target outcome and guardrails reported |
| O4 — Integration | Affected-package checks and physical playback evidence | No lifecycle/UX regression; findings and limitations recorded |

Capture the minimal extraction baseline from §17.3 before migration Phase 1.
Complete O0 for a performance tuning work item; it is not a prerequisite to every
behavior-preserving extraction. Repeat affected checks after ownership changes.
Refactor acceptance requires preserved behavior and regression margins, not an
artificial promise of faster playback from moving code. A local optimization can
proceed independently when its owner and measurement are clear. Rebaseline after
concurrent native changes land; do not attribute their effects to a resolver refactor.

Run focused tests during iteration, then `flutter analyze` and `flutter test`
from `apps/app` for app changes. Run the corresponding checks in every affected
package; pure Dart packages use `dart analyze` and `dart test`. Native/interface
changes also require affected consumers to compile and applicable native tests.
Run `dart run tool/check_class_length.dart` and `git diff --check` when code changes.
Documentation-only updates require link/content and diff checks.

Headless tests establish deterministic behavior, not temperature, smooth native
playback, or upstream reliability. Physical validation must include the relevant
live/VOD, clear/protected, subtitle, network, and presentation paths. Missing
evidence is marked pending. A failed or unavailable provider remains visible in
the result set rather than being dropped from a success calculation.

Rollback the isolated candidate if startup, stalls, live latency, quality, memory,
energy, or lifecycle violates the predeclared margins. Restore only that candidate;
preserve unrelated changes and the failing trace. Do not roll out a thermal claim
based solely on fewer files, timers, rebuilds, or passing unit tests.

## 17.10 Work-item and measurement record

Copy this template for each concrete optimization. These fields are intentionally
unfilled until baseline collection; they are required before tuning production
behavior.

```text
Work item / owner / status:
Viewer symptom and reproduction:
Baseline commit + diff/artifact; candidate commit + diff/artifact:
Device / OS / app mode / native versions / extension bundle hash:
Media/source identity (redacted); rendition / codec / DRM / subtitles:
Network / brightness / charging / power mode / starting thermal state:
Run duration / repetitions / instrumentation / unavailable measurements:
Confirmed facts / hypothesis / disconfirming experiment:
Relevant behavior decision (recovery, quality, priority, live latency):
Primary metric / baseline variation / required improvement:
Viewing cohort / absolute product target / acceptance statistic:
Current timeout, buffer, grace, recovery settings (tested revision):
Guardrail metrics / allowed regression margins:
Candidate change / owning layer / cancellation or lifecycle implications:
Per-run results / median and range / failed starts / total interruption cost:
Absolute target outcome: met / improved but unmet / regressed / pending:
Quality and live-latency differences:
Tests / physical-device evidence / trace locations:
Rollback condition / outcome / remaining limitations:
```

Store only safe identifiers and redacted summaries in versioned evidence. Do not
commit signed URLs, cookies, request authorization, DRM keys, or subtitle-provider
credentials. Diagnostic events should use session/attempt/controller identifiers
and monotonic elapsed time where applicable, with bounded collection overhead.
## 17.11 Preview playback policy

Decorative trailer previews on Home and Detail are a separate workload from
full playback. Device baselines must identify whether a preview is active so
its decoder and buffer cost is not attributed to the main playback session.

Decorative previews:

- remain enabled by default, with a persisted Settings toggle;
- start only after the hero has remained active for 1 second;
- play muted for at most 20 seconds and do not loop;
- pause while scrolling, while their route is covered, and while a full or
  mini-player session is attached;
- do not affect Shorts, which is an explicit viewing surface rather than
  decorative autoplay.

The app cannot impose a preview resolution cap unless the source contract
provides selectable variants. Do not claim or synthesize a quality limit for a
single final trailer URL.
