# 026 Server Indicator And Runtime Environment Visibility

## Mental model

When you are refactoring a client/runtime boundary, "what backend am I actually talking to?" becomes part of the product's debugging surface.

The point of `ServerIndicator.swift` is not to add another feature for end users. It is to make the runtime cutover visible inside the app itself:

1. The app already knows which backend root it is configured to use.
2. The UI should be able to read that configuration instead of re-encoding hostnames in another place.
3. A tiny status affordance in the top-right corner is enough to tell you two things at a glance: which environment this build is pointed at, and whether that backend is responding right now.

That is why the indicator reads `AnkyAPI.shared.baseURL` and then trims `/swift/v2` off that URL before sending a lightweight `HEAD` request to the backend root.

## Swift concepts involved

- Access control: `AnkyAPI.baseURL` changed from `private` to internal (`let baseURL: URL`) so another file in the same module can read the already-resolved environment.
- Computed properties: `environmentLabel` and `dotColor` translate runtime state into UI state.
- `@State`: `ServerIndicator` stores `isReachable` and `lastCheckedAt` as local view state because reachability belongs to the view's own refresh cycle.
- Swift concurrency: `checkReachability()` is `async` and uses `await URLSession.shared.data(for:)`.
- `MainActor`: after the network call completes, the view hops back to the main actor before mutating `@State`.

## SwiftUI concepts involved

- Small views can own their own polling loop. Here the indicator uses `.task` for the first check and `.onReceive(Timer.publish(...).autoconnect())` for the 30-second refresh.
- Placement matters more than size. The indicator only works if it lives in top chrome that users already scan for status.
- Different screens can have different top chrome. In this app, the chat shell, full-screen writer, and profile sheet do not actually share one reusable top bar, so the same indicator view is inserted into each surface's top-right slot.

## Files involved

- `Anky/AnkyAPI.swift`
  This is the source of truth for the backend root. The indicator should read from here, not hardcode its own hostnames.
- `Anky/ServerIndicator.swift`
  The new reusable SwiftUI view that renders the dot/label and performs the `HEAD` check.
- `Anky/AnkyChatView.swift`
  Owns the root chat header and the full-screen writing surface. The indicator appears in the chat header and in a top-right overlay while writing.
- `Anky/AnkyProfileView.swift`
  Owns the profile hero row. The indicator appears beside the gear button so it stays visible when the profile sheet replaces the chat shell.

## Data flow

1. `AnkyAPI` resolves the current `baseURL`.
2. `ServerIndicator` reads `AnkyAPI.shared.baseURL`.
3. It removes the `/swift/v2` path components to get the backend root like `https://staging.anky.app/`.
4. It sends a `HEAD` request with a 5-second timeout.
5. If the backend responds with any status in `200..<500`, the dot is treated as reachable.
6. If the request throws, the dot becomes the failure color.

The important idea is that the UI is not discovering the environment independently. It is reflecting the exact runtime configuration the API client is already using.

## Backend relationship

This feature is tied directly to the runtime cutover:

- Debug builds currently point `/swift/v2` traffic at `https://staging.anky.app`.
- Release builds point at `https://anky.app`.
- The indicator does not call a new backend endpoint. It just checks whether the already-selected backend root is responding.

That keeps the diagnostic honest: if the app is misconfigured, the indicator will reflect the same misconfiguration the real API client is using.

## Common failure modes

- If `baseURL` stays `private`, `ServerIndicator.swift` cannot read the configured backend and you end up duplicating environment logic.
- If you hardcode `staging` or `prod` URLs inside the indicator, the UI can drift away from the actual API client configuration.
- If you put the indicator only in the chat header, it disappears while the writing surface is full-screen.
- If you make the indicator too large or central, it stops feeling like status chrome and starts competing with the writing flow.

## How to debug it

- If the dot stays gray, confirm `checkReachability()` is being triggered from `.task` and from the timer.
- If the dot is always red, print the derived URL and verify that removing two path components from `baseURL` produces the real backend root you expect.
- If the label is wrong in a debug build, check `AnkyAPI.defaultBaseURL` first. The label only makes sense if the build configuration and API configuration match.
- If the indicator vanishes on a screen, inspect which view owns that screen's top chrome rather than assuming one global navigation bar exists.

## Try this yourself

1. Temporarily point `defaultBaseURL` at an invalid host in a debug build.
2. Launch the app and confirm the indicator goes red.
3. Point it back to staging and confirm the dot recovers on the next poll.
4. Move the indicator to only one surface, run the app, and notice how easy it is to lose visibility once a full-screen cover or overlay takes over.
