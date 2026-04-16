# 023 Contract Foundation: Bundle, Archive, and Proof

This lesson explains the first contract-foundation PR in `ios-app`.

Nothing in this pass was a runtime cutover.
Nothing in this pass deleted the old paths.

The job here was simpler and more important:

1. name the canonical objects clearly
2. put the locked rules in one place
3. teach the existing code how to project into those objects
4. mark the older competing models as legacy

If you keep that mental model in mind, the whole pass makes sense.

## The mental model

The locked product truth says a completed Anky is not "just a writing row."

It is a session bundle that moves through this loop:

`write -> title -> reflect -> image -> prove -> archive`

That means the client needs clear native types for:

- the sacred writing session itself
- the local archive record that stores it on-device
- the proof metadata that says the session was real
- the validation rules that decide whether the artifacts are complete

Before this pass, the repo had pieces of that idea spread across:

- `LocalWritingCapture`
- `CachedWritingEntry`
- `WritingItem`
- `/swift/v2/writing/{id}/status`
- `.anky` file helpers

Those pieces were useful, but they were not one obvious contract.

Now they project into one.

## The files involved

- `Anky/AnkyContractFoundation.swift`
- `Anky/AnkyModels.swift`
- `Anky/AnkyAPI.swift`
- `Anky/AppState.swift`
- `Anky/OfflineQueue.swift`
- `Anky/AnkyWritingSession.swift`
- `Anky/SessionArchiveStore.swift`
- `Shared/AnkySession.swift`
- `Shared/AnkySessionState.swift`

## What the new foundation file does

`AnkyContractFoundation.swift` is now the internal source of truth for the first refactor phase.

It defines:

- `AnkyContract.Qualification`
- `AnkyContract.Title`
- `AnkyContract.Artifacts`
- `AnkySessionBundle`
- `LocalArchiveRecord`
- `AnkyProofMetadata`
- `AnkyImageArtifact`
- `AnkyArtifactCompleteness`

That matters because later PRs no longer need to invent new names like:

- "writing record"
- "archive entry"
- "anky status"
- "proof receipt"
- "session payload"

The canonical answer is now in one file.

## Centralized qualification rules

The fixed rules now live in:

- `AnkyContract.Qualification.minimumDurationSeconds`
- `AnkyContract.Qualification.minimumWordCount`

and the actual helper methods:

- `qualifies(text:durationSeconds:)`
- `qualifies(durationSeconds:wordCount:)`
- `wordCount(in:)`

This is a good Swift design move.

Instead of every file remembering:

- `480`
- `300`

the app now asks the contract layer.

That is why these low-risk call sites were changed:

- `LocalWritingCapture`
- `CachedWritingEntry.init(item:)`
- `OfflineQueue`
- `AnkyWritingSession`
- `AnkyChatView`
- `ContentView`
- `AnkyProfileView`
- `OnboardingRitualView`
- `MirrorView`
- `FlowScoreCalculator`

The runtime behavior stays the same.
The rule just stops drifting.

## The 3-word title rule

The title rule now has one validator:

- `AnkyContract.Title.validation(for:)`

and one boolean shortcut:

- `AnkyContract.Title.isValid(_:)`

This matters because title used to be "just an optional string."

Now the code can distinguish between:

- missing title
- wrong number of words
- valid canonical title

That is how you stop placeholders like `"An anky was born."` from pretending to be canonical completed titles.

## Artifact completeness

The new required-artifact validator lives in:

- `AnkyContract.Artifacts.completeness(...)`

It checks the four locked artifacts:

- title
- reflection
- image
- proof

and returns:

- `AnkyArtifactCompleteness`

with:

- `missingArtifacts`
- `isComplete`

This is an important architectural shift.

Before this pass, "complete" could mean:

- synced
- long enough
- has backend status
- maybe has reflection

Now there is one explicit answer for canonical artifact completeness.

## The new canonical models

### `AnkySessionBundle`

This is the client-side model of the sacred session bundle.

It holds:

- session identity
- author identity
- client origin
- started/completed times
- duration and word count
- writing plaintext
- keystroke metadata
- title, reflection, image
- session hash
- proof metadata
- artifact status
- sync status
- deletion status

This is the model later PRs should normalize around.

### `LocalArchiveRecord`

This is the durable local archive read model.

It wraps:

- one `AnkySessionBundle`
- archive timing
- backend id when present
- kingdom / energy / reason metadata
- source information

The important detail is the `source`.

Right now the app still has older data models, so `LocalArchiveRecord` makes that explicit:

- `.localSessionBundle`
- `.legacyCachedWritingProjection`
- `.legacyRemoteHistoryProjection`

That is how this PR reduces ambiguity without deleting the old code yet.

### `AnkyProofMetadata`

This is the canonical proof type for iOS.

It is centered on:

- `sessionHash`

and then adds:

- proof source
- verification status
- optional wallet signature
- optional anchor signature
- optional proof URL

This is the right mental model:

proof is not "some random receipt field."
proof is a coherent object attached to the session bundle.

## How the old models connect to the new ones

The contract layer adds adapters instead of forcing a risky cutover.

Examples:

- `LocalWritingCapture.canonicalSessionBundle`
- `LocalWritingCapture.localArchiveRecord`
- `CachedWritingEntry.canonicalSessionBundle`
- `CachedWritingEntry.localArchiveRecord`
- `WritingItem.canonicalSessionBundle`
- `WritingItem.localArchiveRecord`
- `WritingStatusResponse.artifactCompleteness`

That means later PRs can migrate feature by feature.

They do not need to rewrite the entire app in one step.

## How the backend still fits in

This PR did **not** change the backend contract.

The live canonical submit path is still:

- `POST /api/anky/submit`

What changed is the iOS-side mental model around that path.

`AnkyAPI.makeAnkySubmitRequest(...)` now derives timing and hash semantics from:

- `capture.canonicalSessionBundle`

That is a very good pattern to notice.

The API layer should not reinvent session meaning.
It should consume the session-bundle model.

## Legacy paths that are now labeled clearly

This PR explicitly marks older competing systems as legacy, including:

- `/swift/v2/write`
- sealed-write submit
- relay proof/archive path
- sealed session proof path
- Arweave plaintext archive helper
- app-group archive/session models
- cached writing and remote history projections

That does not remove them yet.
It just stops them from pretending to be the canonical architecture.

## Swift concepts involved

- `enum` namespaces for rules and validation helpers
- `struct` value types for canonical bundle/archive/proof models
- computed properties for adapters and projections
- optional modeling for additive migration work
- `Codable` for future durable archive shapes
- focused extensions to keep legacy-to-canonical projection logic near the type being projected

## SwiftUI and native iOS concepts involved

This PR is mostly model-layer work, but it still affects SwiftUI architecture.

Why?

Because SwiftUI screens need a clear read model.

`LocalArchiveRecord` is that future read model.

Even though the UI still renders from `CachedWritingEntry` today, the repo now has a native type that says:

- this is what the archive actually wants to read from

That is a classic refactor technique in iOS:

1. introduce the right model
2. add adapters
3. cut screens over later

## Common failure modes

If a title looks present but the canonical contract says it is missing:
check `AnkyContract.Title.validation(for:)`.

If a session is synced but still incomplete:
check `AnkyArtifactCompleteness` instead of assuming synced means artifact-complete.

If proof looks "kind of there" but completeness still fails:
check whether the proof object has real canonical fields or only legacy evidence.

If a future PR starts adding new archive fields to `CachedWritingEntry`:
stop and ask whether that field belongs on `AnkySessionBundle` or `LocalArchiveRecord` instead.

If a future PR reintroduces raw `480` and `300` checks:
move that logic back to `AnkyContract.Qualification`.

## Try this yourself

1. Open `Anky/AnkyContractFoundation.swift`.
2. Read `AnkySessionBundle` top to bottom.
3. Follow `LocalWritingCapture.canonicalSessionBundle`.
4. Follow `CachedWritingEntry.localArchiveRecord`.
5. Then read `AnkyAPI.makeAnkySubmitRequest(...)` and notice that the API layer now consumes the bundle projection instead of rebuilding session meaning by hand.

That path is the whole point of the PR:

- the runtime is still old
- the names are now right
- the next refactor can move faster without getting lost
