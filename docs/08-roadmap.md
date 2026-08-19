# Roadmap

The application already supports extension installation, browsing, search,
library state, source resolution, and playback. The next milestones focus on
safe distribution, failure recovery, and release readiness.

## P0 — Public extension safety

### Signed extension releases

The current SHA-256 check detects a corrupted or mismatched download, but the
hash is supplied by the same repository index as the bundle. It does not prove
who published the release.

- Sign release metadata and bundles with Ed25519.
- Store a publisher key or fingerprint with each installed repository.
- Show publisher identity and signature status before installation.
- Reject invalid signatures before evaluating JavaScript.
- Define a safe key-rotation process.

### Validate playback URLs

The host must validate URLs returned by an extension before handing them to a
native player.

- Accept only supported HTTP and HTTPS URLs.
- Reject local files, application intents, loopback addresses, and private
  network targets in production.
- Apply the same policy to media, subtitle, audio, and DRM-license URLs.
- Keep local-network access limited to development builds.

### Runtime containment

QuickJS already has memory, stack, execution-time, request-timeout, redirect,
and concurrency limits. Complete the containment model before running arbitrary
third-party bundles.

- Add an isolate-level termination backstop.
- Cap response body and decoded payload sizes.
- Add tests for repeated timeouts, allocation pressure, and pending promises.
- Ensure one failed extension cannot delay application startup.

### Compatibility metadata

Add minimum host and protocol versions to the manifest and repository entry.
An incompatible extension must be rejected with an actionable message before
download or evaluation.

## P0 — Extension release pipeline

Extension releases should be reproducible and require no manual edits to
generated files.

```text
tag → test → analyze → build → hash → sign → publish → update index
```

- Publish immutable, versioned artifacts from CI.
- Provide a stable HTTPS URL for `repo.json`.
- Maintain separate stable and development channels.
- Validate manifest, host permissions, bundle freshness, and SDK compatibility.
- Generate release notes from committed changes.

## P1 — Safe updates and recovery

- Keep the previously working extension version after an update.
- Allow rollback from Addons.
- Record versions that fail to load or repeatedly fail at runtime.
- Do not automatically reinstall a version already marked as broken.
- Show installed, available, and previous versions.
- Make automatic updates an explicit per-extension preference.

An update is considered successful only after its manifest parses, its bundle
passes verification, its runtime surface loads, and the installed record is
written successfully.

## P1 — Diagnostics

Add a local diagnostics screen for users and extension authors.

- Record extension, provider, role, time, and operation duration.
- Classify HTTP, TLS, timeout, blocked-host, protocol, DRM, and player errors.
- Show extension load failures detected during application startup.
- Allow logs to be copied or exported.
- Redact authorization headers, tokens, signed query values, and sensitive
  request bodies.
- Keep retention bounded by age and entry count.

Diagnostics must remain local unless the user explicitly exports them.

## P1 — Playback reliability

- Add end-to-end fixtures for HLS and DASH on supported platforms.
- Cover headers, redirects, subtitles, DRM, expired URLs, TLS failures, and
  source switching.
- Distinguish retrying the current media URL from resolving a fresh URL.
- Show which source failed and offer another source without switching silently.
- Use separate timeouts for source discovery, resolution, and player startup.
- Remember the last successful source preference without persisting resolved
  stream URLs.

Playback errors must never trigger an invisible source change.

## P2 — Persistent catalog and metadata cache

The current catalog cache is session-only. Add persistent caching with
stale-while-revalidate behavior.

- Persist catalog pages and metadata with bounded storage.
- Render cached data immediately while refreshing in the background.
- Indicate when cached data is shown because the network is unavailable.
- Invalidate extension-owned cache entries after update or uninstall.
- Provide retry controls per failed catalog instead of replacing the whole
  screen with one error state.

Library records remain durable user data and are not governed by cache expiry.

## P2 — Addons experience

- Configure a default trusted repository while retaining custom repository
  support.
- Show installed, update available, disabled, and broken states clearly.
- Explain why each requested host permission is needed.
- Display publisher fingerprint, signature status, and release channel.
- Add repair, rollback, and update-history actions.
- Separate local HTTP development repositories from public HTTPS repositories.

## P2 — Documentation maintenance

- Keep this roadmap aligned with shipped behavior.
- Maintain a protocol and SDK compatibility table.
- Document the complete extension release and rollback process.
- Move historical implementation notes out of the active plan.
- Update milestone status only after automated checks and the required device
  verification pass.

## Recommended order

1. Signed releases and playback URL validation.
2. Automated extension publishing.
3. Diagnostics and playback end-to-end coverage.
4. Update rollback.
5. Persistent catalog and metadata caching.
6. Addons and documentation polish.
