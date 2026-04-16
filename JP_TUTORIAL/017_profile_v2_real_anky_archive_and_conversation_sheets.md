# 017 Profile V2, Real Anky Archive, and Conversation Sheets

Note as of April 16, 2026:
This lesson captures the first profile-v2 pass. The current profile runtime now reads primarily from `LocalArchiveRecord` rather than `AppState.writingHistory`. Read `025_runtime_cutover_local_archive_first.md` for the up-to-date archive/proof model.

This lesson explains the new active profile surface in `Anky/AnkyProfileView.swift`.

The important mental model is:

- profile is not a separate dashboard API
- profile is a lens over the phone's real local archive truth

That means the profile is built mostly from `AppState.writingHistory`, not from some independent backend payload.

The files in this pass are:

- `Anky/AnkyProfileView.swift`
- `Anky/AnkyAPI.swift`
- `Anky/AnkyModels.swift`
- `Anky/WritingCacheStore.swift`
- `Anky/AnkyThreadChatStore.swift`
- `Anky/AnkyTheme.swift`

## 1. Mental model

The user asked for a profile that feels like:

- a memory surface
- a map of past ankys
- a place to reopen the writing and the reflection

not a generic stats dashboard.

That changes the architecture.

The old way of thinking would be:

1. fetch profile data
2. fetch sessions
3. show some cards

The new way is:

1. take the cached writing archive that already powers the app
2. filter it down to real ankys
3. derive the profile views from that shared truth
4. let each anky reopen as a threaded conversation

That is why `AnkyProfileView` starts from:

- `appState.writingHistory`

and then computes:

- `sessions`
- `points`
- `level`
- `currentStreak`
- `avgFlowScore`
- `dominantKingdom`

This is a good SwiftUI habit:

- prefer derived view state from one trusted source
- avoid inventing a second source of truth just for one screen

## 2. The profile screen is a small state machine

At the top of `AnkyProfileView.swift`, look at the local state:

- `activeSection`
- `showSettings`
- `selectedAnky`
- `selectedKingdom`
- `selectedDay`

Those five values drive almost the whole screen.

That is the SwiftUI pattern here:

- `@State` stores navigation and temporary UI selection
- computed properties derive the visible content
- `.sheet(item:)` turns selected models into bottom sheets

The three big content modes are represented by:

- `ProfileSection.ankys`
- `ProfileSection.streak`
- `ProfileSection.words`

This is cleaner than a bunch of booleans because:

- only one section can be active at a time
- the active state is type-safe
- the button row and the content switch can both read the same enum

## 3. A profile session is just a projection of `CachedWritingEntry`

The struct `ProfileAnkySession` is the core adapter.

It wraps one `CachedWritingEntry` and gives the profile screen the fields it actually needs:

- title
- kingdom
- image URL
- date labels
- word count
- completeness
- seal state
- flow score
- preview text

That is a strong design move.

Instead of teaching the whole view tree about raw cache details, the screen builds one profile-focused model on top of the shared cache model.

This teaches an important Swift idea:

- your app model and your screen model do not have to be identical

`CachedWritingEntry` is the persistence shape.
`ProfileAnkySession` is the presentation shape.

## 4. Why metadata preservation matters

The territories view depends on metadata like:

- `flowScore`
- `kingdom`
- `energy`
- `reason`

Those values come from backend history decoding in `Anky/AnkyModels.swift`, specifically `WritingItem`.

Then they have to survive:

- conversion into `CachedWritingEntry`
- local cache updates
- remote/local merge passes

That is why this session also touched:

- `WritingItem`
- `CachedWritingEntry.init(item:)`
- `WritingCacheStore`

If those fields get dropped during a cache rewrite, the profile breaks in subtle ways:

- territories go blank
- average flow becomes wrong
- dominant kingdom becomes wrong

This is a useful lesson for JP:

- UI bugs often start as data-shape bugs

The territory screen is only as good as the archive model underneath it.

## 5. The ankys list, calendar, and territories are three views over the same archive

The three sections are not separate systems.

They are three projections of the same `sessions` array.

### Ankys list

`ankyListSection` is the most direct projection:

- one row per real anky
- image
- title
- short date
- writing preview

The row is `ProfileAnkyCardRow`.

### Calendar

`calendarSection` groups those same sessions by day in UTC using `ProfileCalendarContext`.

That matters because the app's chat/archive system already thinks in UTC days.

So the profile calendar should use the same day boundary or the archive will feel inconsistent.

When the user taps a day:

- `selectedDay` changes
- the matching ankys appear below the grid

That is a good example of lightweight drill-down without navigation.

### Territories

`territoriesSection` uses the same sessions again, but groups them by `kingdom`.

Then it shows:

- average flow score
- total sessions
- all eight kingdoms in a fixed order
- per-kingdom progress bars

This is why the screen feels coherent:

- one archive
- three lenses

## 6. Bottom sheets are the right iOS pattern here

The user asked for slide-up detail, not push navigation.

SwiftUI gives you a clean way to model that:

- `.sheet(item: $selectedAnky)`
- `.sheet(item: $selectedKingdom)`

The profile uses:

- `.presentationDetents([.large])` for conversation
- `.presentationDetents([.medium])` for kingdom detail

That keeps the user inside the profile context.

They are still "in the archive", just zoomed into one memory.

This is the conceptual difference between:

- navigation to another screen
- presentation of a detail layer

For this product, the sheet is better because the archived anky should feel like something surfacing from below, not like leaving the archive entirely.

## 7. How the conversation sheet is built

`ProfileConversationSheet` reconstructs the thread in layers:

1. the original writing becomes the first user bubble
2. the stored reflection becomes the first anky bubble
3. `AnkyThreadChatStore` adds any later local follow-ups

That is the initial display state.

Then the inline reply bar lets the user keep going.

When the user sends:

1. the message is appended locally
2. it is persisted in `AnkyThreadChatStore`
3. the UI shows typing
4. the sheet tries to fetch a reply

The reply path is important:

- if `session.entry.ankyId` exists, it calls `AnkyAPI.continueAnkyConversation(...)`
- if that fails or there is no backend anky id, it falls back to `AnkyAPI.chatQuick(...)`

That is a pragmatic client design.

It supports the cleaner backend route for real archived ankys without breaking older or locally reconstructed cases.

## 8. Why auto-scroll needs `ScrollViewReader`

The conversation sheet uses:

- `ScrollViewReader`
- a bottom anchor id
- `syncBottom(proxy:)`

The job is simple:

- when the sheet opens, show the newest part of the thread
- when the user sends, stay at the bottom
- when Anky starts typing or finishes replying, stay at the bottom

The double-scroll pattern in `syncBottom(proxy:)` exists because SwiftUI often needs one pass to lay out the new content and another pass to settle the final height.

That is a normal SwiftUI debugging lesson:

- state updates happen first
- final geometry arrives a moment later

If scrolling depends on final geometry, sometimes you need two passes.

## 9. Why the colors live in the theme

The profile spec introduced a clearer palette:

- `ankyBg`
- `ankyCardBg`
- `ankyBorder`
- `ankyTextPrimary`
- `ankyTextSecondary`
- `ankyTextMuted`
- `ankyTextDim`
- `ankyDivider`

Those live in `Anky/AnkyTheme.swift`.

That matters because the profile is not supposed to become a one-off file full of hardcoded colors.

A theme extension gives you:

- consistent color meaning
- easier reuse
- cleaner view code

This is the difference between:

- styling a screen
- extending the design system

## 10. Data flow summary

The full archive/profile flow now looks like this:

1. `AppState` refreshes writing history
2. `WritingItem` decodes backend history including reflection/image/kingdom/flow metadata
3. `CachedWritingEntry` stores that in the local archive
4. `AnkyProfileView` filters to real ankys and derives profile stats
5. the user opens one of three archive lenses:
   - ankys list
   - calendar
   - territories
6. tapping an anky opens `ProfileConversationSheet`
7. the sheet rebuilds the thread from:
   - original writing
   - stored reflection
   - local follow-up archive
8. sending a new reply uses `/api/anky/{id}/conversation` when possible, otherwise `/api/chat-quick`
9. the new reply is stored locally so the thread can reopen later

That is the deeper architecture:

- profile is an archive browser
- conversation is an archive continuation

## 11. Try this yourself

1. Open `Anky/AnkyProfileView.swift` and trace how `activeSection` changes what `sectionContent` renders.
2. In `ProfileAnkySession`, comment out the custom `title` logic and see how quickly the UI becomes less readable without a screen-specific projection model.
3. In `Anky/AnkyModels.swift`, follow `WritingItem.init(from:)` and see which backend keys fill the profile metadata.
4. In `Anky/WritingCacheStore.swift`, find the places where cache updates now preserve `kingdom`, `energy`, and `reason`.
5. In `ProfileConversationSheet`, temporarily remove the bottom anchor scroll calls and watch how fast the sheet stops feeling like a chat interface.
6. Change the selected section animation duration and notice how much the perceived calmness of the screen depends on tiny timing choices.

The main lesson from this pass is:

- a good profile page is not a separate feature
- it is a readable projection of the app's existing truth
