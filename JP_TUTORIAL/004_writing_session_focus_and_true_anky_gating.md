# 004 Writing Session Focus And True Anky Gating

This lesson explains the new writing flow that lives mostly in `Anky/AnkyWritingSession.swift`.

The important mental model is this:

1. The write screen is not a text editor anymore.
2. It is a state machine that uses a hidden text input to capture keystrokes while the visible UI stays focused on the present moment.
3. The app decides locally whether a finished session is only a local write or a real anky that should hit the backend.

## The state machine

The main state lives in `WritingFlowModel` inside `Anky/AnkyWritingSession.swift`.

It now has four phases:

1. `landing`
2. `writing`
3. `paused`
4. `complete`

Why this matters:

- `landing` shows only the minimal prompt state: `Write now` and `8 minutes`.
- `writing` drives the timer, idle drain, huge current glyph, and bottom ribbon.
- `paused` happens after the user loses the first life. The writing is frozen, but the session is still alive.
- `complete` is where the app decides whether to keep the session local or sync a real anky.

This is a useful Swift lesson: the UI is simpler when the model exposes explicit states instead of a pile of booleans that can combine in invalid ways.

## Hidden input, visible experience

Look at `Anky/AnkyComposerTextView.swift`.

The `UITextView` is still there because iOS keyboard handling is native and reliable, but it is now allowed to run in a visually hidden mode:

- text color becomes clear
- caret becomes zero-sized
- selection rectangles disappear
- paste items are discarded through `UITextPasteDelegate`
- the view still becomes first responder and still receives printable characters

That is the native iOS trick behind the experience:

- the keyboard and text entry remain real
- the visible writing surface is fully custom SwiftUI

This is a common iOS pattern. You keep UIKit around for the hard platform problem, then build the contemplative visual layer on top in SwiftUI.

It is also where the forward-only rule is enforced:

- `deleteBackward()` is overridden to do nothing
- `paste(_:)` and `paste(itemProviders:)` are overridden to do nothing
- `UITextPasteDelegate` returns `setNoResult()` for paste items
- `shouldChangeTextIn` only allows inserts at the very end of the document

That combination matters because blocking menu actions alone is not enough on iOS. Hardware shortcuts and item-provider-based paste paths can still try to inject text unless you close those UIKit paths explicitly.

## Keyboard-aware viewport

The visible stage now treats the keyboard as part of the layout, not as an overlay to ignore.

In `WritingsView` inside `Anky/AnkyWritingSession.swift`:

- the view listens for `UIResponder.keyboardWillChangeFrameNotification`
- it computes a `keyboardOverlap`
- it reserves bottom space for the keyboard plus the ribbon
- the glyph stage sizes itself from the remaining visible height

This mental model is important:

- the user is not writing into a generic full-screen canvas
- they are writing into the live viewport that remains after the keyboard takes its share

Why this matters in SwiftUI:

- `ignoresSafeArea` is not enough when a contemplative layout needs to feel centered above the keyboard
- sometimes you need to own the keyboard math directly and then drive the SwiftUI layout from that state

## Data that drives the writing visuals

Inside `WritingFlowModel`, a few computed properties now matter a lot:

- `idleDrainProgress`
- `glyphOpacity`
- `glyphFractureProgress`
- `rhythmMultiplier`
- `currentDisplayGlyph`
- `ribbonCharacters`

These are the bridge between raw input data and the visuals.

Examples:

- `idleDrainProgress` maps the 3s to 8s idle window to `0...1`
- `glyphOpacity` uses that same number so the glyph fades with the active heart
- `glyphFractureProgress` uses the same idle window so the crack effect and life drain stay synchronized
- `rhythmMultiplier` uses recent keystroke deltas to size the bottom ribbon

This is the main SwiftUI concept to learn here:

- do as much interpretation as possible in the model
- keep the view reading clean values like `opacity`, `fontSize`, or `characters`

That makes the view tree easier to reason about.

## Two lives and pause/resume

The life logic is handled in `loseLifeOrComplete()` inside `Anky/AnkyWritingSession.swift`.

Behavior:

1. During `writing`, if idle reaches 8 seconds, the app checks how many lives remain.
2. If there is still one extra life, it decrements the count and enters `paused`.
3. If there are no lives left to spend, the session finishes.

Resume has two paths:

- `resumeFromPauseManually(at:)` for tapping the `Continue` button
- `resumeFromPauseFromTyping(at:)` for the first printable key after pause

This split exists for a real reason:

- manual resume should restart the idle clock immediately
- typing resume should not lose the first character or count a fake long keystroke delta from the pause gap

That is a good example of why naming two different functions is better than trying to cram both behaviors into one vague `resume()`.

## Local-only vs backend-bound sessions

The product rule is now enforced locally.

The relevant code is spread across:

- `Anky/AnkyModels.swift`
- `Anky/AnkyWritingSession.swift`
- `Anky/AppState.swift`
- `Anky/WritingCacheStore.swift`
- `Anky/OfflineQueue.swift`

### Qualification

`LocalWritingCapture` in `Anky/AnkyModels.swift` defines:

- `requiredDurationForAnky = 480`
- `requiredWordCountForAnky = 300`
- `qualifiesForAnky(text:duration:)`

That means the native app no longer asks the backend whether a short session should sync.

### Completion path

In `submitFinishedCapture(appState:)`:

- short/incomplete captures are written locally with `syncState: .localOnly`
- true ankys call `AnkyAPI.shared.submitWriting(...)`
- offline true ankys are queued with `syncState: .pending`
- successful true ankys are stored as `syncState: .synced`

This is the architectural change that matters most:

- UI behavior and sync behavior are now aligned with the new product rule even though `/swift/v1/write` is still behind the web flow

### Legacy migration

Older app builds may already have short pending writes cached.

Two places handle that:

- `WritingCacheStore.migrateLegacyShortPendingWrites()`
- `PendingAction.isObsoleteShortWrite` in `Anky/OfflineQueue.swift`

Why both are needed:

- the cache migration changes old pending history entries to `localOnly`
- the offline queue filter prevents old short write payloads from continuing to sync

That is a useful systems lesson: when product logic changes, you often need migration for already-saved local state, not just new code paths.

## Localization

The new writing copy is centralized in `Anky/WritingExperienceStrings.swift`.

This file does three jobs:

1. defines the supported copy keys
2. stores the translated strings
3. picks a language based on `Locale.preferredLanguages`

Why that structure is useful for JP:

- you can inspect one file to see exactly what the write experience says
- the view code stays readable because it only asks for `copy[.continueAction]` or `copy[.wordsLabel]`
- adding or updating a translation is a data change, not a view rewrite

This is a pragmatic localization approach for a still-moving product surface.

## How data moves through the feature

From keyboard to backend:

1. `AnkyComposerTextView` receives printable text from UIKit.
2. `onUserInput` sends the latest string into `WritingFlowModel.handleInput(_:)`.
3. The model updates timer-related state, rhythm data, current glyph data, and pause/resume state.
4. When the session ends, the model creates a `LocalWritingCapture`.
5. If the capture is incomplete, `AppState.recordWriting(..., syncState: .localOnly)` stores it only on-device.
6. If it is a true anky, `AnkyAPI.submitWriting` sends it to `/swift/v1/write`.
7. After a successful real anky, `AppState.refreshUserProfile()` and `AppState.refreshWritings()` pull the latest backend state back into the app.

That round trip is the native-app contract with the backend system.

## Common failure modes

If something looks wrong, start here:

1. The first resumed character disappears.
   Check the difference between `resumeFromPauseFromTyping(at:)` and `resumeFromPauseManually(at:)`.

2. Short sessions are syncing.
   Check `submitFinishedCapture(appState:)`, `WritingCacheStore.migrateLegacyShortPendingWrites()`, and `PendingAction.isObsoleteShortWrite`.

3. The keyboard shows but nothing is visible.
   That is expected during writing now. Inspect `AnkyComposerTextView` and confirm `isVisuallyHidden` is intentional.

4. The ribbon size feels wrong.
   Check `rhythmMultiplier` and the `fontSize` passed into `WritingRibbonView`.

5. The current glyph fades at the wrong time.
   Check `idleDrainProgress`, `glyphOpacity`, and `glyphFractureProgress` together. They should all be driven by the same idle window.

6. The center glyph feels too low when the keyboard is open.
   Check `keyboardOverlap`, `keyboardBottomPadding(for:)`, and the `contentHeight` calculation in `WritingsView`.

7. New copy is not localized.
   Check `WritingExperienceStrings.current` and make sure the view uses copy keys instead of literal strings.

## Try this yourself

1. In `Anky/AnkyWritingSession.swift`, temporarily change `idleWarningStart` from `3` to `1.5`.
2. Run the app and feel how much more aggressive the drain becomes.
3. Change it back and notice how strongly product feel depends on tiny timing constants.

That is the core lesson of this feature:

- the feeling of the app comes from a few well-named pieces of state and timing, not from lots of UI chrome.
