# 015 Seed Backup Sheet Layout

This lesson covers a small bug that matters because it lives inside a trust-critical identity flow.

The problem was simple:

- `SeedPhraseBackupView` looked fine on roomy screens
- but on smaller sheet heights the text and swipe control could overflow past the visible viewport
- that made the ceremony feel broken, and in some cases the user could not reach the swipe affordance at all

The fix lives in:

- `Anky/SeedPhraseBackupView.swift`

## 1. Mental model

The backup flow is not a static full-screen poster.

It is still normal app UI running inside:

- sheet presentation chrome
- safe areas
- variable device heights
- dynamic text wrapping

That means any "ceremonial" layout built with `VStack` and `Spacer()` still needs a fallback when the content becomes taller than the viewport.

If you do not provide that fallback, the screen will overflow.

## 2. What was wrong

Each backup phase was built as a plain `VStack`:

- intro
- reveal
- confirm
- done

Those stacks used `Spacer()` to create a calm vertically-centered composition.

That works only when the available height is large enough.

Once the sheet gets shorter, the stack has nowhere to put the extra content, so the bottom controls get pushed off-screen.

The real bug was not the text itself. The real bug was assuming a full-screen composition would always fit.

## 3. What changed

`SeedPhraseBackupView` now uses:

- `GeometryReader`
- `ScrollView`
- a `minHeight` based on the current viewport height

That combination does two important things at the same time:

1. when there is enough room, the phase still feels centered and spacious
2. when there is not enough room, the view becomes scrollable instead of overflowing

That is the right SwiftUI pattern for "centered when possible, scrollable when necessary."

## 4. Why `GeometryReader` is useful here

`GeometryReader` gives the current presented size of the sheet.

Then the phase content gets:

- a comfortable max width
- padding for breathing room
- a `minHeight` that roughly matches the visible viewport

So the same content can adapt to:

- large iPhones
- smaller iPhones
- shorter sheet heights

without needing separate hard-coded layouts.

## 5. Why this matters for product quality

This is identity UX.

If the backup flow overflows, the user does not experience "a small layout bug."

They experience:

- uncertainty around the recovery phrase
- confusion about whether the ritual is broken
- friction at the exact moment the app is asking for trust

That is why these bugs matter more than their code size suggests.

## 6. Try this yourself

Open `SeedPhraseBackupView.swift` and compare the old and new structure mentally:

1. find the root `GeometryReader`
2. find the `ScrollView`
3. find the `minHeight` frame
4. notice that the individual phase views still keep their calm `Spacer()`-based composition

That is the key lesson:

- do not throw away a good centered layout
- wrap it in a container that can degrade gracefully on smaller viewports
