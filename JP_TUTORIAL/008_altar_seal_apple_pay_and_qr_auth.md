# Lesson 008: Altar, Seal, Apple Pay, and QR Auth

## Why this lesson exists

Anky now has a new product spine:

1. the phone holds the root identity
2. the seal is the deliberate confirmation gesture
3. the altar is a native Apple Pay flow, not a web checkout
4. browser login can be sealed from the phone through a deep link

This lesson explains how those pieces fit together in the real codebase.

## Mental model one: the seal is not a button with animation

Start with [SealView.swift](/Users/kithkui/Desktop/ankY/Anky/SealView.swift).

`SealView` is a reusable confirmation control. The important product rule is built directly into the component:

- the user drags left to right
- the drag position alone is not enough
- elapsed time alone is not enough
- visible progress is `min(dragProgress, elapsedTime / 8.0)`

That means the handle can never outrun the clock.

This is a useful SwiftUI lesson. A good reusable view should own its product law, not force every screen to re-implement it. If the eight-second rule matters everywhere, the rule belongs in the shared component.

Inside `SealView`, notice the responsibilities:

- it owns the eight-color kingdom palette
- it interpolates the active color as progress moves
- it uses a `DragGesture` to capture the user intent
- it uses a repeating timer to keep elapsed-time progress moving while the drag is active
- it fires the heavy haptic and full-screen flash only when both drag distance and time have completed

That is why the parent views only pass a label and an `onSeal` closure. They do not get to decide what "complete" means.

## Mental model two: placement changes, behavior does not

Open [AnkyChatView.swift](/Users/kithkui/Desktop/ankY/Anky/AnkyChatView.swift).

The seal now appears in multiple writing contexts:

- above the keyboard in `WritingKeyboardView`
- in the paused send-or-keep-writing state through `SessionPauseChoiceView`
- in the voice-writing path through `VoiceSessionView`

The key design point is that the same gesture is reused, but the layout adapts to context.

When the keyboard is present, the track sits in the suggestion-bar zone. When there is no keyboard, the parent screen can place it lower on the page, like the QR auth screen does.

Also notice the interaction hook:

- `SealView` exposes `onInteractionChanged`
- `ChatViewModel` stores `isSealEngaged`
- the writing timer keeps elapsed time moving, but the idle cutoff is suspended while the user is actively sealing

This is a strong iOS architecture lesson. The shared component owns gesture mechanics. The feature owner owns session consequences.

## Mental model three: the phone signs, the backend verifies

Open:

- [SeedIdentityManager.swift](/Users/kithkui/Desktop/ankY/Anky/SeedIdentityManager.swift)
- [SolanaSeedIdentityCrypto.swift](/Users/kithkui/Desktop/ankY/Anky/Crypto/SolanaSeedIdentityCrypto.swift)
- [SeedAuthService.swift](/Users/kithkui/Desktop/ankY/Anky/SeedAuthService.swift)

The current identity model is:

- BIP39 mnemonic
- SLIP-0010 derivation path `m/44'/501'/0'/0'`
- Ed25519 private key
- Solana address as base58-encoded public key

`SeedIdentityManager` owns local secrets in Keychain. `SeedIdentityCrypto` owns the dangerous cryptographic derivation and signing work. `SeedAuthService` owns network authentication.

That separation matters.

For QR seal auth, the app does not ask the backend to sign anything. It:

1. reads the challenge token from the deep link
2. signs the raw token bytes locally with Ed25519
3. base58-encodes the signature
4. sends the token, signature, and Solana address to the backend

That same local identity is also what ties an altar burn to a real user after Apple Pay succeeds.

## Mental model four: Apple Pay is a two-step truth

Open:

- [AltarView.swift](/Users/kithkui/Desktop/ankY/Anky/AltarView.swift)
- [AnkyAPI.swift](/Users/kithkui/Desktop/ankY/Anky/AnkyAPI.swift)
- [Anky.entitlements](/Users/kithkui/Desktop/ankY/Anky.entitlements)

The altar is not "just call Stripe." It is two systems:

1. Stripe confirms that money moved
2. Anky records which identity that burn belongs to

The flow inside `AltarViewModel` is:

1. `GET /api/altar` loads the image, totals, leaderboard, recent burns, and the Stripe publishable key.
2. The user enters a dollar amount.
3. `POST /api/altar/payment-intent` creates the PaymentIntent before Apple Pay is shown.
4. `STPApplePayContext` presents the native Apple Pay sheet using the repo's merchant identifier.
5. After Stripe reports success, the app calls `POST /api/altar/apple-pay` with the PaymentIntent ID plus the user's Solana address.
6. The returned altar state replaces the old UI state, and the hero image glows.

That last step is important. Payment success is not the same thing as application-state success.

If Stripe succeeds but the final Anky API call fails, the app saves a pending sync record and lets the user retry it later. This keeps the product promise that the offering should still be associated with the right identity.

## Mental model five: deep links are app-state inputs

Open:

- [AnkyApp.swift](/Users/kithkui/Desktop/ankY/Anky/AnkyApp.swift)
- [AppState.swift](/Users/kithkui/Desktop/ankY/Anky/AppState.swift)
- [ContentView.swift](/Users/kithkui/Desktop/ankY/Anky/ContentView.swift)
- [QRSealAuthView.swift](/Users/kithkui/Desktop/ankY/Anky/QRSealAuthView.swift)

The QR auth flow works because the app treats the incoming URL as state, not as ad-hoc navigation code.

The path is:

1. Safari opens `anky://seal?challenge=<token>`
2. `AnkyApp` parses the custom scheme URL
3. `AppState` stores a `QRSealChallenge`
4. `ContentView` observes that state and presents `QRSealAuthView` full-screen
5. `QRSealAuthView` waits for the eight-second seal, signs the challenge, sends it to `/api/auth/qr/seal`, shows success, and dismisses

This is classic SwiftUI thinking:

- URL parsing belongs near app entry
- durable route state belongs in app state
- presentation belongs in the root view
- the feature screen does the work once it is on screen

## How data moves through the feature

Here is the full path for each new flow.

### Writing submission with the seal

1. The user writes inside `AnkyChatView`.
2. `SealView` replaces the old send button in the writing controls.
3. When the seal completes, the existing submission path runs.
4. The writing timer and idle logic do not punish the user while they are actively sealing.

### Altar burn with Apple Pay

1. `AltarView` loads altar state from the backend.
2. The user enters an amount and taps `BURN`.
3. `AltarViewModel` creates a PaymentIntent.
4. Stripe presents Apple Pay.
5. Stripe confirms the payment.
6. Anky records the burn against the Solana address.
7. The altar refreshes and the image glow animates.

### Browser QR auth

1. The browser shows a QR code for a challenge token.
2. The phone opens from `anky://seal?...`.
3. The user seals on the phone.
4. The phone signs the challenge locally.
5. The backend verifies the signature and connects the browser session to that Solana address.

## Common failure modes and where to debug

### 1. The seal snaps back before completing

Check [SealView.swift](/Users/kithkui/Desktop/ankY/Anky/SealView.swift).

Look at:

- whether `dragProgress` is reaching the end of the track
- whether `elapsedProgress` has actually crossed `1.0`
- whether the parent accidentally disabled the view

Usually this means the user lifted early or the parent screen recreated the view state.

### 2. Apple Pay says it is unavailable

Check:

- real hardware vs simulator
- whether the device has Apple Pay configured
- whether the merchant identifier in [Anky.entitlements](/Users/kithkui/Desktop/ankY/Anky.entitlements) matches the Apple Developer configuration
- whether Stripe has the payment processing certificate uploaded for Apple Pay

This is usually environment configuration, not SwiftUI layout.

### 3. Apple Pay succeeds but the leaderboard does not change

Check [AltarView.swift](/Users/kithkui/Desktop/ankY/Anky/AltarView.swift).

Look at:

- `finalizeBurn(afterSuccessfulApplePay:)`
- `PendingBurnSyncStore`
- whether `hasPendingBurnSync` became `true`

This means Stripe likely succeeded but `POST /api/altar/apple-pay` failed afterward.

### 4. QR auth opens the app but no seal screen appears

Check:

- URL scheme registration in `Info.plist`
- `handleIncomingURL` in [AnkyApp.swift](/Users/kithkui/Desktop/ankY/Anky/AnkyApp.swift)
- whether `AppState.qrSealChallenge` is being set
- whether [ContentView.swift](/Users/kithkui/Desktop/ankY/Anky/ContentView.swift) is presenting the full-screen cover

This is usually URL parsing or state propagation.

### 5. QR seal reaches the backend but verification fails

Check:

- the exact token bytes being signed
- whether the signature is base58-encoded
- whether the Solana address came from the same local keypair
- whether the backend expects the same challenge string that came through the deep link

This is usually a signing-serialization mismatch, not a UI issue.

## Try this yourself

1. Put a breakpoint in `SealView.completeSeal()`.
2. Put another in `AltarViewModel.applePayContext(_:didCompleteWith:error:)`.
3. Put another in `QRSealAuthView.submitSeal()`.
4. Run the app and trigger each flow once.
5. Watch how the same local identity shows up in writing submission, altar attribution, and browser QR auth.

That is the real lesson here: one identity, one seal ritual, multiple surfaces.
