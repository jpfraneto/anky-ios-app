# Lesson 011: Chat Shell Header and the Native Generate Gallery

## Why this lesson exists

The main screen needed to stop feeling like a stack of special-purpose controls and start feeling like a normal chat app.

The active shell in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift) now does three simple things at the top:

1. left side opens the native `GenerateView`
2. center shows Anky's identity
3. right side opens the user's profile and archive

That sounds cosmetic, but it changes the app's navigation mental model in an important way.

## Mental model one: the header should explain the product in one glance

Open `ChatHeaderView` inside [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

The old shell exposed product internals too directly.
It made sense if you already knew the altar and the wider ritual system.
It did not read like a chat interface to a new user.

The new header is intentionally legible:

- `Generate` is an explicit action
- `Anky` is the conversation partner
- the user avatar is where history and personal archive live

That is a product lesson as much as an iOS lesson.
Top-level navigation should answer:

- where am I?
- what can I do from here?
- where is my stuff?

If the header cannot answer those quickly, the screen will feel noisy even if the code is clean.

## Mental model two: center alignment is a layout problem, not a branding problem

Look at the `HStack` in `ChatHeaderView`.

The center identity is not positioned with hard-coded offsets.
Instead the header uses three equal flexible regions:

- leading region for `Generate`
- center region for Anky
- trailing region for the profile button

That matters because SwiftUI layout should stay stable across:

- short names
- long localization
- different device widths
- different Dynamic Type settings

This is a useful SwiftUI rule:
if something must stay visually centered, give the surrounding zones symmetrical layout responsibility instead of nudging the middle view by hand.

## Mental model three: native screen, real backend contract

The generate route is no longer a Safari handoff.

Open:

- [GenerateView.swift](/Users/kithkui/Desktop/Anky/Anky/GenerateView.swift)
- [AnkyAPI.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyAPI.swift)
- [AnkyModels.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyModels.swift)

The native screen now talks to the same backend contract the web app uses:

- `POST /api/v1/generate`
- `GET /api/v1/anky/{id}`
- `GET /api/ankys?origin=generated`

That is the important architecture shift.
The iPhone app is no longer handing the user off to another surface for Flux generation.
It owns the full generation loop itself.

## Mental model four: a collage is just a data merge plus a grid

The gallery in [GenerateView.swift](/Users/kithkui/Desktop/Anky/Anky/GenerateView.swift) is intentionally simple.

It merges two sources:

- completed generations stored locally in [GeneratedAnkyStore.swift](/Users/kithkui/Desktop/Anky/Anky/GeneratedAnkyStore.swift)
- the broader generated feed from `GET /api/ankys?origin=generated`

Then it renders them in a three-column `LazyVGrid`.

This is a useful SwiftUI lesson.
You do not need a complex masonry engine to get a collage feeling.
If the content is image-first and the spacing is tight, a simple square grid already reads as a collage.

The important engineering work is not the grid itself.
It is:

- decoding mixed URL formats correctly
- deduplicating local and remote items by id
- polling pending generations until they become complete
- persisting enough local state to recover after dismissal or relaunch

## Mental model five: profile is not settings, it is the archive

The right side of the header opens [ProfileView.swift](/Users/kithkui/Desktop/Anky/Anky/ProfileView.swift).

This matters because the profile screen in Anky is not just account chrome.
It is where the user reads:

- generated ankys
- archived UTC chat days
- full writing sessions for a given day

So the header is not pointing at "settings."
It is pointing at "your accumulated interior record."

That is a product-structure lesson.
A navigation icon should map to the real user job, not the engineering category.

## Mental model six: keyboard overlap and slot stability both matter in a chat dock

The collapsed composer in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift) is supposed to behave like a normal chat dock:

- stay attached to the bottom edge
- rise only enough to clear the keyboard
- keep the header and message list readable
- keep the same left, center, and right control zones while the user types

That means the layout should use keyboard overlap, not a naive raw keyboard frame height.
It also means the dock should not gain and lose side buttons in ways that make the whole bar jump around.

The helper in [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift) now measures how much of the screen the keyboard actually covers.
`UnifiedInputView` then applies that value as bottom lift only in the docked state, while keeping a fixed mic slot on the left, the composer in the center, and the send action on the right.

This is an important iOS layout lesson:

- raw keyboard geometry can be misleading
- overlap with the visible screen is the value the view actually cares about
- normal chat bars feel stable because their control zones do not disappear and collapse the whole layout

If you use the wrong value, a docked composer can jump halfway up the screen and feel broken even when the rest of the chat UI is correct.
If you let the slots reflow every time text appears, the bottom bar can still feel broken even after the keyboard math is fixed.

## Mental model seven: async work should occupy visible space

Open [GenerateView.swift](/Users/kithkui/Desktop/Anky/Anky/GenerateView.swift) and look at `GenerateViewModel`.

There are two different waiting states in generation:

- the prompt is being sent to the backend
- the backend has accepted the job and is still rendering the image

If the UI only changes a button label for those states, the user will miss it.

The screen now uses one prominent activity card for both phases.
It shows:

- a spinner
- a headline with how many Ankys are in flight
- body copy explaining what the backend is doing
- the latest prompt preview
- placeholder collage tiles that occupy the same visual space the finished images will use

This is a good SwiftUI state-design lesson.
Async state should not only be textual.
It should take over the piece of layout the finished content will eventually inhabit.

## Mental model eight: saving a backend image to Photos is an iOS permission flow

Saving a generated image is not just "open a URL and hope."

The flow in [GenerateView.swift](/Users/kithkui/Desktop/Anky/Anky/GenerateView.swift) is:

1. get the normalized remote image URL from the generated Anky model
2. download the bytes with `URLSession`
3. confirm the bytes decode into a real `UIImage`
4. request `PHPhotoLibrary` add-only authorization
5. write the image data into the user's photo library

The matching permission string lives in [Info.plist](/Users/kithkui/Desktop/Anky/Info.plist).

This is an important native-app lesson.
When you move a feature from "the web app has this image" to "the phone owns this image," you usually cross a framework boundary:

- networking
- permissions
- a system-owned data store

## Swift and iOS concepts involved

- `@State` drives whether the generate route or profile sheet is shown
- `fullScreenCover` is used for the native generate route because it behaves like a top-level destination
- `sheet` is still appropriate for profile because it is a native secondary surface inside the app
- `Task.sleep` plus polling drives the generation lifecycle until the backend marks an item complete
- `AsyncImage` handles a remote user avatar when the backend provides one
- `LazyVGrid` renders the generated Anky collage
- `UserDefaults` stores pending and completed generated Ankys through a dedicated store
- keyboard notifications plus safe-area math keep the chat composer docked correctly while the system keyboard appears and disappears
- `PHPhotoLibrary` handles add-only permission and the actual save to the user's device
- `URLSession.shared.data(from:)` is used to download the remote generated image bytes before saving

This is one of the recurring iOS patterns in this repo:

- SwiftUI owns screen state and layout
- UIKit controllers are bridged in only where the native Apple API already solves the exact problem well

## How the files fit together

- [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift): owns the root chat shell, header, generate route cover, and profile presentation
- [GenerateView.swift](/Users/kithkui/Desktop/Anky/Anky/GenerateView.swift): owns prompt entry, Flux generation, polling, and the collage gallery
- [Info.plist](/Users/kithkui/Desktop/Anky/Info.plist): declares the Photos add-only permission text required for native image saving
- [GeneratedAnkyStore.swift](/Users/kithkui/Desktop/Anky/Anky/GeneratedAnkyStore.swift): persists pending generation ids and locally completed Ankys
- [ProfileView.swift](/Users/kithkui/Desktop/Anky/Anky/ProfileView.swift): owns writing history, archived-day browsing, and the support entry that still leads to the altar
- [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift): still owns the shared `KeyboardObserver` used by the chat shell and other writing surfaces
- [README.md](/Users/kithkui/Desktop/Anky/README.md): describes the current routed shell accurately for future work
- [CURRENT_STATE.md](/Users/kithkui/Desktop/Anky/CURRENT_STATE.md): records that the chat header no longer routes straight to the altar

## Data flow

The data flow is simple:

1. `AnkyChatView` reads `appState.user`
2. the header turns that into a visible avatar or fallback initial
3. tapping `Generate` presents `GenerateView`
4. `GenerateView` posts to `/api/v1/generate`
5. the screen shows a visible activity card immediately, even before the backend returns an id
6. the returned `ankyId` is stored as pending and polled through `/api/v1/anky/{id}`
7. completed items are merged into the local store and the public collage feed
8. tapping a collage tile opens the detail sheet, where the generated image can be saved to Photos
9. tapping the user avatar presents `ProfileView`
10. `ProfileView` reads `appState.writingHistory` and archived chat days to show writings for a given day

The important split is this:

- `AppState` still owns the main writing/archive state
- `GeneratedAnkyStore` owns local generation recovery
- `GenerateViewModel` owns the short-lived prompt/polling UI state

## Common failure modes

- If `/api/v1/generate` changes shape, the native screen can fail even though the header still opens correctly.
- If generated image fields alternate between absolute URLs, relative paths, and bare `.webp` filenames, images will silently disappear unless the normalization logic stays tolerant.
- If pending generation ids are not persisted, the user can dismiss the screen and lose track of generations that are still rendering on the backend.
- If local and remote gallery items are not deduplicated by id, the collage will show obvious duplicates after a poll completes and the public feed catches up.
- If `profileImageUrl` starts coming back as a relative path, avatar loading will fail unless the URL is normalized.
- If the chat dock uses raw keyboard frame height instead of overlap with the visible screen, the composer can jump upward and cover the header.
- If the collapsed dock changes width or drops controls as text appears, the bottom bar will feel unstable even when its vertical position is correct.
- If [Info.plist](/Users/kithkui/Desktop/Anky/Info.plist) does not include the Photos usage string, saving generated images will fail at runtime.
- If someone reintroduces more top-level actions into the header, the center identity will stop reading cleanly and the shell will drift back toward visual noise.

## Try this yourself

1. Open [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).
2. Find `ChatHeaderView` and trace the `fullScreenCover` that presents [GenerateView.swift](/Users/kithkui/Desktop/Anky/Anky/GenerateView.swift).
3. In `GenerateViewModel`, trace the path from `generate()` to `pollForGeneratedAnky(...)`.
4. Find the save-to-Photos path in `GeneratedAnkyDetailView` and trace it into `GeneratedAnkyPhotoLibrary`.
5. Find the local persistence in [GeneratedAnkyStore.swift](/Users/kithkui/Desktop/Anky/Anky/GeneratedAnkyStore.swift) and confirm you understand why pending ids and completed items are stored separately.
6. Change the collage grid from three columns to two and notice how much the screen's feeling changes even though the data flow stays the same.
