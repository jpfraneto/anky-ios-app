# 018 Background Skip Submit And Pending Archive Truth

This lesson explains the bug JP actually needs to understand:

- the user finishes a real 8-minute anky
- they skip the sealing ritual because they want to get back to chat
- the app must still treat that finished anky as real immediately

If it does not, the product feels broken even when the backend is technically still processing.

The files to study are:

- `Anky/AnkyChatView.swift`
- `Anky/SealingView.swift`
- `Anky/AppState.swift`
- `Anky/WritingCacheStore.swift`
- `Anky/AnkyProfileView.swift`

## 1. Mental model

Finishing writing creates a real local event before it creates a fully persisted backend artifact.

That is the core mental model.

There are two separate truths:

1. the user definitely completed a qualifying writing session on this device
2. the backend may still be generating reflection, image, and persistence records

The app has to honor truth `1` immediately.

That is why a qualifying `LocalWritingCapture` now gets written into `writingHistory` as `.pending` the moment the skip/background path starts.

## 2. Where the bug lived

Look at `AnkyChatView.swift`.

`ChatViewModel.sendToAnky()` already did the first correct thing:

- append the raw user writing bubble
- store the finished `LocalWritingCapture` in `pendingCapture`
- set `isAwaitingSealingDecision = true`

The problem happened after the user tapped `not now`.

Before this fix, the `.task(id: viewModel.pendingCaptureTaskToken)` branch waited for a helper that did not update local history until much later. That meant:

- chat could sit on typing dots
- profile could still show `0` ankys
- the user had already done the work, but the UI was acting like nothing happened

That is a product bug, not just a timing bug.

## 3. How the fixed flow works

Open `submitPendingCaptureInBackground(_:)` in `Anky/AnkyChatView.swift`.

That function is now the background mirror of the sealing path.

It does this in order:

1. checks whether the capture actually qualifies for a real anky
2. records it locally through `appState.recordWriting(..., syncState: .pending)`
3. starts streaming `POST /api/anky/submit`
4. stores reflection/title/image back into local cache as they arrive
5. upgrades the entry to `.synced` only when the backend has clearly accepted/persisted it

This is the important architecture point:

- pending means "the user really wrote this"
- synced means "the backend has caught up"

Those are not the same thing, and the UI should not pretend they are.

## 4. Why profile updates immediately now

`AnkyProfileView.swift` builds its archive from `appState.writingHistory`.

The `sessions` array is:

- filtered by `entry.isAnky`
- sorted by `createdAt`

It does not require `syncState == .synced`.

That means a `.pending` real anky will appear in profile as soon as it lands in `writingHistory`.

That is exactly what we want.

The thumbnail already knows how to show the difference:

- synced sessions are "sealed"
- pending sessions show the unsealed indicator

So the data model already had the right shape. The bug was that the skip path was not populating that model early enough.

## 5. The Swift concept underneath this

The network layer returns an `AsyncThrowingStream<AnkySubmitStreamEvent, Error>`.

That means the UI can consume backend progress like this:

- `accepted`
- `title`
- `reflection_chunk`
- `reflection_complete`
- `image_url`
- `done`

That is a much better fit than waiting for one big final response when the product itself is staged.

Swift concept to understand:

- `AsyncThrowingStream` lets the app react to backend progress event by event
- `@MainActor` makes sure the state mutations touching SwiftUI happen on the UI actor

In practice, that means chat can warm up while the anky is still being processed.

## 6. Why there is still polling after the stream

The backend stream and the history/status endpoints are not the same source.

The stream is the fastest path for live UX.
`GET /swift/v2/writing/{sessionId}/status` is the recovery path when some artifact arrives late or the stream closes before every field is sent.

So `submitPendingCaptureInBackground(_:)` does both:

- stream first for immediacy
- poll for missing reflection/title/image/prompt when needed

This is a real iOS integration pattern:

- use streaming for live UX
- use polling to heal partial backend timing differences

## 7. How `AppState` and cache fit together

`AppState.recordWriting(...)` creates the `CachedWritingEntry`.

`WritingCacheStore.prepend(...)` persists it in `UserDefaults`.

Later:

- `AppState.storeGeneratedArtifacts(...)` fills in reflection/title/image
- `AppState.applyPersistedAnkySuccess(...)` upgrades the entry to `.synced` and refreshes server-backed state

That gives the app a layered persistence model:

- first save the fact that the session exists
- then enrich it
- then sync it

This is exactly how you keep the app honest during slow backend work.

## 8. Common failure modes

### A. The session disappears from profile

Check whether the qualifying capture was recorded as `.pending` before waiting on the network.

Files:

- `Anky/AnkyChatView.swift`
- `Anky/AppState.swift`

### B. Chat stays on typing dots

Check whether reflection ever reaches:

- `fullReflection`
- `viewModel.deliverWritingOutcome(...)`

Then check whether the fallback status polling is filling missing artifacts from `/writing/{sessionId}/status`.

Files:

- `Anky/AnkyChatView.swift`
- `Anky/AnkyAPI.swift`

### C. A real anky never upgrades from pending to synced

Check whether the stream reached:

- `accepted`
- `done`

or whether the status poll can still recover enough data to call `applyPersistedAnkySuccess(...)`.

Files:

- `Anky/AnkyChatView.swift`
- `Anky/AppState.swift`

## 9. Try this yourself

1. Put a breakpoint in `ChatViewModel.sendToAnky()`.
2. Put a breakpoint in `submitPendingCaptureInBackground(_:)`.
3. Put a breakpoint in `AppState.recordWriting(...)`.
4. Finish a qualifying anky and tap `not now`.
5. Watch these values in order:
   - `pendingCapture`
   - `isAwaitingSealingDecision`
   - `writingHistory.first?.syncState`
   - `writingHistory.first?.response`
   - `writingHistory.first?.ankyImagePath`

If the sequence is healthy, you should see:

- raw writing bubble first
- `.pending` archive entry immediately
- reflection appear in chat
- profile show the new anky before cloud history catches up

## 10. The big takeaway

In Anky, "I finished writing" is a first-class app event.

Backend persistence matters.
Generated reflection matters.
Images matter.

But none of those are allowed to erase the truth that the user already completed the practice.

That is the product reason this fix exists, and it is the architectural reason the pending archive state matters.
