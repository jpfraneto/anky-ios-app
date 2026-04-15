# 020 Settings Formalities and In-App Safari

This lesson covers a small feature that teaches an important SwiftUI product rule:

- system containers shape behavior

The user asked for legal/help buttons that look like the designed settings modal, not like default iOS settings rows.

That changed both:

- layout structure
- navigation behavior

The main files in this pass are:

- `Anky/SettingsView.swift`
- `Anky/AnkyProfileView.swift`

## 1. Mental model

The old settings screen used `Form`.

`Form` is fast to build, but it brings a strong opinion:

- grouped iOS settings chrome
- automatic row insets
- system section spacing
- cell behavior that looks like Apple Settings

That is useful when you want "device settings" energy.
It is wrong when you want Anky's quieter, cave-like surface.

So the real fix was not "add three more rows."

The real fix was:

- stop using the wrong container

`SettingsView.swift` now uses:

- a custom `ScrollView`
- manually grouped cards
- a dedicated header
- explicit row dividers

That gives the app control over spacing, corners, background color, and row density.

## 2. Why the links use an in-app Safari controller

The new formalities rows point at:

- `https://anky.app/terms-of-service.md`
- `https://anky.app/privacy-policy.md`
- `https://anky.app/faq.md`

Those pages are web documents, not native SwiftUI screens.

There are three common ways to open them:

1. `Link`
2. `openURL` to Safari
3. `SFSafariViewController`

This pass uses `SFSafariViewController` through `SettingsSafariView`.

Why?

- it keeps the user inside the app flow
- it gives a native browser with reader/cookie/share behavior
- it avoids building a custom web view stack for a simple document case

That is a common iOS pattern:

- SwiftUI owns the screen
- UIKit owns the specialized controller when Apple already provides one

## 3. The SwiftUI to UIKit bridge

`SettingsSafariView` is a `UIViewControllerRepresentable`.

That type exists for cases where SwiftUI needs to host a UIKit controller.

The data flow is simple:

1. `SettingsDocument` stores a title and URL
2. tapping a row sets `selectedDocument`
3. `.sheet(item:)` reacts to that optional value
4. SwiftUI presents `SettingsSafariView`
5. `SettingsSafariView` creates `SFSafariViewController(url:)`

This is the mental model JP should keep:

- SwiftUI state decides *whether* something is shown
- UIKit controller wrappers decide *how* a specialized native controller is rendered

## 4. How the settings rows are built now

`SettingsView.swift` now has a few reusable pieces:

- `settingsSection`
- `settingsCard`
- `settingsDivider`
- `sizeButton`

Those helpers are not "architecture for architecture's sake."

They exist because the screen has repeated visual rules:

- each section has a subtle label
- each section body is a rounded dark card
- rows need consistent horizontal padding
- dividers need a shared left inset

Once those rules repeat, extracting them makes the screen easier to read and harder to drift.

## 5. Font controls are a good SwiftUI state example

The settings screen still owns the same writing preferences:

- `@AppStorage("anky.writing.fontName")`
- `@AppStorage("anky.writing.fontSize")`

That means the storage model did **not** change.

Only the presentation changed.

This is an important lesson:

- storage state and layout state are different decisions

The font family rows and the custom plus/minus size control read and write the same persistent values as before.

So the user gets a different visual experience without any backend or persistence migration.

## 6. How this connects to the rest of the app

The active archive/profile flow lives in `AnkyProfileView.swift`.

That view opens settings with:

- `.sheet(isPresented: $showSettings) { SettingsView() }`

So the settings modal is part of the current routed product surface, not a dead legacy screen.

Inside `SettingsView.swift`, the other important connections are:

- `SeedPhraseBackupView` through `fullScreenCover`
- `AppState` for `hasBackedUpPhrase`
- `SeedIdentityManager` for the wallet address
- `@AppStorage` for writing preferences

This is a good example of a "composition screen":

- the view does not invent new business logic
- it composes existing app systems into one user-facing control surface

## 7. Common failure modes

If the legal/help links stop working, check these first:

1. The URL strings in `legalDocuments` are valid.
2. `selectedDocument` is being set on tap.
3. `.sheet(item:)` is still attached to `SettingsView`.
4. `SafariServices` is still imported.

If the settings styling regresses, check whether someone reintroduced `Form` or moved rows outside `settingsCard`.

If the wallet row stops updating, check the `onAppear` wallet load from `SeedIdentityManager.shared.walletAddress()`.

## 8. Try this yourself

1. In `SettingsView.swift`, change the card background color and see how much the overall mood shifts.
2. Replace the Safari sheet temporarily with `openURL` and notice how much rougher the flow feels when the app gets bounced out.
3. Add another document row using the same `SettingsDocument` pattern to practice data-driven SwiftUI sheets.

The main lesson from this pass is:

- choosing the right container is often more important than adding the next row
