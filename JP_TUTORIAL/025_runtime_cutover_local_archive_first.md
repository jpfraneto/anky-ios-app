# 025 Runtime Cutover, Local Archive First

This lesson explains the April 16, 2026 runtime cutover that made the live iOS app behave like the canonical Anky architecture.

This is the important mental model:

1. The phone owns the durable session bundle.
2. The phone owns the durable local archive record.
3. The backend processor enriches that archive record.
4. A session is not canonically sealed until the local archive has:
   - a valid 3-word title
   - a reflection
   - an image
   - proof-of-writing

That means the app must stop asking legacy backend history to tell it whether an Anky is "done."

The local archive is the truth.

## Files to study

- `Anky/AnkyContractFoundation.swift`
- `Anky/LocalArchiveStore.swift`
- `Anky/AppState.swift`
- `Anky/SealingView.swift`
- `Anky/AnkyChatView.swift`
- `Anky/PendingAnkyRetryService.swift`
- `Anky/AnkyProfileView.swift`
- `Anky/AnkyModels.swift`
- `Anky/AnkyAPI.swift`

## 1. The core mental shift

Before this cutover, the app had the right local models, but the live runtime still finished Ankys with older heuristics:

- `/swift/v2/writing/{sessionId}/status`
- `/swift/v2/writings`
- "synced" state that could exist before proof was real

After this cutover, the runtime works like this:

1. Writing finishes.
2. The app writes a canonical `.anky` file.
3. The app stores a pending `LocalArchiveRecord`.
4. `POST /api/anky/submit` streams acceptance and artifacts.
5. As soon as the backend accepts the session, the local archive stores the backend anky id.
6. The app reconciles the session by `sessionHash` through:
   - `GET /api/anky/sessions/{session_hash}`
   - `GET /api/anky/sessions/{session_hash}/proof`
7. The local archive becomes sealed only when completeness says title, reflection, image, and proof are all present.

That is the actual local-archive-first architecture.

## 2. Why `LocalArchiveRecord` matters

`LocalArchiveRecord` is now the real client archive model.

Open `AnkyContractFoundation.swift` and study these pieces:

- `artifactCompleteness`
- `isCanonicallySealed`
- `needsCanonicalProcessorReconciliation`
- `reconcilingCanonicalSyncStatus(updatedAt:)`

These helpers do an important job:

- they stop old "synced" flags from lying
- they force proof to matter
- they make "processing" vs "sealed" a data rule instead of a UI guess

This is a good Swift lesson in putting business truth on the model instead of scattering it through views.

## 3. What `AppState` now owns

Open `AppState.swift`.

The runtime cutover moved the live archive logic into a few clear functions:

- `storeCanonicalAcceptedSubmission(...)`
- `applyCanonicalProcessorStatus(...)`
- `applyCanonicalProofReadback(...)`
- `reconcileCanonicalArchiveRecord(...)`
- `hydrateCanonicalArchiveRecordIfAvailable(...)`
- `refreshCanonicalArchiveReadback()`

The mental model is:

- `AppState` owns the array of canonical archive records
- views ask `AppState` for archive truth
- `writingHistory` still exists, but only as a projection for older UI

That is a classic state-management move in SwiftUI:

- one owner for the real state
- derived adapters for older consumers

If JP remembers one sentence from this lesson, it should be this:

Do not mutate `writingHistory` directly when you mean to change archive truth.

Mutate the canonical archive, then let the adapter projection update.

## 4. How the submit flow changed

### `SealingView.swift`

The sealing path now does three separate jobs:

1. show the ritual UI
2. stream `/api/anky/submit`
3. reconcile the archive after acceptance through snapshot/proof readback

The key methods are:

- `persistStoredSubmissionIfNeeded(ankyId:)`
- `reconcileCanonicalArchive(pollUntilSettled:markComplete:)`
- `absorbArchiveRecord(_:markComplete:)`

This is important because SSE is not the same thing as final truth.

Streaming is great for immediacy.
The archive is for durability.
Snapshot/proof readback is how the durable archive catches up if the stream ends before every artifact arrives.

### `AnkyChatView.swift`

The skip/background path now follows the same architecture.

That matters because the user should not get two different product truths:

- one truth when they watch the sealing surface
- another truth when they skip it

Both paths now:

- persist pending archive state first
- store accepted backend identity immediately
- reconcile through the session hash

## 5. How retry changed

Open `PendingAnkyRetryService.swift`.

The important change is that retry is no longer:

- "poll old status route"
- "guess whether it finished"
- "repost if maybe not"

Now retry first asks:

1. can I rebuild the canonical capture from the local archive?
2. does canonical snapshot/proof readback already know this session?
3. if yes, can I just hydrate the local archive instead of reposting?

That is the correct local-first approach.

The resend path should be conservative.
If the backend already knows the `sessionHash`, the client should prefer reconciliation over duplication.

## 6. How profile changed

Open `AnkyProfileView.swift`.

The active profile surface now builds its live session list from:

- `appState.canonicalArchiveAnkys`

not from raw `writingHistory`.

`ProfileAnkySession` now wraps a `LocalArchiveRecord`.

That gives the UI direct access to:

- canonical title
- canonical reflection
- canonical image
- proof-aware sealed state
- missing-artifact information

This is a good example of a SwiftUI read model:

- the model handed to the view already knows what "processing" means
- the view does not need to reverse-engineer state from half-trusted fields

## 7. How backend contract thinking changed

The backend still matters, but it matters in a narrower way now.

The client does not ask the backend to be the canonical plaintext archive anymore.

The backend now does these jobs for the core flow:

- accept the canonical session
- process title/reflection/image
- expose status snapshot by `sessionHash`
- expose proof object by `sessionHash`

That contract lives in:

- `AnkyAPI.getCanonicalSessionSnapshot(sessionHash:)`
- `AnkyAPI.getCanonicalSessionProof(sessionHash:)`
- `CanonicalProcessorStatusResponse`
- `CanonicalProofResponse`

This is a useful iOS architecture lesson:

Sometimes the right boundary is not "download the archive from the server."

Sometimes the right boundary is:

- store the archive locally
- ask the server only for the processor outputs that local archive still needs

## 8. Swift concepts in this change

- Value-type modeling with `struct`
  `LocalArchiveRecord` and `AnkySessionBundle` stay easy to reason about because every mutation returns a new value.
- Derived state
  `writingHistory` is now derived from `localArchiveRecords`.
- Focused extensions
  Mapping from API response to canonical model lives near the model in `AnkyModels.swift`.
- Async orchestration
  `AppState` coordinates streaming acceptance and later readback with async functions instead of burying network logic inside every view.
- MainActor boundaries
  Views can ask `AppState` for mutations/reconciliation while keeping UI state changes on the main actor.

## 9. Common failure modes

### 1. A session shows as sealed before proof exists

Check:

- `artifactCompleteness`
- `isCanonicallySealed`
- `reconcilingCanonicalSyncStatus(updatedAt:)`

If proof is missing, the session should still be processing.

### 2. A remote history merge marks a local session as done too early

Check `LocalArchiveStore.merge(remote:local:)`.

The merge should preserve the local canonical payload and must not let legacy `/swift/v2/writings` mark the session `.synced` before proof exists.

### 3. Retry reposts a session the backend already knows

Check `PendingAnkyRetryService.retry(record:appState:)`.

It should hydrate from canonical snapshot/proof first.

### 4. A profile card never leaves processing

Check:

- whether the record has a `sessionHash`
- whether `getCanonicalSessionSnapshot(sessionHash:)` succeeds
- whether proof readback returns a real proof object

## 10. Try this yourself

1. Open `AppState.reconcileCanonicalArchiveRecord(...)`.
2. Follow how it calls `refreshCanonicalArchiveRecord(...)`.
3. Open `AnkyModels.swift` and read `applyingCanonicalProcessorStatus(...)`.
4. Open `AnkyContractFoundation.swift` and read `reconcilingCanonicalSyncStatus(updatedAt:)`.
5. Ask yourself one question:

"If the SSE stream dies after `accepted`, what exact code path still lets the archive become sealed?"

If you can answer that clearly, you understand the cutover.
