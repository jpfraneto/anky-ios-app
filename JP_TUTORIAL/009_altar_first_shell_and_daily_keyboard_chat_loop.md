# Lesson 009: Altar-First Shell, Daily Keyboard, and the Short-Write Chat Loop

Historical note: parts of this lesson describe an older routed shell. The current active writing route is covered in [010_forward_only_writing_and_daily_archives.md](/Users/kithkui/Desktop/Anky/JP_TUTORIAL/010_forward_only_writing_and_daily_archives.md).

## Why this lesson exists

The app no longer opens straight into writing.

The current product shape is:

1. the user lands on the altar
2. the altar holds the main mood and the burn flow
3. a bottom button asks Face ID to unlock writing
4. writing lives in a separate full-screen surface above the altar
5. short or unfinished writing falls into a simple chat with Anky instead of hard-resetting the user back to blank space

This lesson explains how that was built in the existing code rather than by creating a second app shell.

## Mental model one: keep the route stable, change the active shell

Start with [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift).

`ContentView` still routes both `.locked` and `.unlocked` into `AnkyChatView`.

That is important.

Instead of rewriting app-state routing, the code changes the meaning of `AnkyChatView` itself:

- before, it opened directly into the writing surface
- now, it renders the altar as the base layer
- the writing/chat experience is presented above that base layer only after the user unlocks it

This is a good SwiftUI architecture lesson. If the app already has one active shell wired into navigation, you often get a safer refactor by changing that shell's internal composition instead of rewriting the router.

Open [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

Look at:

- `AnkyChatView`
- `WritingExperienceContainer`
- `SimpleConversationView`

The altar is now always visible first. The writing surface is just another layer inside the same root view.

## Mental model two: Face ID is a gate, not the root screen

The altar footer button calls `BiometricLockManager.reauthenticate(reason:)`.

Open [BiometricLockManager.swift](/Users/kithkui/Desktop/Anky/Anky/BiometricLockManager.swift).

That object already knew how to:

- check whether biometry is available
- present Face ID / Touch ID
- remember whether the app is currently unlocked

The new shell uses that existing manager as a feature gate:

- the altar button is always present
- tapping it triggers biometric reauthentication
- if reauthentication succeeds, the writing surface is shown

This is a useful native-iOS lesson. Face ID does not need to be tied to app launch only. It can be reused as a feature-level privacy boundary inside the app.

## Mental model three: the writing surface is resumable state, not disposable UI

Look at `ChatViewModel` in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

Two new ideas matter:

- `hasActiveWritingContext`
- `shouldShowConversationSurface`

`hasActiveWritingContext` answers: "If I hide the writing sheet right now, is there still something alive that should resume later?"

That includes:

- an active writing session
- a paused session
- a short-write conversation
- a pending Anky reply
- a reply-ready conversation after a writing was sent

Because of that, the user can leave the writing surface and come back without the app blindly resetting them to a fresh blank state.

Notice how this connects to `setExternalPresentationActive(_:)`.

When the writing surface is hidden but the session still exists, the session timer is treated as externally covered. That pauses the idle logic instead of silently letting the session drift toward an unwanted pause state while the altar is visible.

That is the real lesson: view visibility and session state are not the same thing.

## Mental model four: the keyboard is themed by the day, not by the wallet

Open [AnkyTheme.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyTheme.swift).

There is now a shared helper:

- `Kingdom.ankyverseDay(for:calendar:)`

This derives the current Ankyverse kingdom from the local day-of-year modulo eight.

That is different from the existing wallet-derived kingdom mapping. The app still has both ideas:

- a user kingdom, derived from identity
- a kingdom of the day, derived from the calendar

The in-app writing keyboard now uses the kingdom of the day.

Open `WritingKeyboardView` in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

The keyboard now:

- shows the shared `SealView` above the keys
- includes comma and period keys
- includes a `123` / `ABC` symbols toggle
- keeps backspace visually disabled
- tints the keys and space bar with the current day's kingdom

This is a strong component lesson. The keyboard does not fetch calendar data itself. The root shell computes the day kingdom once and passes it down.

## Mental model five: the chat is a continuation of a writing, not a general inbox

Open `SimpleConversationView` and the related `ChatViewModel` properties in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

The important part is the boundary:

- a writing message with a `duration` marks the start of the thread
- `conversationMessages` slices the current-session messages from that writing onward
- `shouldShowConversationSurface` decides when the UI should stop showing the keyboard-only writing view and start showing the simple chat

The current behavior is:

1. the user writes
2. they seal to send
3. the writing is submitted through the existing `POST /swift/v2/write` path
4. the UI waits for Anky's response
5. the same surface becomes a minimal chat

This is not a second backend system. It is still grounded in:

- `POST /swift/v2/write`
- `GET /swift/v2/writing/{sessionId}/status`
- `POST /api/chat-quick`

That means the "chat interface" is really a continuation layer on top of the writing session, not a free-floating messaging product.

## Mental model six: the altar is now a real home screen

Open [AltarView.swift](/Users/kithkui/Desktop/Anky/Anky/AltarView.swift).

The altar view now supports a root mode:

- `isRootExperience`

In root mode:

- the close button is removed
- extra bottom space is reserved for the unlock button that lives in the shell above it
- the provided generated image is used as the full-screen background

This is a nice SwiftUI design pattern:

- one view owns the feature
- a small configuration flag changes whether it behaves like a modal screen or the root home surface

That lets the app keep one altar implementation instead of forking it into "landing altar" and "modal altar."

## How data and control move now

### Login to writing

1. `ContentView` routes into `AnkyChatView`.
2. `AnkyChatView` renders `AltarView(isRootExperience: true)`.
3. The bottom altar button calls `BiometricLockManager.reauthenticate`.
4. If Face ID succeeds, `presentWritingExperience()` shows the writing surface.
5. If there is no active writing context yet, `ChatViewModel.beginSession()` starts a fresh session.

### Writing to short-write chat

1. The user types with `WritingKeyboardView`.
2. The eight-second seal completes.
3. `ChatViewModel.sendToAnky()` captures the writing and marks whether it was shorter than the 8-minute goal.
4. The existing write submission path runs.
5. While the backend response is loading, the surface can already swap into the simple conversation state.
6. `deliverAnkyResponse(_:)` appends the assistant message.
7. The bottom input bar can send follow-up text through `sendReply(_:)`.

### Leaving and returning

1. The user taps the top-left `altar` button.
2. The writing surface is hidden.
3. The underlying `ChatViewModel` is not thrown away.
4. If there is active context, `setExternalPresentationActive(true)` prevents the timer from drifting while hidden.
5. Tapping the bottom altar button again returns to the same writing or conversation state.

## Common failure modes and where to debug

### 1. Tapping the altar button does nothing

Check:

- `unlockWritingExperience()` in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift)
- `reauthenticate(reason:)` in [BiometricLockManager.swift](/Users/kithkui/Desktop/Anky/Anky/BiometricLockManager.swift)
- whether the device actually has Face ID / Touch ID available

### 2. The user returns to the altar and the session keeps timing out in the background

Check:

- `syncExternalPresentationState()` in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift)
- `sessionTick(at:)`
- `isExternalPresentationActive`

The hidden writing surface should be treated like an external presentation when there is still active session state.

### 3. The keyboard shows the wrong daily color

Check:

- `Kingdom.ankyverseDay(for:calendar:)` in [AnkyTheme.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyTheme.swift)
- the device calendar and timezone
- the `dayKingdom` value passed from `AnkyChatView` into `WritingExperienceContainer` and `WritingKeyboardView`

### 4. The simple chat appears before any writing was sent

Check:

- `conversationMessages`
- `shouldShowConversationSurface`

The chat UI should only appear once there is a latest writing message anchoring the conversation.

## Try this yourself

1. In `WritingKeyboardView`, change the `spaceLabel` mapping for one kingdom and rebuild.
2. In `AnkyTheme.swift`, temporarily change `ankyverseDay` to use `(dayOfYear + 1) % 8` and watch the keyboard tint shift.
3. In `AnkyChatView`, comment out the `hasActiveWritingContext` check inside `presentWritingExperience()` and notice how reopening the writing surface always destroys the current thread. That is a good way to feel why state and presentation must stay separate.
