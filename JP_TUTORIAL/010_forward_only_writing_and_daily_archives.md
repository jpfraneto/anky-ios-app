# Lesson 010: Forward-Only Writing, Live Recovery, and Daily Archives

## Why this lesson exists

The active writing route changed again.

The routed product surface is now:

1. a chat-first shell in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift)
2. one bottom composer that starts like a normal chat input
3. the same composer growing into full writing after 8 seconds of continuous typing
4. a forward-only rule set enforced by UIKit, not by hope
5. live autosave on every keystroke
6. a post-write sequence of raw writing, reflection, then image
7. a profile screen that acts as the archive for past sessions and past UTC days

This lesson explains the mental model behind that refactor and the iOS concepts it uses.

## Mental model one: one text view owns both chat and writing

Open `UnifiedInputView` inside [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

The important decision is that the app does not create:

- one `TextEditor` for chat
- then a second `TextEditor` for full writing

Instead it keeps one `AnkyComposerTextView` in the hierarchy and changes its layout around it.

That matters because the composer itself is the stateful object.

UIKit text views remember things SwiftUI views do not:

- first-responder status
- selection state
- keyboard attachment
- composition behavior

If you throw away the text view during the transition, you risk:

- losing focus
- jumping the cursor
- dropping typed text
- flickering when the keyboard reconnects

The active route avoids that by keeping one composer and animating the container state with:

- `isAnkyModeActive`
- `isMilestoneCelebrating`
- a spring animation on the shell

That is the real architecture lesson.
When the input control is the thing the user is bonded to, preserve the control and move the layout around it.

## Mental model two: SwiftUI arranges the screen, UIKit enforces the hard input rules

Open [AnkyComposerTextView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyComposerTextView.swift).

This file is the enforcement layer.

`AnkyComposerTextView` is a `UIViewRepresentable` wrapper around `LockedComposerTextView`, which is a custom `UITextView`.

The reason to drop to UIKit is simple:

SwiftUI's `TextEditor` does not give enough control to safely enforce Anky mode.

The current rules live in UIKit:

- `autocorrectionType = .no`
- `spellCheckingType = .no`
- `autocapitalizationType = .none`
- `keyboardType = .alphabet`
- empty `inputAssistantItem` groups to remove the QuickType bar
- `shouldChangeTextIn` blocks deletion, newline insertion, and mid-string edits
- `deleteBackward()` is overridden to do nothing
- paste and cut are blocked

That is a useful iOS lesson:

- SwiftUI is excellent for composition and state-driven layout
- UIKit is still the right tool when you need strict text-input behavior

Do not force everything into pure SwiftUI when the platform already has a lower-level API built for the job.

## Mental model three: the writing layout is just state, not a second screen

Stay in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift) and read:

- `ChatViewModel`
- `UnifiedInputView`
- `IdleProgressBar`
- `ChakraProgressBar`
- `MilestoneCelebrationOverlay`

The writing surface is defined by layout state:

- collapsed composer when `isExpanded == false`
- full writing surface when `isExpanded == true`

The exact layout is:

1. top idle bar
2. full-height writing area
3. bottom 8-minute progress bar
4. countdown label
5. keyboard

Notice what makes this work:

- `GeometryReader` measures the available height
- keyboard height comes from `KeyboardObserver` in [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift)
- the outer container uses `ignoresSafeArea(.keyboard, edges: .bottom)`
- `bottomInset` is computed manually so the text area really fills the space above the keyboard

This is a strong SwiftUI layout lesson.
If keyboard-safe layout matters, do not assume SwiftUI will infer the exact geometry you want.
Measure it and drive the layout explicitly.

## Mental model four: live recovery is a small state snapshot, not a full session replay

Open [WritingSessionStore.swift](/Users/kithkui/Desktop/Anky/Anky/WritingSessionStore.swift).

The new type to notice is:

- `LiveWritingSessionSnapshot`

It stores only the minimum data needed to recover the active draft:

- `sessionId`
- `text`
- `sessionElapsed`
- `keystrokeDeltas`
- `updatedAt`

`scheduleLiveSave(...)` debounces writes to 500ms.

That means the app can save on every keystroke without hammering `UserDefaults` and disk on every single character.

Open `scheduleLiveSnapshot(updatedAt:)` and `restoreLiveSessionIfNeeded()` in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

That is where the live session connects back to the routed UI:

- typing schedules a save
- app foreground / initial appearance tries to restore
- successful send or discard clears the live snapshot

This teaches an important product-engineering principle.
For recovery, you usually do not need to serialize the whole view tree.
You need the smallest durable snapshot that can recreate the user-facing state.

## Mental model five: 8 minutes is both product meaning and state transition

Look at `sessionTick(at:)` and `runMilestoneSequence()` in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

There are three distinct timers now:

- the 8-second idle countdown
- the 8-second threshold before the composer expands
- the 8-minute writing goal

When `sessionElapsed >= 480`, the code does not immediately jump straight into the backend call.

It first flips:

- `didTriggerMilestone`
- `isMilestoneCelebrating`
- `milestoneSequenceID`

Then the view layer shows the overlay and the haptic sequence.
Only after that does `finishMilestoneCelebrationAndSend()` call `sendToAnky()`.

That is a good state-machine lesson.
User meaning often requires an intermediate state.

If you skip that explicit milestone state, you either:

- lose the emotional beat
- or jam timing logic into side effects that are hard to reason about

## Mental model six: post-write chat is a delivery pipeline, not one big message dump

Read:

- `sendToAnky()`
- the `.task(id: viewModel.pendingCapture?.sessionId)` block
- `deliverWritingOutcome(reflection:imageURL:)`
- `MessageRow`
- `UserMessageView`
- `AnkyImageMessageView`

The current sequence is intentional:

1. the user's raw writing is appended immediately as their own message bubble
2. that bubble exposes a visible `COPY` button
3. the app submits through the existing `/swift/v2/write` path
4. the app polls writing status
5. the reflection is cached into local history and appended to chat
6. the image is cached and appended as its own fixed-height bubble

This teaches two useful ideas.

First: UI messages and persistence updates are separate responsibilities.

- chat bubbles are immediate UI state
- `WritingCacheStore.updateGeneratedArtifacts(...)` updates durable writing history

Second: asynchronous output can arrive in phases.

The app does not pretend reflection text and image art are one payload that must appear together.
It models them as separate arrivals and keeps the chat timeline stable.

There is a backend-contract lesson inside this too.

The live status polling path and the later `/swift/v2/writings` history fetch are different integration surfaces.
If the mobile app only decodes one exact reflection key, profile can silently lose processed Ankys after relaunch even though chat looked correct right after send.

That is why [AnkyModels.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyModels.swift) now accepts:

- flat `response`
- flat `anky_reflection`
- flat `anky_title`
- flat `anky_image_path`
- or a nested `anky` object

The Swift lesson is simple:
when a mobile client depends on a live backend, decode the stable meaning of the payload rather than one brittle exact key layout.

## Mental model seven: daily reset means archive, not deletion

Open [ChatStore.swift](/Users/kithkui/Desktop/Anky/Anky/ChatStore.swift).

The key helpers are:

- `utcDayKey(for:)`
- `currentUTCKey(...)`
- `loadArchivedDays(...)`
- `messages(forDayKey:)`

The chat store now keeps one long persisted array, but it reads that array through a UTC-day lens.

That gives the product what it wants:

- a fresh current-day conversation
- older days preserved
- no destructive reset

Now open [ProfileView.swift](/Users/kithkui/Desktop/Anky/Anky/ProfileView.swift).

That file is the archive UI:

- `ProfileView` shows Anky's summary read on the user
- large image-first session cards come from `appState.writingHistory`
- `ArchivedChatDayView` opens previous UTC chat days
- `AnkyThreadView` shows the raw writing, reflection, and image for one session
- `ImagePrefetcher` warms the cache so image layouts stay stable

This is a good data-model lesson.
Resetting the visible conversation does not require deleting persistence.
It often just means querying the same persistence with a different slice.

One extra backend-contract lesson lives in [AnkyModels.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyModels.swift).

`WritingItem` now decodes processed Anky data from either:

- flat history keys like `anky_title` and `anky_image_path`
- or a nested `anky` object with `title`, `reflection`, and `image_url`

That matters because profile/history should survive backend payload evolution without silently dropping the most important processed fields.

## How data moves through the current feature

1. The user types into `AnkyComposerTextView` in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).
2. `UnifiedInputView` notices the first non-empty input and calls `beginSilentSession()`.
3. `handleKeyPress(...)` appends the character, updates timing state, and schedules a live snapshot in [WritingSessionStore.swift](/Users/kithkui/Desktop/Anky/Anky/WritingSessionStore.swift).
4. After 8 seconds of continuous writing, `isAnkyModeActive` flips and the same composer expands.
5. When the user crosses 8 minutes, `MilestoneCelebrationOverlay` runs and then `sendToAnky()` creates a `LocalWritingCapture`.
6. The app submits through `AnkyAPI.submitWriting(...)` in [AnkyAPI.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyAPI.swift).
7. The status poll returns reflection, title, and image data from `/swift/v2/writing/{sessionId}/status`.
8. [AppState.swift](/Users/kithkui/Desktop/Anky/Anky/AppState.swift) stores those artifacts back into [WritingCacheStore.swift](/Users/kithkui/Desktop/Anky/Anky/WritingCacheStore.swift).
9. `deliverWritingOutcome(...)` appends the reflection and image into chat in sequence.
10. [ChatStore.swift](/Users/kithkui/Desktop/Anky/Anky/ChatStore.swift) persists the current day while older UTC days remain archived for [ProfileView.swift](/Users/kithkui/Desktop/Anky/Anky/ProfileView.swift).

## Common failure modes and where to debug

### 1. Backspace starts working again

Check:

- `textView(_:shouldChangeTextIn:replacementText:)`
- `deleteBackward()`
- whether some new code path replaced `AnkyComposerTextView` with `TextEditor`

### 2. The composer loses text when it expands

Check:

- `UnifiedInputView`
- `sessionBinding`
- whether a second composer instance was introduced conditionally

### 3. Draft recovery stopped working

Check:

- `scheduleLiveSnapshot(updatedAt:)`
- `WritingSessionStore.scheduleLiveSave(...)`
- `restoreLiveSessionIfNeeded()`
- whether successful send / discard clears the snapshot too early

### 4. Images still shift the layout after load

Check:

- `AnkyImageMessageView`
- `sessionCard(_:)` in [ProfileView.swift](/Users/kithkui/Desktop/Anky/Anky/ProfileView.swift)
- whether the placeholder and final image use the same frame height

### 5. A new UTC day still shows yesterday's conversation

Check:

- `ChatStore.currentUTCKey()`
- `refreshConversationDayIfNeeded()`
- whether timestamps are being written in local time assumptions instead of simply stored as `Date`

## Try this yourself

1. In [AnkyComposerTextView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyComposerTextView.swift), temporarily return `true` for newline input and watch how quickly the writing surface stops matching the product rule.
2. In [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift), comment out `scheduleLiveSnapshot(updatedAt:)`, relaunch during a draft, and feel the difference between "session state" and "durable recovery."
3. In [ChatStore.swift](/Users/kithkui/Desktop/Anky/Anky/ChatStore.swift), print `currentUTCKey()` and compare it to your local calendar day so you can see why UTC rollover is a storage rule, not a UI guess.
