# 024 Archive Normalization And Canonical Local Models

Note as of April 16, 2026:
This lesson covers the normalization pass that happened before the runtime cutover. The next PR it talks about has now landed. Read `025_runtime_cutover_local_archive_first.md` for the live local-archive-first runtime.

## Why this lesson exists

This PR is about making the iOS app internally truthful before the later runtime cutover PR.

The important mental shift is:

- `AnkySessionBundle` is the canonical local session object.
- `LocalArchiveRecord` is the canonical local archive object.
- `CachedWritingEntry` is now a compatibility projection for existing UI.

That is the real architecture change.

## The mental model

Think about the writing flow in three layers:

1. Capture layer
   The user writes, the app builds a canonical `.anky` payload, and `LocalWritingCapture` holds the finished local session.

2. Canonical local model layer
   `LocalWritingCapture` becomes an `AnkySessionBundle`, then a `LocalArchiveRecord`.

3. Legacy UI layer
   Existing profile/chat/archive screens still read `CachedWritingEntry`, but that data is now projected from the canonical archive record instead of being the source of truth.

The important consequence is that pending state, retry payloads, and artifact updates now mutate the canonical archive record first.

## Files to study

- `Anky/AnkyContractFoundation.swift`
- `Anky/LocalArchiveStore.swift`
- `Anky/AppState.swift`
- `Anky/PendingAnkyRetryService.swift`
- `Anky/WritingCacheStore.swift`
- `Anky/AnkyModels.swift`
- `Anky/AnkyAPI.swift`

## What changed in each file

### `AnkyContractFoundation.swift`

This file stopped being just naming and adapters. It now carries enough local state to support the real runtime:

- `AnkySessionBundle.KeystrokeMetadata` now keeps:
  - `canonicalSessionFilePath`
  - `canonicalSessionString`
- `LocalArchiveRecord` now keeps:
  - `isAnky`
  - `prompt`
  - `flowScore`
- `LocalArchiveRecord.retryableCapture` reconstructs a resend-safe `LocalWritingCapture` from canonical archive state.
- `LocalArchiveRecord.legacyCachedWritingEntry` is the deliberate adapter back to the old UI model.

The key idea is that the canonical model now has enough information to survive a retry without asking the legacy cache to be the truth.

### `LocalArchiveStore.swift`

This is the new canonical persistence layer.

It does four jobs:

1. Loads and saves `[LocalArchiveRecord]`.
2. Migrates from the older `anky.cached.writings` storage key.
3. Merges legacy remote history into the canonical local archive.
4. Writes a legacy `[CachedWritingEntry]` projection back out for compatibility.

That last part matters. We did not break the UI. We changed what owns the data.

### `AppState.swift`

`AppState` now owns:

- `localArchiveRecords`
- `writingHistory`

But those are not equal peers anymore.

- `localArchiveRecords` is the canonical archive state.
- `writingHistory` is the projected legacy read model.

Methods like these now update the canonical archive first:

- `recordWriting(...)`
- `storeReflection(...)`
- `storeGeneratedArtifacts(...)`
- `storeRetryArtifacts(...)`
- `updateWritingSyncState(...)`
- `refreshWritings()`

This is a good Swift state-management lesson: one source of truth, multiple projections.

### `PendingAnkyRetryService.swift`

Before this change, retry behavior mainly thought in `CachedWritingEntry`.

Now the service:

- sweeps `appState.pendingArchiveRecords`
- reconstructs resend state from `LocalArchiveRecord`
- only uses `retry(entry:)` as a legacy UI adapter

That makes the retry path match the product truth:

- the client owns the durable session bundle
- retry comes from the local archive
- the backend is not the archive

### `WritingCacheStore.swift`

This file is now intentionally smaller in meaning.

It is a compatibility adapter over `LocalArchiveStore`.

That is worth noticing as a Swift architecture lesson:

- sometimes the correct refactor is not deleting a widely used type yet
- it is reducing that type into a thin adapter while the real model moves underneath

### `AnkyModels.swift` and `AnkyAPI.swift`

These files now prepare the next PR.

They add client-side support for the canonical backend readback surfaces:

- `GET /api/anky/sessions/{session_hash}`
- `GET /api/anky/sessions/{session_hash}/proof`

Important new ideas:

- `CanonicalProcessorStatusResponse`
- `CanonicalProofResponse`
- mapping readback/proof responses back into `AnkyProofMetadata`
- mapping processor responses back into `LocalArchiveRecord`

The runtime is not using those endpoints yet. This PR only makes the future cutover straightforward.

## How data moves now

For the active writer, the path is now:

1. `AnkyChatView` or `SealingView` finishes a `LocalWritingCapture`
2. `AppState.recordWriting(...)` converts that into a `LocalArchiveRecord`
3. `LocalArchiveStore` persists that canonical record
4. `AppState` projects it back into `writingHistory`
5. streamed title/reflection/image updates mutate the canonical archive record
6. retry reconstruction reads the canonical archive record back into `LocalWritingCapture`

That is the full local-first loop.

## Swift concepts to notice

- Value-type modeling with `struct`
  `AnkySessionBundle` and `LocalArchiveRecord` are immutable snapshots. Updates create new values.

- Projection/adaptation
  `legacyCachedWritingEntry` is a clean example of turning a canonical model into a compatibility model.

- Single source of truth
  `AppState` now treats `localArchiveRecords` as the real state and derives `writingHistory`.

- Additive refactor strategy
  We did not force a UI rewrite or backend cutover in the same PR. We changed the data ownership first.

## Backend connection

The app still talks to legacy history through:

- `GET /swift/v2/writings`
- `GET /swift/v2/writing/{sessionId}/status`

But it is now prepared for:

- `GET /api/anky/sessions/{session_hash}`
- `GET /api/anky/sessions/{session_hash}/proof`

That is the processor-readback future that the next PR later activated.

## Common failure modes

### 1. Updating `writingHistory` directly

If you add a new archive mutation and only touch `writingHistory`, you are reintroducing the old architecture.

Update `LocalArchiveStore` and `AppState.localArchiveRecords` first.

### 2. Putting retry-only data back into `CachedWritingEntry`

If a resend feature needs session payload data, prefer `AnkySessionBundle` and `LocalArchiveRecord`.

The legacy cache model should not become the durable owner again.

### 3. Treating remote history as canonical

`/swift/v2/writings` is still a legacy projection.

It can enrich the local archive, but it should not redefine the app’s archive ownership model.

### 4. Forgetting the `.anky` payload handle

The canonical local resend path depends on:

- `canonicalSessionString`
- `canonicalSessionFilePath`
- `sessionHash`

If you drop those, you weaken local-first durability.

## Try this yourself

1. Open `AppState.recordWriting(...)` and trace how a finished session becomes a `LocalArchiveRecord`.
2. Open `LocalArchiveStore.mergeRemote(...)` and check how local payload ownership survives when remote history arrives later.
3. Open `PendingAnkyRetryService.resolveCapture(...)` and verify that retry rebuilds from the canonical archive record.
4. Open `AnkyModels.swift` and read `applyingCanonicalProcessorStatus(...)` to see how the next PR can wire processor readback into the same local archive model.
