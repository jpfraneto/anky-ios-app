# Lesson 002: Legacy Privy Auth, Callback Schemes, and Backend URL Boundaries

This lesson is historical context for the older mobile auth path.

Current product work uses local seed identity plus `/swift/v2/*`, not Privy-first onboarding. For the active auth model, read [005_seed_identity_and_v2_unlock_model.md](/Users/kithkui/Desktop/Anky/JP_TUTORIAL/005_seed_identity_and_v2_unlock_model.md).

`PrivyAuthService.swift` and the callback-scheme setup still exist in the repo because older surfaces still compile, but they are no longer the primary shell described by the README.

## Why this lesson exists

The Anky auth flow has two separate handoffs:

1. Privy proves who the user is.
2. Anky's backend turns that Privy token into the app session.

If either boundary is wired incorrectly, login fails even if the UI looks fine.

This lesson maps the exact code path for email, Apple, and Google sign-in in the current app.

## The mental model: auth is two systems, not one

Start with [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift).

The signed-out screen does not talk to the backend directly. It first talks to `PrivyAuthService`, which wraps the native Privy SDK.

Then `AppState` exchanges the returned Privy access token for the Anky backend session.

That means the auth pipeline is:

1. User enters email code or taps Apple/Google.
2. [PrivyAuthService.swift](/Users/kithkui/Desktop/Anky/Anky/PrivyAuthService.swift) gets a Privy access token.
3. [AppState.swift](/Users/kithkui/Desktop/Anky/Anky/AppState.swift) calls `signIn(withPrivyToken:)`.
4. [AnkyAPI.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyAPI.swift) sends `POST /auth/privy`.
5. Backend returns the app session token.
6. `KeychainHelper` stores that session token securely.
7. `AppState` refreshes `/me` and the signed-in shell appears.

If you remember only one thing, remember this:

- Privy identity is not the same thing as the app session.

## The SwiftUI side: the auth screen is local state plus app state

Inside [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift), `AuthExchangeView` owns short-lived UI state:

- `email`
- `code`
- `pendingEmail`
- `statusMessage`
- `isSubmitting`
- `focusedField`

That is view-local state because it only matters while the auth form is on screen.

But the real login result lives in shared app state:

- `appState.authStatus`
- `appState.authError`

That split is a common SwiftUI pattern:

- local `@State` for temporary form behavior
- shared observable state for app-wide truth

## The backend boundary: URL construction matters more than it looks

Look at [AnkyAPI.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyAPI.swift).

This file now normalizes the base URL as:

- `https://anky.app/swift/v1/`

That trailing slash matters.

Before this fix, paths like `"/auth/privy"` were being resolved incorrectly by Foundation URL rules and could collapse to:

- `https://anky.app/auth/privy`

That is a subtle but important lesson:

- URL joining is not string concatenation
- leading slashes and missing trailing slashes change the meaning
- if your base URL already contains a path component, relative URL behavior can surprise you

This is why [AnkyTests.swift](/Users/kithkui/Desktop/Anky/AnkyTests/AnkyTests.swift) now has a focused regression test for route resolution.

## The Privy boundary: OAuth needs a callback URL scheme

Now open [PrivyAuthService.swift](/Users/kithkui/Desktop/Anky/Anky/PrivyAuthService.swift).

Privy's OAuth API on iOS needs an app URL scheme so `ASWebAuthenticationSession` knows how to hand control back to Anky after Apple or Google finishes.

The important line is:

- `privy.oAuth.login(with:choice.provider, appUrlScheme: appURLScheme)`

That `appURLScheme` comes from the app bundle identifier.

The same scheme is registered in [Info.plist](/Users/kithkui/Desktop/Anky/Info.plist) under `CFBundleURLTypes`.

This teaches two iOS concepts:

1. Web-based native auth flows still need local app configuration.
2. Some runtime auth failures are really plist/configuration failures.

If the callback scheme is missing, the SDK cannot finish the OAuth round trip.

## Why the auth screen layout changed

The old auth screen used a `VStack` with spacers.

That is fine until the keyboard appears on a smaller iPhone. Then the bottom feedback text can be pushed off-screen, and the user cannot see the actual error that came back from Privy or the backend.

The new version in [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift) uses:

- `ScrollView`
- `ScrollViewReader`
- `@FocusState`
- a keyboard toolbar with a Done button

This is a useful SwiftUI mental model:

- forms that can grow should usually scroll
- number-pad flows should usually provide an explicit keyboard dismissal path
- status and error feedback should live close to the action that triggered them

## Common failure modes and how to debug them

### 1. Email code sends, but verify never logs in

Check these files:

- [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift)
- [AppState.swift](/Users/kithkui/Desktop/Anky/Anky/AppState.swift)
- [AnkyAPI.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyAPI.swift)

Questions to ask:

- Did Privy return an access token?
- Did `/auth/privy` hit the real `/swift/v1` route?
- Did Keychain store the backend session token?

### 2. Google or Apple opens, then fails immediately

Check these files:

- [PrivyAuthService.swift](/Users/kithkui/Desktop/Anky/Anky/PrivyAuthService.swift)
- [Info.plist](/Users/kithkui/Desktop/Anky/Info.plist)

Questions to ask:

- Is the callback scheme registered in `CFBundleURLTypes`?
- Is the same scheme passed into Privy login?

### 3. The user says "login does nothing"

Check:

- whether `appState.authError` is being set
- whether the feedback view is visible while the keyboard is open

This is a UI debugging lesson, not just a networking lesson.

## Try this yourself

1. Put a breakpoint in `AppState.signIn(withPrivyToken:)`.
2. Put another breakpoint in `AnkyAPI.resolveURL(for:)`.
3. Trigger email login.
4. Watch the token handoff happen from Privy into the backend exchange.
5. Change the base URL trailing slash locally and see how the resolved route changes.

That experiment is a good way to make Foundation URL behavior stick in your head.
