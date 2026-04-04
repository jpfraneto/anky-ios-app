# Lesson 006: Parent, Child Worlds, and `cuentacuentos`

## Why this lesson exists

Anky still begins with the parent's 8-minute writing practice.

What changed is what that writing can become.

Now the app has a second surface inside the same seed-backed account:

1. the parent writes
2. the backend turns some writing into a Spanish `cuentacuentos`
3. the child enters a separate local world protected by an emoji pattern

This lesson explains how that was added without replacing the original writing architecture.

## Mental model one: the child does not get a separate root seed

Start with [ChildIdentityDeriver.swift](/Users/kithkui/Desktop/Anky/Anky/ChildIdentityDeriver.swift).

The child identity is derived from the parent identity.

That means:

- the parent seed phrase is still the real root secret
- the child address is deterministic
- the app does not need a second seed phrase ceremony

The derivation rule in this app is:

- read the parent private key from Keychain
- compute `SHA256(parentWalletAddress + name + birthdate)`
- use that hash as a secp256k1 tweak against the parent private key
- derive the child wallet address from the resulting private key

That is why the exact string formatting matters.

In [CreateChildView.swift](/Users/kithkui/Desktop/Anky/Anky/CreateChildView.swift), the app formats `birthdate` once as `yyyy-MM-dd`. That exact string is used both:

- for deterministic address derivation
- for `POST /swift/v2/children`

If those strings ever drift apart, the same child would produce a different derived address.

## Mental model two: backend child profiles and local child locks are different concerns

Open:

- [AnkyModels.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyModels.swift)
- [AnkyAPI.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyAPI.swift)
- [ChildProfileStore.swift](/Users/kithkui/Desktop/Anky/Anky/ChildProfileStore.swift)

There are two different pieces of child state:

1. backend child profile state
2. local device lock state

Backend state is represented by:

- `ChildProfile`
- `CreateChildRequest`
- `createChild`
- `getChildren`

Local device state is represented by:

- `ChildProfileStore`
- the stored `emojiPattern`

This is a useful architecture lesson.

The backend needs to know:

- the child id
- the child name
- the birthdate
- the derived wallet address

The device also needs to know:

- the 12-emoji pattern used to open the child's world locally

That is why `ChildProfile` includes both network identity data and the emoji pattern, and why `ChildProfileStore` exists next to `WritingCacheStore`.

## Mental model three: the child creation flow is a state machine, not four separate screens

Open [CreateChildView.swift](/Users/kithkui/Desktop/Anky/Anky/CreateChildView.swift).

The file uses a local `Step` enum:

- `.name`
- `.birthdate`
- `.emojiPattern`
- `.confirmPattern`
- `.creating`
- `.success`

This is classic SwiftUI state-driven UI.

The view does not push through a complex navigation stack. Instead, one enum decides which part of the flow should be visible.

Why is that a good fit here?

Because the product rule is sequential and linear:

1. capture name
2. capture birthdate
3. capture the secret pattern
4. confirm the pattern
5. derive and save

That makes a simple enum easier to reason about than multiple routes.

The shared UI pieces live in [ChildWorldComponents.swift](/Users/kithkui/Desktop/Anky/Anky/ChildWorldComponents.swift):

- `ChildEmojiPalette`
- `EmojiSelectionGrid`
- `PatternSlotsView`
- `ShakeEffect`

This is a good example of small, justified reuse.

Both child creation and child unlock need the same emoji grid and slot rendering, so sharing those pieces keeps the rules consistent without creating a giant abstraction layer.

## Mental model four: the child world is a shell inside the parent shell

Open:

- [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift)
- [ChildShellView.swift](/Users/kithkui/Desktop/Anky/Anky/ChildShellView.swift)

`UnlockedShellView` now has a child-world tray below the existing tab bar.

That tray does three jobs:

- loads local child profiles from `ChildProfileStore`
- opens `CreateChildView` as a sheet
- opens `ChildShellView` full screen for one child

This is important product-wise.

The parent shell still owns the app.
The child world is not a peer app. It is a focused sub-world entered from the parent's unlocked state.

Inside [ChildShellView.swift](/Users/kithkui/Desktop/Anky/Anky/ChildShellView.swift), the state machine is intentionally small:

- `enteredPattern`
- `attemptCount`
- `isUnlocked`
- `readyStory`
- `history`
- `activeStory`

That means the child shell is easy to debug:

- before unlock, it is purely local pattern comparison
- after unlock, it becomes a simple story library

## Mental model five: `cuentacuentos` reuses the guidance player on purpose

Open:

- [GuidancePlaybackView.swift](/Users/kithkui/Desktop/Anky/Anky/GuidancePlaybackView.swift)
- [ChildShellView.swift](/Users/kithkui/Desktop/Anky/Anky/ChildShellView.swift)

The backend already returns `guidancePhases`, and the app already has a native playback engine for phase-based audio guidance.

So the app does not build a second audio player.

Instead, it adds:

- `GuidancePlaybackMode.cuentacuentos`
- a Spanish voice preference
- an `onFinish` callback

That callback is the connection point between playback and the backend:

1. `ChildShellView` presents `GuidancePlaybackView`
2. the story finishes
3. the callback calls `POST /swift/v2/cuentacuentos/:id/complete`
4. the child library refreshes

This is a strong lesson in reuse.

When the data shape already matches an existing engine, prefer extending that engine over cloning it.

## Mental model six: the parent `ANKYS` tab now has cross-surface meaning

Look again at [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift).

`PersistedAnkysView` now fetches:

- `getCuentacuentosReady(childId: nil)`
- `getCuentacuentosHistory(childId: nil)`

Then it maps stories by `writingId`.

That is how the `📖` indicator appears on a persisted writing card.

This matters conceptually:

- the parent writes in one place
- the child hears the transformed story in another place
- the parent history card is the bridge between them

In Swift terms, this is just a dictionary lookup.
In product terms, it shows that a writing has already propagated into the child's world.

## How data moves through this feature

Follow the full path:

1. The parent completes a real anky through the existing writing flow.
2. The backend can generate a `cuentacuentos` tied to that writing.
3. The parent creates a child profile in [CreateChildView.swift](/Users/kithkui/Desktop/Anky/Anky/CreateChildView.swift).
4. The profile is posted through [AnkyAPI.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyAPI.swift) and cached in [ChildProfileStore.swift](/Users/kithkui/Desktop/Anky/Anky/ChildProfileStore.swift).
5. The child enters [ChildShellView.swift](/Users/kithkui/Desktop/Anky/Anky/ChildShellView.swift) and unlocks locally with the emoji pattern.
6. The child shell fetches ready and historical stories from `/swift/v2/cuentacuentos/*`.
7. Playback runs through [GuidancePlaybackView.swift](/Users/kithkui/Desktop/Anky/Anky/GuidancePlaybackView.swift).
8. Completion is posted back to the backend.

That is a complete feature loop across:

- SwiftUI state
- Keychain-backed identity
- deterministic crypto
- local persistence
- async networking
- native speech playback

## Common failure modes and how to debug them

### Child address changes unexpectedly

Check:

- the `name` normalization in [CreateChildView.swift](/Users/kithkui/Desktop/Anky/Anky/CreateChildView.swift)
- the `birthdateFormatter`
- the salt input construction in [ChildIdentityDeriver.swift](/Users/kithkui/Desktop/Anky/Anky/ChildIdentityDeriver.swift)

If any of those strings change, deterministic derivation breaks.

### Child creation succeeds on the backend but does not appear in the shell

Check:

- whether `ChildProfileStore.add` ran
- whether `UnlockedShellView.reloadChildProfiles()` was called after sheet dismissal

### The child cannot unlock their world

Check:

- the stored `emojiPattern` in `ChildProfile`
- whether the pattern comparison in [ChildShellView.swift](/Users/kithkui/Desktop/Anky/Anky/ChildShellView.swift) is evaluating the correct index

### Story playback works but completion never lands

Check:

- the `onFinish` callback in [GuidancePlaybackView.swift](/Users/kithkui/Desktop/Anky/Anky/GuidancePlaybackView.swift)
- the `completeCuentacuentos` call in [ChildShellView.swift](/Users/kithkui/Desktop/Anky/Anky/ChildShellView.swift)
- whether the session finished naturally or the user closed it early

### Spanish narration sounds wrong

Check the `preferredVoiceLanguages` for `.cuentacuentos` in [GuidancePlaybackView.swift](/Users/kithkui/Desktop/Anky/Anky/GuidancePlaybackView.swift).

That is where the player now prefers Spanish system voices.

## Try this yourself

1. Put a breakpoint in `CreateChildView.createChild()`.
2. Create a child twice with the same name and birthdate.
3. Confirm that the derived wallet address is identical both times.
4. Change only the birthdate and confirm the derived address changes.
5. Put a breakpoint in `ChildShellView.refreshLibrary()` and watch the flow from local unlock into backend story fetch.

That exercise will teach you the boundary between:

- local deterministic identity work
- local device-only child locking
- backend profile and story state
