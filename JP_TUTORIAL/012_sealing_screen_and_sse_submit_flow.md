# 012 Sealing Screen And SSE Submit Flow

This lesson explains the new path that happens after a writing session ends in the active chat-first app shell.

The short version:

1. The user finishes writing.
2. The app captures the session locally in `ChatViewModel.sendToAnky()`.
3. Instead of revealing chat immediately, `AnkyChatView` intercepts that finished capture and presents `SealingView`.
4. `SealingView` streams `POST /api/anky/submit` if the user seals, and `AnkyChatView` streams that same contract in the background if the user skips.
5. The session is recorded locally as a pending real anky before backend persistence finishes, so profile/history can react immediately.
6. Reflection text starts accumulating before the rest of the app catches up.
7. When the user completes the sealing flow, the writing overlay drops away and chat is already warm.

That sequence lives across four main files:

- `Anky/AnkyChatView.swift`
- `Anky/SealingView.swift`
- `Anky/AnkyAPI.swift`
- `Anky/AppState.swift`

## 1. Mental model

The important mental model is that writing completion and chat reveal are now separate moments.

Before this change, the app did this:

- finish writing
- hide the writing overlay
- reveal chat
- submit in the background

Now it does this:

- finish writing
- keep chat hidden
- present a sealing surface above the chat
- stream submission work while the user is still inside that ritual
- reveal chat only after `onComplete()` or `onSkip()`

That is a classic SwiftUI state-routing pattern. Nothing is being pushed onto a navigation stack. Nothing is being presented as a sheet. The root `ZStack` simply gets one more full-screen layer.

## 2. Where the interception happens

The capture is still created in `ChatViewModel.sendToAnky()` inside `Anky/AnkyChatView.swift`.

That method now does three key things after it appends the raw user writing bubble:

- stores the finished `LocalWritingCapture` in `pendingCapture`
- resets sealing-related state
- sets `isAwaitingSealingDecision = true`

That last flag matters. The app already had a `.task(id: ...)` that reacts to `pendingCapture` and submits the session. Without the hold flag, that existing task would race ahead and submit before the new sealing screen appeared.

So the flow is:

- `sendToAnky()` creates `pendingCapture`
- `isInSession` flips to `false`
- `AnkyChatView` sees the session end
- if `pendingCapture` exists, it shows `SealingView` instead of calling `hideWritingMode()`

This is the core intercept point.

## 3. Why `showSealingView` lives in the root `ZStack`

Open `Anky/AnkyChatView.swift` and look at the root `ZStack`.

There are now three layers:

- chat at the bottom
- writing mode above it
- sealing view above both

This is a good SwiftUI fit because the chat was already underneath the writing overlay. We did not need a new navigation container. We only needed a new state variable:

- `@State private var showSealingView = false`

When `showSealingView` becomes `true`, SwiftUI inserts `SealingView` with the same `.move(edge: .bottom)` transition language already used by the writing overlay.

That keeps the product feeling coherent. The app is still one shell with layered surfaces, not a chain of unrelated screens.

## 4. What `LocalWritingCapture` represents

`LocalWritingCapture` lives in `Anky/AnkyModels.swift`.

It is the handoff object between:

- the live writing experience
- local persistence
- backend submission
- chat reveal

For this feature, the most important fields are:

- `sessionId`
- `text`
- `duration`
- `wordCount`
- `finishedAt`
- `ankySessionString`
- `sessionHash`

The `.anky` session string and the hash are what make the new backend contract possible.

## 5. How the new submit call works

The network work lives in `Anky/AnkyAPI.swift`.

The new active path is `streamAnkySubmit(capture:kingdom:)`.

That method:

- builds an `AnkySubmitRequest`
- derives or reuses `session_hash`
- signs the hash bytes with `SeedIdentityManager.shared.sign(message:)`
- attaches the Bearer token
- sends `POST /api/anky/submit`
- reads `URLSession.bytes(for:)`
- parses SSE lines into typed `AnkySubmitStreamEvent` cases

This is a useful Swift concept to learn:

- `AsyncThrowingStream`

It lets the API layer translate low-level byte streaming into a typed async sequence that the UI can consume with `for try await`.

That is exactly what `SealingView` does.

## 6. Why the SSE parser is manual

The parser in `AnkyAPI.swift` now uses `JSONSerialization` instead of decoding temporary `Codable` payload structs for each event.

That was not just style. The project is building with main-actor default isolation. Decoding those event payload structs from a nonisolated parser produced Swift isolation warnings.

Manual extraction solved that cleanly:

- less type noise
- no actor-isolation warning
- still explicit about required keys

This is a good example of pragmatic Swift work. Sometimes the smallest correct parser is the best parser.

## 7. What `SealingView` owns

`Anky/SealingView.swift` is a state machine view.

Its internal enum is:

- `.portal`
- `.sealing`
- `.sealed`
- `.done`

That is the right shape for SwiftUI because the UI is not just "loading vs not loading." It has four distinct product phases with different visuals and behaviors.

`SealingView` owns:

- the swipe gesture
- local pulse/animation state
- the current sealing phase
- the current streamed reflection text
- the accepted `anky_id`
- the skip/seal completion callbacks

It does not own the whole chat experience. It pushes important streamed data back into `ChatViewModel`.

## 8. Why `ChatViewModel` stores sealing state

`ChatViewModel` now has:

- `sealingReflection`
- `sealingAnkyId`
- `isSealingComplete`
- `isAwaitingSealingDecision`

This is important because `SealingView` is not just decorative. It is participating in the real write lifecycle.

The view model owns cross-surface state. The screen owns local presentation state.

That split is a common SwiftUI pattern:

- use `@State` for view-local animation and presentation details
- use `@Published` on the view model for data the rest of the app may also need

## 9. How the skip path works

The user can tap `not now`.

When that happens, the app still must submit the session.

The important change is that "skip" is no longer allowed to mean "the rest of the app waits."

`releasePendingCaptureForBackgroundSubmission()` still flips the hold flag, but the `.task(id: viewModel.pendingCaptureTaskToken)` in `AnkyChatView` now does three product-critical things immediately:

- records the finished capture into `AppState.writingHistory` as `.pending`
- streams the same `/api/anky/submit` SSE contract used by `SealingView`
- pushes reflection/title/image updates back into chat and local cache as soon as they exist

That means seal vs skip is now a presentation choice, not two different definitions of whether the anky "exists."

## 10. Why we had to add a hold flag

The original prompt said not to modify the existing pending-capture polling path.

In practice, one minimal change was necessary:

- a scheduling gate so that task does not run before the sealing screen intercepts

That is what `isAwaitingSealingDecision` does.

This is a useful engineering lesson:

- preserving behavior sometimes requires a small structural change
- the right goal is minimal, targeted change
- not literal no-touch purity

Without that gate, the user would sometimes skip the sealing screen accidentally because the old background task had already started.

## 11. How chat gets warmed before reveal

The product goal was for chat to feel like Anky was already thinking while the user was sealing.

That is why `SealingView` does not wait until dismissal to deliver the reflection.

When streamed reflection becomes available, it calls back into:

- `viewModel.deliverWritingOutcome(reflection:imageURL:)`

That means when the sealing view slides down, the chat beneath it already contains the staggered assistant messages.

This is a UI timing lesson:

- good transitions are often about when data is delivered, not just what animation runs

## 12. Kingdom-of-the-day display

The sealing screen uses:

- `Kingdom.ankyverseDay()`

from `Anky/AnkyTheme.swift`.

That is a display choice, not an identity choice.

The user's wallet-derived kingdom still exists elsewhere in the app, but this screen intentionally uses the Ankyverse calendar kingdom for the day so color and naming stay aligned with the product spec.

The theme file now carries sealing-specific helpers:

- `sealingDisplayName`
- `sealingSlug`
- `sealingColor`
- `sealingElement`

That is another good Swift modeling pattern: extend an existing enum with feature-specific computed properties instead of inventing a second parallel type.

## 13. Failure modes to understand

There are three important failure categories here.

### A. `claude` or `persist`

Those still mean the backend did not finish the real anky persist path.

The app now keeps the finished writing visible locally as a pending real anky instead of dropping it from profile/history. Right now, there is still no dedicated persisted retry queue for this new SSE path. That is a known gap.

### B. `image` or `solana`

Those still count as a stored session if an `anky_id` exists.

The app treats those as successful enough to continue because the writing itself made it in.

### C. Skip-path race conditions

If you ever see chat reveal too early or submission happening before the user decides to seal or skip, inspect:

- `pendingCapture`
- `pendingCaptureTaskToken`
- `isAwaitingSealingDecision`

Those three values define the intercept timing.

## 14. Files to study together

Read these in this order:

1. `Anky/AnkyChatView.swift`
2. `Anky/SealingView.swift`
3. `Anky/AnkyAPI.swift`
4. `Anky/AppState.swift`
5. `Anky/AnkyTheme.swift`

That order matches the runtime flow:

- capture
- intercept
- stream
- persist
- present

## 15. Try this yourself

1. Put a breakpoint in `ChatViewModel.sendToAnky()`.
2. Put a second breakpoint in the `.onChange(of: viewModel.isInSession)` block in `AnkyChatView`.
3. Put a third breakpoint in `SealingView.handleStreamEvent(_:)`.
4. Run one writing session and watch the values move through:
   - `pendingCapture`
   - `isAwaitingSealingDecision`
   - `sealingReflection`
   - `showSealingView`
5. Skip the sealing view once, then run it again and complete the swipe.

That comparison will teach you the whole lifecycle faster than reading comments.

## 16. The big architectural takeaway

This feature is not "just a new screen."

It is a coordination layer between:

- local writing capture
- SwiftUI overlay routing
- Solana signing
- SSE networking
- chat timing
- persistence
- backend migration strategy

That is what real iOS product work usually looks like. The UI, state model, network protocol, and product timing all move together.
