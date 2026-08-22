# 13. Issue Fix Workflow

Use this workflow for every bug, regression, playback failure, incorrect UI
state, cache issue, or extension-host failure. The goal is to fix the cause
with evidence, not to make the symptom disappear temporarily.

## 13.1 Define the failure

Record the concrete symptom before changing code:

- user action, input, media item, source, platform, and expected result;
- actual result, including whether it is deterministic or intermittent;
- relevant logs, stack traces, timestamps, and safe/redacted source details;
- last known good behavior and the regression range when available.

Do not infer token expiry, network failure, native-player behavior, or an
upstream outage without evidence from the active request or player logs.

## 13.2 Evidence and uncertainty

Do not hallucinate causes, logs, API behavior, user intent, or validation
results. State what is known, what is inferred, and what remains unknown.

Do not overthink by exploring unrelated subsystems, adding speculative
defenses, or designing a broad replacement before the smallest relevant
evidence has been checked.

Ask the user for clarification when a missing fact or choice would materially
change the fix, such as the expected product behavior, the affected platform,
a missing reproducible case, or permission to change external state. Make a
reasonable, low-risk assumption only when it stays within the reported issue;
state that assumption in the handoff.

## 13.3 Reproduce and narrow scope

Reproduce the issue with the smallest reliable case. Identify which boundary
owns the failing behavior:

| Boundary | Investigate first |
|---|---|
| Widget or controller state | state transition, lifecycle, stale async result |
| Catalog or cache | persisted snapshot, refresh request, merge and invalidation |
| Extension host | manifest, permissions, role call, JSON contract, redirect |
| Playback | source resolution, headers, DRM, live state, native events |
| Storage | serialized record, schema, load/save and migration behavior |
| Upstream | final HTTP response, manifest shape, signed URL lifetime |

Keep the investigation in the owning layer. Do not introduce provider-specific
logic into the app shell to compensate for an extension or upstream failure.

## 13.4 Form and test the hypothesis

State the suspected cause in one sentence, then verify it with a focused test,
fixture, log, or inspection. Change only the minimum code necessary to test or
fix that hypothesis.

If the evidence disproves it, remove the exploratory change and continue from
the new evidence. Do not accumulate defensive branches around unproven causes.

## 13.5 Implement the root-cause fix

Make the fix at the lowest layer that owns the behavior. Preserve existing
contracts unless the contract itself is the defect.

- Use a Cubit/controller for async workflow and persistent state changes.
- Keep widgets focused on rendering and forwarding intent.
- Keep extension data and provider knowledge in extensions.
- Keep source discovery separate from fresh stream resolution.
- Preserve usable cached data during a recoverable refresh failure.
- Never auto-advance playback after an error; offer retry or source switching.

When a temporary workaround is unavoidable, meet every condition in
[App Engineering Guidelines §12.8](12-app-engineering-guidelines.md#128-fix-causes-not-symptoms),
make it observable in safe logs, and document its removal condition in a short
English comment.

## 13.6 Prove the fix

Add or update the narrowest regression coverage that would have failed before
the fix. Use the injected registry and player builder seams; widget tests must
not construct native playback views.

Run the smallest relevant checks during development, then broaden validation
to every affected package:

```sh
# Flutter app
cd apps/app
flutter analyze
flutter test

# Pure Dart package
cd packages/<affected-package>
dart analyze
dart test

# Workspace hygiene
git diff --check
```

Native playback, a real upstream, and device-specific behavior still require
manual verification. Report that boundary clearly; passing headless tests does
not prove a physical-device playback fix.

## 13.7 Handoff

Summarize the symptom, confirmed cause, code path changed, regression coverage,
validation run, and anything still requiring device or upstream verification.
Commit the focused fix only after validation passes. Do not push without the
user's confirmation.
