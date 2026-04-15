# 021 Writer Dismissal And First-Responder Races

## Mental model

The active writing surface in Anky is not a pure SwiftUI text field. It is a custom UIKit `UITextView` wrapped in SwiftUI through `UIViewRepresentable`.

That matters because closing the writer is really two systems moving at once:

1. SwiftUI removes `AnkyModeView` from the view tree.
2. UIKit tears down the keyboard and first-responder state for the embedded `UITextView`.

If those two moves happen in the wrong order, you can crash. That is what happened when the red close button was tapped on the untouched writing overlay.

The bug was not about backend logic or writing persistence. It was a view-lifecycle bug.

## What changed

The fix lives in two files:

- `Anky/AnkyChatView.swift`
- `Anky/AnkyComposerTextView.swift`

### In `AnkyChatView.swift`

`AnkyModeView.handleCloseButton()` now does two important things before dismissing the overlay:

1. It ends editing on the current key window with `endEditing(true)`.
2. It defers the actual exit/send action to the next main-loop turn with `DispatchQueue.main.async`.

Why this helps:

- `endEditing(true)` tells UIKit to resign the active text view cleanly.
- Waiting one run-loop turn gives UIKit a chance to start that resignation before SwiftUI removes the whole writing overlay.

That is a classic iOS mental model: if a control is actively editing, do not rip the view hierarchy out from under it in the same breath unless you are sure the responder chain is already settled.

### In `AnkyComposerTextView.swift`

The deeper fix is in the `UIViewRepresentable` bridge.

Before this change, `updateUIView` could schedule async `becomeFirstResponder()` or `resignFirstResponder()` work. If the writer closed in the middle of that, old async work could still fire after the overlay was already disappearing.

The wrapper now:

- tracks focus sync requests with an incrementing token
- cancels stale pending focus work
- resigns first responder inside `dismantleUIView`
- clears delegates during teardown
- avoids moving the caret when the text view is no longer attached to a window

This is the key SwiftUI/UIKit concept:

`UIViewRepresentable` is not just "render a UIKit view." It is a lifecycle bridge. If you schedule async UIKit work, you are responsible for cancelling or invalidating it when SwiftUI decides that view is gone.

## Swift and iOS concepts involved

- `UIViewRepresentable`: lets SwiftUI host a UIKit view
- `Coordinator`: the bridge object that owns delegate callbacks and imperative state
- first responder: the UIKit object currently receiving keyboard input
- `dismantleUIView`: SwiftUI's teardown hook for wrapped UIKit views
- main run loop: where UIKit keyboard and responder changes are processed
- `DispatchQueue.main.async`: a simple way to wait one turn of the main loop

## How data and control move now

1. The user taps the red close button in `AnkyModeView`.
2. `dismissWritingKeyboard()` marks the writer as unfocused and asks the key window to end editing.
3. The actual close/send action is deferred one main-loop turn.
4. SwiftUI begins removing `AnkyModeView`.
5. `AnkyComposerTextView.dismantleUIView` cancels any stale pending focus work and resigns the `UITextView` if needed.
6. No old `becomeFirstResponder()` request is allowed to re-fire after teardown starts.

## Why this structure exists

It may feel redundant to fix this in both places, but the two layers do different jobs:

- `AnkyChatView` sequences the product flow correctly.
- `AnkyComposerTextView` makes the UIKit bridge safe in general.

That is a good architecture rule for iOS:

- fix the user flow at the feature layer
- fix lifecycle hazards at the bridge layer

If you only do one of those, the same class of bug often comes back somewhere else.

## Common failure modes to watch for

- A `UIViewRepresentable` schedules async `becomeFirstResponder()` work and never cancels it.
- A wrapped UIKit view is removed while still being the first responder.
- A custom text view mutates selection or caret state after it has already left the window.
- A close button both dismisses the keyboard and removes the whole screen in the same synchronous path.

When debugging this class of bug, inspect:

- `updateUIView`
- `dismantleUIView`
- delegate callbacks like `textViewDidBeginEditing` and `textViewDidEndEditing`
- any `DispatchQueue.main.async` blocks touching responder state

## Backend connection

This fix does not change the backend contract directly. It protects the native container around the writing flow so the app can safely get back to chat, local autosave, and later `/api/anky/submit` work without dying during UI teardown.

That still matters to the system as a whole: if the shell crashes before the user can leave writing mode cleanly, local preservation and submission guarantees do not matter.

## Try this yourself

1. Open `Anky/AnkyComposerTextView.swift`.
2. Find `syncFocus` and `dismantleUIView`.
3. Trace how a focus request becomes invalid when `pendingFocusSyncID` changes.
4. Then open `Anky/AnkyChatView.swift` and follow `handleCloseButton()` into `dismissWritingKeyboard()`.
5. Ask yourself: which parts are product flow, and which parts are lifecycle safety?
