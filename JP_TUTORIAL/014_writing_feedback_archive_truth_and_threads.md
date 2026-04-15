# 014 Writing Feedback, Archive Truth, And Threads

This lesson explains a cluster of fixes that belong together even though they touch different screens.

The user-visible requests sounded separate:

1. make the writing screen calmer
2. make the post-write reply actually arrive
3. make the finished anky show up in profile
4. make profile only show real ankys
5. let each archived anky reopen as a conversation

Under the hood, those are all the same architecture problem:

- the live writing state
- the submit pipeline
- the cached archive state
- the profile/detail UI

all need to agree about what a "real anky" is and what phase that anky is in.

The main files for this lesson are:

- `Anky/AnkyChatView.swift`
- `Anky/SealingView.swift`
- `Anky/AppState.swift`
- `Anky/AnkyModels.swift`
- `Anky/WritingCacheStore.swift`
- `Anky/AnkyProfileView.swift`
- `Anky/ProfileView.swift`
- `Anky/AnkyThreadChatStore.swift`

## 1. Mental model

Think about the flow as three layers of truth:

1. **live session truth**
2. **local archive truth**
3. **remote backend truth**

Live session truth is what the user is doing right now on the writing screen.

Local archive truth is what the phone already knows happened, even if the backend has not caught up yet.

Remote backend truth is what eventually comes back from `/swift/v2/writings`.

If those three layers disagree, the app feels haunted:

- a real anky vanishes from profile
- a short write looks like a real one
- the submit screen spins forever
- a thread detail opens but has no conversation in it

The fixes in this session mostly make those layers line up.

## 2. Writing chrome is a state machine, not static UI

Open `Anky/AnkyChatView.swift`.

The writing chrome now has explicit timing rules:

- `idleWarningStart`
- `idleRemainingProgress`
- `idleBarVisible`
- `shouldShowTimer`
- `shouldShowCloseButton`
- `writingBottomInset`

There is one more important presentation rule now:

- before the first keystroke, both the top and bottom bars are visible
- the prompt stays in the `UITextView` placeholder path even before the session has formally started

### Why the idle bar changed

The top bar is not supposed to be a constantly moving decoration.

It is a warning that the session is about to pause/end.

That means it should:

- stay hidden while the user is actively flowing
- appear only after a meaningful pause
- visually empty in the direction the product expects

That is why `idleRemainingProgress` now stays full until 3 seconds of silence have passed. Only after that does it drain over the remaining 5 seconds.

The top bar is still visible before writing starts, but in that pre-writing state it is just a full bar. It does not start behaving like a warning until the user is actually inside a live session.

This is a good SwiftUI mental model:

- compute UI state from domain state
- do not manually animate random booleans if the value can be derived

`IdleProgressBar` also changed alignment so the visible portion shrinks from right to left. That is a small layout change, but it matters because alignment is part of product meaning.

## 2.5 Why the prompt must stay in the text view

The prompt is supposed to feel like it lives inside the writing field, not above it.

That means the `UITextView` needs to own the prompt through its placeholder path instead of letting session-state shortcuts accidentally remove it when the view is empty.

In `Anky/AnkyChatView.swift`, `AnkyModeView` now always passes `writingPlaceholder` into `AnkyComposerTextView`.

Then `Anky/AnkyComposerTextView.swift` keeps the prompt aligned with the real typing position by:

- forcing left text alignment
- measuring the placeholder against the text container width
- using the same font family and inset model as the actual writing

This is a useful UIKit lesson:

- a fake overlay can look almost right
- but placeholder positioning must be tied to the text container geometry if you want it to feel native

### Why the footer chrome hides

The red exit button and the timer row are useful during entry.

Once the user is deep in writing, they become visual noise.

So the view now treats them as onboarding chrome:

- timer stays for the first 20 seconds
- exit button is only there before real writing begins
- after that, the bottom progress bar is the only persistent control

This is a product lesson for JP:

- calm UI is often about removing controls at the right moment
- not about adding more styling

### Why the text inset changed

The text area used to visually run behind the bottom bar.

That is a classic scroll/composer bug in iOS: the editable content area and the decorative chrome are not using the same geometry assumptions.

`writingBottomInset` fixes that by reserving space inside the `UITextView` content area itself.

The important iOS concept here is:

- safe area insets solve screen edges
- text container insets solve editor content visibility

Those are different layers.

## 3. A session can finish without becoming a real anky

The most important business rule lives in `Anky/AnkyModels.swift`:

- `LocalWritingCapture.qualifiesForAnky(text:duration:)`

The thresholds are:

- at least 480 seconds
- at least 300 words

That rule now drives multiple places, not just one API branch.

### Where it is enforced

In `Anky/AnkyChatView.swift`:

- `sendToAnky()` stores `lastWritingThreadID`
- `isAwaitingSealingDecision` is only true for qualifying captures
- the background `pendingCapture` task now keeps short sessions local-only

In `Anky/AppState.swift`:

- `recordWriting(...)` only marks something as a persisted/pending anky if the capture also qualifies locally

In `Anky/AnkyModels.swift`:

- `CachedWritingEntry.init(item:)` ignores the backend `isAnky` flag if the duration/word-count thresholds are not met

That last point matters a lot.

You do not want the UI blindly trusting a backend boolean when the product definition is stricter. The client should defend the product meaning.

## 4. Why the loading dots got stuck

The submit ritual lives in `Anky/SealingView.swift`.

The important methods are:

- `beginStreamingSubmission()`
- `handleStreamEvent(_:)`
- `handleStreamCompletionIfNeeded()`

### What was wrong

The old path assumed the stream would always end with the exact terminal event the UI expected.

If the backend had already accepted the anky and delivered useful data, but then closed the stream normally without the final event sequence, the UI kept waiting forever.

That is why the user saw the three loading dots with no reply.

### What changed

`beginStreamingSubmission()` now immediately records the capture locally as `.pending` through `AppState.recordWriting(...)`.

Then, if the stream finishes and:

- the anky was accepted
- reflection/image data was already accumulated
- but the formal "done" moment never arrived

`handleStreamCompletionIfNeeded()` promotes that state forward instead of leaving the user stranded.

This is an important async networking lesson:

- streams can fail
- streams can terminate early
- streams can also end "successfully enough" for the UI even if the perfect terminal marker never arrives

Your UI state machine must model that reality.

## 5. Local archive truth has to survive remote lag

The history cache lives in `Anky/WritingCacheStore.swift`.

The new helpers are:

- `mergedEntries(remoteItems:existingEntries:)`
- `representsSameWriting(_:_:)`
- `merge(remote:local:)`

### The bug

The old merge behavior trusted the remote `/swift/v2/writings` list too much.

If a fresh local anky had already been submitted and stored on-device, but the backend history endpoint had not returned it yet, the local entry could disappear.

That is exactly the kind of bug that makes a user say:

"I just wrote this. Why is it gone from my profile?"

### The fix

The merge now preserves local synced entries until the remote history catches up.

Matching is done by:

- local id
- backend anky id
- or close enough timing/content identity

Then the merge preserves the useful local fields when the remote payload is incomplete:

- local id continuity
- prompt/content
- local artifacts already known

This is a core caching lesson:

- remote history is not always more correct in the moment
- sometimes local truth is newer

## 6. Profile now shows real ankys, not random writings

Open `Anky/AnkyProfileView.swift`.

The big change is that the screen no longer treats every cached writing as archive-worthy.

It now derives:

- `allSessions`
- `ankySessions`
- `latestAnkyImageURL`

Then the hero, map, stats, calendar, and tap targets are all based on `ankySessions`.

That means:

- short sessions do not masquerade as real ankys
- the latest anky image can drive the hero
- the archive feels like one coherent surface

This is a good SwiftUI architecture habit:

- derive filtered collections once near the top of the view
- reuse them everywhere

That keeps the whole screen consistent.

## 7. Tapping an anky should reopen a thread, not a flat record

The detail UI now routes from `AnkyProfileView` into `AnkyThreadView` in `Anky/ProfileView.swift`.

`AnkyThreadView` already knew how to show:

- the image
- the original writing
- the initial reflection
- later follow-up messages

But it only works if those later follow-up messages exist somewhere durable.

That is where `Anky/AnkyThreadChatStore.swift` comes in.

It is a small JSON-backed store in Documents:

- one file per anky id
- `load(ankyId:)`
- `append(ankyId:message:)`

Then `ChatViewModel.sendReply(_:)` in `Anky/AnkyChatView.swift` mirrors both sides of the quick-chat exchange into that store:

- the user's follow-up
- Anky's reply

So now the writing flow and the profile flow are connected:

1. user writes a real anky
2. `SealingView` submits it
3. chat receives writing + reflection + image
4. user keeps talking
5. those later messages are mirrored into `AnkyThreadChatStore`
6. profile can reopen that same anky as a conversation

That is the deeper product fix. The profile is no longer just a summary card. It is a doorway back into the thread that an anky created.

## 8. Backend relationships in this feature

Three backend surfaces matter here:

- `POST /api/anky/submit`
- `GET /swift/v2/writings`
- `POST /api/chat-quick`

Use this mental model:

- `/api/anky/submit` is the live creation stream
- `/swift/v2/writings` is the slower history truth
- `/api/chat-quick` is the follow-up conversation path

The iOS client now stitches those together with local persistence so the product still feels continuous even when the backend responses arrive at different times.

## 9. Common failure modes and how to debug them

### A. The reply never appears after sealing

Check:

- `Anky/SealingView.swift`
- whether `accepted` was received
- whether `handleStreamCompletionIfNeeded()` is running
- whether `fullReflection` was actually appended during `reflectionChunk`

If `accepted` exists but the UI is still spinning, the completion handling is the first place to inspect.

### B. A finished anky is missing from profile

Check:

- `AppState.recordWriting(...)`
- `WritingCacheStore.mergedEntries(...)`
- whether the capture qualifies locally
- whether the remote history endpoint is simply lagging

If the local entry exists but profile is empty, verify the item was classified as a real anky.

### C. A weird short session appears as a real anky

Check:

- `CachedWritingEntry.init(item:)`
- `LocalWritingCapture.qualifiesForAnky`

The client should reject that classification even if the backend sent `is_anky: true`.

### D. Thread detail opens with only the original reflection

Check:

- `ChatViewModel.sendReply(_:)`
- `lastWritingThreadID`
- `AnkyThreadChatStore`

If follow-up quick chat is happening but nothing is in the thread view, the mirroring step likely did not happen.

## 10. Try this yourself

1. Start a write and stop typing for 2 seconds. Confirm the top warning bar stays hidden.
2. Stop typing for 4 to 5 seconds. Confirm the bar appears and drains from right to left.
3. Write for more than 20 seconds. Confirm the timer row and red exit button are gone.
4. Finish a real anky. Confirm the app enters `SealingView`, then shows the reflection without getting stuck on dots.
5. Open profile. Confirm the new anky appears there even before a manual history refresh.
6. Tap that anky, send a follow-up quick-chat message, dismiss, and reopen it. Confirm the thread is still there.

That manual path teaches almost the whole system:

- SwiftUI view derivation
- UIKit text behavior inside SwiftUI
- async submit streams
- local-first cache merging
- profile/detail routing

That is the real lesson of this change: product feel depends on data truth.
