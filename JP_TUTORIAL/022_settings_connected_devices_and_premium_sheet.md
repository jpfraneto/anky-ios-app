# 022 Settings Connected Devices and Premium Sheet

This pass teaches one useful iOS product rule:

- settings screens are composition surfaces

`SettingsView.swift` is no longer just a place for one local toggle.

It now combines:

- local writing preferences
- local identity state
- backend-backed account sessions
- modal presentation state for premium UI

The main files in this pass are:

- `Anky/SettingsView.swift`
- `Anky/AnkyAPI.swift`
- `Anky/AnkyModels.swift`

## 1. Mental model

The important thing to notice is that these settings rows do **not** all come from the same kind of state.

Inside the same modal:

- text size is local `ObservableObject` state from `UserSettings.shared`
- wallet copy comes from `SeedIdentityManager`
- recovery phrase state comes from `AppState`
- connected devices come from the backend through `AnkyAPI`
- premium presentation comes from local SwiftUI `@State`

That means `SettingsView` is acting like a coordinator.

It does not own deep business logic.
It composes several existing systems into one surface.

That is a very common pattern in iOS:

- one screen
- many data sources
- one piece of presentation state holding it together

## 2. How connected devices are modeled

The backend payload for account sessions is not documented strongly in this repo yet, so the iOS side had to become tolerant.

`AnkyModels.swift` now adds:

- `ConnectedDevicesResponse`
- `ConnectedDevice`

The important design choice is that `ConnectedDevice` does **not** assume one exact JSON shape.

Its custom `init(from:)` accepts multiple possible keys for:

- id
- device name
- model
- platform
- current-session flag
- revoked flag
- timestamps

Why do this?

Because account-session APIs often drift in naming:

- `device_id` vs `session_id`
- `current` vs `is_current`
- `updated_at` vs `last_seen_at`

Instead of making the UI fragile, the decoder absorbs small contract differences.

That buys the app two things:

1. the settings screen can ship before the backend contract is perfectly frozen
2. JP can see how Codable can be strict where it matters and flexible where reality is messy

## 3. Why the current iPhone has a local fallback

`SettingsView.swift` calls:

- `AnkyAPI.shared.connectedDevices()`

which maps to:

- `GET /swift/v2/auth/sessions`

But the repo docs did not previously guarantee that route exists.

So the settings screen does not fail hard if the request fails.

Instead it uses:

- `ConnectedDevice.currentFallback(appVersion:)`

That means the user still sees:

- this iPhone
- app version
- current-session status

even if the backend cannot yet list remote sessions.

This is a good product pattern:

- show the truth you definitely know locally
- layer backend truth on top when available

That is why the screen feels resilient instead of empty.

## 4. The SwiftUI async state you should look for

The connected-devices section is driven by a few simple state values in `SettingsView.swift`:

- `connectedDevices`
- `isLoadingConnectedDevices`
- `connectedDevicesError`
- `revokingDeviceIDs`
- `devicePendingRevocation`

This is the important mental model:

- one state for data
- one state for loading
- one state for errors
- one state for transient destructive intent

The view then reacts to those states:

- `.task` loads devices when settings opens
- `.refreshable` reloads on pull
- the row button sets `devicePendingRevocation`
- the confirmation dialog reads that state
- the async revoke call updates the array and clears the pending dialog state

That is a classic SwiftUI data loop:

1. state changes
2. body re-renders
3. presentation updates automatically

No manual reload of the visible rows is needed.

## 5. How revoke works

The revoke path is intentionally conservative.

Only non-current, non-revoked devices show the destructive button.

The flow is:

1. tap `Revoke`
2. `devicePendingRevocation` is set
3. SwiftUI presents `confirmationDialog`
4. confirm action runs `revokeDevice(_:)`
5. `AnkyAPI.shared.revokeConnectedDevice(id:)` sends `DELETE /swift/v2/auth/sessions/{id}`
6. on success, the row is removed locally

Two details matter here:

- the current device cannot revoke itself from this control
- `revokingDeviceIDs` prevents duplicate taps while the request is in flight

That is not just UI polish.
It prevents racey destructive state.

## 6. Why the premium sheet is UI-only for now

The repo has:

- `UserProfile.isPremium`

but it does **not** have:

- StoreKit products
- purchase state manager
- restore flow
- receipt validation path

So the premium sheet in `SettingsView.swift` is a real presentation surface, but not a fake billing implementation.

That is why `PremiumSubscriptionSheet` does this:

- shows a full bottom-sheet design
- lets the user pick a plan
- keeps terms/privacy/restore actions in the footer
- shows an honest alert when the user tries to continue

This matters because fake commerce UI is dangerous.

If there is no real purchase pipeline, the user should not be tricked into thinking money can already move.

The right iOS engineering move is:

- ship the presentation structure now
- wire StoreKit later behind the same sheet

That keeps the design progress without lying about product readiness.

## 7. UIKit inside SwiftUI still shows up here

The settings screen now has two sheet layers that matter:

- the premium bottom sheet
- in-app Safari for legal pages

`SettingsSafariView` is still a `UIViewControllerRepresentable` wrapper around `SFSafariViewController`.

That means even inside this mostly SwiftUI feature, UIKit still handles the native browser controller.

The same pattern from lesson `020_settings_formalities_and_in_app_safari.md` still applies:

- SwiftUI owns visibility
- UIKit owns the specialized controller

The premium sheet reuses that same idea for its Terms and Privacy footer.

## 8. How data moves through the feature

Here is the full flow:

1. `AnkyProfileView` presents `SettingsView()`.
2. `SettingsView` loads wallet state from `SeedIdentityManager`.
3. `SettingsView` requests connected sessions from `AnkyAPI`.
4. `AnkyAPI` decodes those sessions through `ConnectedDevicesResponse` and `ConnectedDevice`.
5. If the backend list is missing, `SettingsView` inserts the local current-device fallback.
6. Tapping a remote device revoke button calls the delete endpoint and removes that row locally.
7. Tapping `Subscribe to Premium` toggles `showPremiumSheet`.
8. `PremiumSubscriptionSheet` presents from the bottom and owns its own legal footer links plus preview alert state.

That is a great example of why settings screens are not "simple."

They are often the densest composition point in the app.

## 9. Common failure modes

If the connected-devices list looks wrong, check these first:

1. `AnkyAPI.connectedDevices()` is pointing at the right backend route.
2. `ConnectedDevice.init(from:)` still matches the backend keys.
3. `mergedConnectedDevices(from:)` is not accidentally dropping the current session.
4. `device.canRevoke` is false for the current device and true for valid remote sessions.

If the premium sheet feels broken, check these:

1. `showPremiumSheet` is toggling.
2. `presentationDetents` still include the tall bottom-sheet detent.
3. legal footer buttons still set `selectedDocument`.
4. nobody accidentally replaced the honest preview alert with fake purchase success.

If you later add real billing, the right place to change is:

- `PremiumSubscriptionSheet`

but the data source will likely live in a separate purchase manager, not directly in `SettingsView`.

## 10. Try this yourself

1. In `SettingsView.swift`, temporarily force `loadConnectedDevices()` to throw and confirm that the sheet still shows the current iPhone.
2. Add one more alias key in `ConnectedDevice.init(from:)` and practice making a tolerant decoder safer.
3. Replace the premium preview alert with a stub purchase manager protocol so you can feel the seam where StoreKit should plug in later.

The main lesson from this pass is:

- one settings modal can safely combine local state, backend state, and future-facing UI, as long as each layer is explicit about what it really knows
