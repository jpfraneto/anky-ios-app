# 016 Chat Scroll, Copy, Haptics, and Settings Polish

This lesson covers a set of small interaction fixes that all point at the same product rule:

- when the user acts, the interface should answer immediately

In Anky, that matters because the product is not supposed to feel like a dashboard.

It should feel:

- present
- calm
- responsive
- trustworthy

The fixes in this pass live in:

- `Anky/AnkyChatView.swift`
- `Anky/MeditationTimerView.swift`
- `Anky/SettingsView.swift`
- `Anky/ProfileView.swift`
- `Anky/SeedPhraseBackupView.swift`

## 1. Mental model

There are two kinds of feedback in iOS UI:

1. visual state changes
2. tactile state changes

If either one is late, the user feels lag even if the code is technically correct.

That is what was happening here:

- chat could land a new message without visibly pinning to the newest content
- copy feedback appeared far away at the top of the screen instead of where the tap happened
- some important thresholds had no haptic answer
- closing the writer waited too long to hide the keyboard
- recovery presentation inherited a cramped sheet container instead of owning the screen

None of those were backend problems.

They were interaction-contract problems.

This also applied to the chat-to-writing handoff:

- the writer was entering in two beats instead of one

The old path inserted a full-screen shell first, then faded its content in later.

That technically worked, but it felt like a glitch because the user briefly saw a blank intermediate state.

## 2. Bottom-pinned chat is a layout contract

`MessageListView` in `AnkyChatView.swift` now treats "latest message visible" as a requirement, not a best effort.

The key pieces are:

- `ScrollViewReader`
- a dedicated bottom anchor id
- `.defaultScrollAnchor(.bottom)`
- a `syncBottom(proxy:)` helper that scrolls twice

Why scroll twice?

Because SwiftUI layout and async message updates do not always settle in a single pass.

The first scroll catches the current layout.
The second `DispatchQueue.main.async` scroll catches the next layout pass after:

- a new message appears
- the typing indicator appears
- bottom inset changes with keyboard/safe area state

That is a common SwiftUI pattern when the UI depends on "final laid out size" instead of just raw state changes.

## 3. Inline copy feedback is local state, not global toast state

The sent-writing bubble uses `UserMessageView`.

Instead of publishing a top-of-screen toast, the copy button now owns its own tiny piece of state:

- `@State private var didCopy = false`

When the user taps copy:

1. the text goes to `UIPasteboard`
2. haptics fire
3. the same button changes from `copy` to `copied`
4. a short delayed reset returns it to normal

That is the right mental model:

- local interaction
- local feedback

The user should not have to move their eyes to another part of the screen to confirm a tap that already happened under their thumb.

## 4. Haptics should mark thresholds, not everything

The new haptic additions all live under `AnkyHaptics` in `AnkyChatView.swift`.

That is useful because it creates one product vocabulary for touch feedback.

This pass added haptics for:

- opening writing mode
- starting the meditation timer
- the final second before idle timeout
- copy confirmation

Notice the pattern:

- these are threshold moments
- they are not random decoration

That is the right way to use iOS haptics in a contemplative product.

They should mark state transitions the body can feel before the mind fully parses the UI.

## 5. Immediate keyboard dismissal needs UIKit, not just SwiftUI focus

SwiftUI focus state alone can feel delayed when dismissing a text input that is deeply integrated into a custom screen.

So `AnkyModeView` now does both:

- `isWritingFocused = false`
- `UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)`

That second line is the important piece.

It reaches into UIKit's responder chain and tells the current first responder to resign immediately.

Mental model:

- SwiftUI focus is declarative intent
- `sendAction` is an imperative "do it now"

Sometimes you need both.

## 6. Settings previews should show the real current value

In `SettingsView.swift`, the font picker previously showed sample text at a fixed size.

That meant the font family changed, but the preview did not reflect the user's actual font-size setting.

Now the preview rows use:

- `fontForName(option.name, size: CGFloat(writingFontSize))`

That is a simple but important lesson:

- preview UI should render from the same source of truth as the actual feature

If the preview is disconnected from live state, it teaches the user the wrong thing.

## 7. Recovery should own the screen when trust is on the line

The recovery phrase flow already had a scroll-safe internal layout from the previous fix.

But the user still found a clipped version when opening it from settings.

The missing piece was presentation style.

`SettingsView` and `ProfileView` now use:

- `.fullScreenCover`

instead of:

- `.sheet`

That matters because the recovery ritual is not just another tiny settings pane.

It is identity-critical UI.

When the container is wrong, even a good internal layout can still feel broken.

The product lesson is:

- important ritual screens should control their own viewport

## 8. Data flow summary

The chat-side flow now looks like this:

1. user sends or receives a message
2. `MessageListView` observes message/typing/inset changes
3. the scroll view re-pins to the bottom anchor
4. if the user copies a sent writing bubble, `UserMessageView` handles the visual state locally and `AnkyHaptics` handles the tactile confirmation

The writer-close flow now looks like this:

1. user taps the red close button
2. `handleCloseButton()` runs
3. keyboard is dismissed immediately through the responder chain
4. the writing flow either exits or sends, depending on session state

The recovery flow now looks like this:

1. settings/profile opens backup
2. the app presents a full-screen cover
3. `SeedPhraseBackupView` still manages internal scroll safety for smaller heights
4. the ceremony remains reachable across device sizes

## 9. Try this yourself

Open the files and trace these small systems:

1. In `AnkyChatView.swift`, find `syncBottom(proxy:)` and follow where it is called.
2. In `UserMessageView`, find `didCopy` and notice that copy feedback does not need global app state.
3. In `AnkyModeView`, compare `isWritingFocused = false` with `sendAction(...resignFirstResponder...)`.
4. In `AnkyChatView.swift`, compare the writer insertion transition with the removed staged opacity/morph approach and notice why one continuous motion feels calmer than a blank intermediate frame.
5. In `SettingsView.swift`, change the `Stepper` value and watch how the sample rows now reflect the same size immediately.
6. In `ProfileView.swift` and `SettingsView.swift`, compare `.sheet` versus `.fullScreenCover` and ask which one matches an identity ritual better.

That is the deeper lesson from this pass:

- polish is often just architecture at the scale of one interaction
