# 019. Profile Pending Retry And Submit Idempotency

Note as of April 16, 2026:
This lesson still explains why retry must preserve the canonical `.anky` payload and `sessionHash`, but the current retry path now checks canonical processor snapshot/proof readback before reposting. Read `025_runtime_cutover_local_archive_first.md` for the current runtime behavior.

This lesson explains the fallback and recovery path for a real anky that exists in local history but never finished backend processing.

## Mental model

There are now two separate truths after a real writing finishes:

1. The user truth: "I already wrote this. It belongs in my history now."
2. The backend truth: "I may or may not have finished turning this writing into a reflected Anky yet."

The bug here was not just UI. It was architectural. The profile archive knew a pending anky existed, but it did not keep enough protocol data to safely send the same `.anky` session again later.

For a retryable real anky, plain writing text is not enough.

The backend submit contract for `POST /api/anky/submit` depends on the canonical `.anky` payload:

- the exact session string
- the exact `sessionHash`
- the wallet signature over that hash

That means the archive must preserve retry metadata, not just display metadata.

## Files to read

- `Anky/AnkyModels.swift`
- `Anky/WritingCacheStore.swift`
- `Anky/AppState.swift`
- `Anky/AnkySessionFileStore.swift`
- `Anky/AnkyAPI.swift`
- `Anky/AnkyProfileView.swift`

## What changed

### 1. `CachedWritingEntry` now stores retry-critical protocol data

In `AnkyModels.swift`, `CachedWritingEntry` now carries:

- `ankySessionString`
- `ankyFilePath`
- `sessionHash`

This is the important design move.

The profile archive used to store enough data to render a card, but not enough data to reproduce the original submit request. Now it stores both:

- presentation state: title, reflection, image, sync state
- protocol state: canonical session payload and hash

That is what makes a real retry possible.

### 2. Cache rewrites now preserve that metadata

`WritingCacheStore.swift` has several code paths that rebuild cached entries:

- prepend
- migrate
- update response
- update generated artifacts
- merge remote and local state

If even one of those paths dropped `sessionHash` or the `.anky` payload, the profile resend button would look correct but fail later. That is why this lesson matters: persistence bugs are usually "one helper dropped one field."

### 3. Older pending entries try to recover from disk

Some pending entries may already exist from builds that did not cache retry metadata yet.

`AnkySessionFileStore.recoverStoredSession(matching:around:)` is the recovery bridge:

- it looks in the canonical `ankys/yyyy/mm/dd/` directories around the writing date
- it opens candidate `.anky` files
- it reconstructs plain text from the protocol file
- it matches that text against the archived writing

If it finds the right file, the app can rebuild:

- `sessionString`
- `filePath`
- `sessionHash`

and persist them back into the cache.

This is a good example of native iOS state recovery:

- UI state alone was not enough
- the disk artifact became the source of truth for repair

### 4. The profile sheet owns the manual retry action

In `AnkyProfileView.swift`, `ProfileConversationSheet` now derives a live `CachedWritingEntry` from `appState.writingHistory` instead of trusting only the snapshot that opened the sheet.

That matters because retry can change the entry from:

- pending

to:

- synced

while the sheet is still on screen.

The sheet now shows a pending-status card with a `send again` action. That action calls `PendingAnkyRetryService`.

The same retry service now also runs from `AppState.postAuthRefresh()`, so pending real ankys get another chance automatically after launch/login when auth comes back.

### 5. Retry checks backend status before reposting

`PendingAnkyRetryService` does not blindly resubmit first.

It first calls `AnkyAPI.shared.getWritingStatus(sessionId:)`.

If the backend already has an `anky.id`, the client can finalize local state without posting again. That reduces duplicate risk even before the backend fully enforces idempotency.

Only if there is still no stored backend anky does it open a fresh `/api/anky/submit` SSE stream.

## Why idempotency belongs on `sessionHash`

The canonical candidate key already exists: `sessionHash`.

Why this key is good:

- it is stable for the same exact `.anky` session
- it is already signed by the wallet flow
- it naturally identifies the write artifact, not just a UI event

`AnkyAPI.swift` now attaches:

- `Idempotency-Key`
- `X-Anky-Session-Hash`

using that canonical hash.

This is only half of idempotency, though.

The backend still needs to guarantee:

- same `sessionHash` => same stored anky
- repeated submit returns existing work instead of creating duplicates

That is the server-side contract JP should look for next.

## Swift concepts involved

- `Codable`: optional persisted fields allow old cache payloads to keep decoding
- `@MainActor`: `AppState` mutations stay on the main actor because they drive SwiftUI
- local helper functions inside async workflows: useful for SSE handling where several steps share state
- actor-based gating: `PendingAnkyRetryGate` prevents duplicate retry taps from starting multiple concurrent submits for the same session
- shared services: moving retry logic into its own file keeps app-level recovery and profile-level recovery on the same code path

## SwiftUI concepts involved

- environment-driven live data: the sheet re-reads `appState.writingHistory` so it updates after retry
- conditional UI sections: the retry card only exists for pending/unsealed sessions
- async button actions with local view state: `isRetryingPendingAnky` disables the button and drives its label

## Data flow

1. A real writing finishes and gets recorded into local history.
2. The cache preserves the canonical `.anky` submit metadata.
3. On the next authenticated app launch/login, `AppState.postAuthRefresh()` asks `PendingAnkyRetryService` to sweep pending real ankys automatically.
4. Profile can also open that same cached entry and show `send again` for manual recovery.
5. Retry service:
   - resolves the canonical payload from cache or disk
   - checks backend status first
   - resubmits only if still needed
   - updates local artifacts and sync state
6. SwiftUI re-renders from updated `AppState`, whether recovery happened automatically or from the profile button.

## Failure modes to debug

- Button shows but retry fails immediately:
  The device probably does not have cached retry metadata and could not recover the `.anky` file from disk.

- Retry completes but sheet still looks pending:
  Check whether the sheet is reading a live entry from `appState` or a stale snapshot.

- Duplicate ankys appear server-side:
  The likely gap is backend idempotency, not the client retry button itself.

- Reflection/title/image disappear after cache updates:
  Check every `CachedWritingEntry(...)` rebuild path in `WritingCacheStore.swift` for dropped fields.

## Try this yourself

1. Write a qualifying real anky.
2. Force the backend path to fail after the local pending entry is recorded.
3. Open profile and tap the pending anky.
4. Tap `send again`.
5. Watch whether the entry moves from pending to synced without disappearing from history.

The main lesson: once an anky becomes part of the user's history, recovery cannot belong only to one screen. The archive is a recovery surface, but launch/login also has to participate so stalled real ankys can heal themselves without waiting for a manual tap.
