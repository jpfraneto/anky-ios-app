# Anky iOS

Anky iOS is the native iPhone client for the Anky writing practice.

The current app centers one product path:

- the parent gets a silent local seed identity on first open
- the altar is now the first surface after login
- Face ID opens the writing space from the altar instead of making writing the home screen
- unfinished and short writing stays local
- a persisted real anky still advances the deeper unlock state, but the visible signed-in shell is now the same altar-first home for both locked and unlocked users
- that writing can become a Spanish `cuentacuentos` inside a child's world in the same app
- the same eight-second seal gesture is now the shared confirmation ritual for writing, browser auth, and altar actions
- the altar is a native Apple Pay flow tied back to the phone's Solana identity

The app is not a separate product from the backend. It is the mobile surface for the wider Anky system described in the monorepo and whitepaper.

## Current product model

- A local seed identity exists from first open.
- There is no new email, phone, or social-login onboarding path.
- The phone's master identity is a local BIP39 phrase that derives one canonical Solana Ed25519 address.
- A real anky requires `>= 8 minutes` and `>= 300 words`.
- `persisted` from `POST /swift/v2/write` is canonical.
- If `persisted == false`, the session stays local-only and must not appear in cloud history.
- Unlock state still advances only after a successful persisted real anky, or when a recovered identity already has persisted ankys on the backend, but the visible signed-in shell is now shared.
- The altar is now the default signed-in home surface.
- Writing opens from a Face ID-gated altar button and lives in a separate full-screen layer above the altar.
- The in-app writing keyboard is themed by the current Ankyverse day from the local calendar, not by the user's wallet-derived kingdom.
- Writing submission is now sealed through the shared eight-second swipe instead of a normal send button.
- Browser login can be completed by deep-linking into the phone and sealing a QR challenge.
- The altar uses Apple Pay via Stripe, then records the burn against the user's Solana address.
- After unlock, the parent can create one or more child worlds derived from the parent seed identity.
- Each child world has a backend child profile and a local 12-emoji pattern lock.
- Child stories are fetched from `/swift/v2/cuentacuentos/*` and played through the shared guidance player.
- After the first reflected response to a writing session, the user can reply in a lightweight text chat grounded in that latest writing.

## Backend relationship

Anky now talks to two backend surfaces:

- `https://anky.app/swift/v2` for seed auth, profile, writing, and child/story flows
- `https://anky.app/api/*` for quick chat, altar data, Apple Pay orchestration, and QR seal auth

The active flow is:

1. The app generates a local BIP39 phrase and derives one canonical Solana Ed25519 identity from `m/44'/501'/0'/0'`.
2. The backend issues a one-time challenge through `POST /swift/v2/auth/challenge`.
3. The app signs the exact challenge bytes locally with Ed25519, base58-encodes the signature, and verifies through `POST /swift/v2/auth/verify`.
4. The app writes through `POST /swift/v2/write`.
5. After the reflected response lands, follow-up chat replies go through the root web endpoint `POST /api/chat-quick` with the latest writing text plus the current-session reflection thread.
6. The seal gesture is reused in the writing flow, QR browser login, and altar-related confirmation surfaces.
7. The altar loads through `GET /api/altar`, creates PaymentIntents through `POST /api/altar/payment-intent`, confirms Apple Pay through Stripe, then records the burn through `POST /api/altar/apple-pay`.
8. Browser QR auth deep-links into `anky://seal?challenge=...`, the phone signs the challenge token locally, and the app sends it to `POST /api/auth/qr/seal`.
9. The parent can create child profiles through `POST /swift/v2/children` using a deterministic child address derived from the parent key plus a SHA-256-based salt built from parent address, name, and birthdate.
10. The app reads identity, persisted history, child profiles, and child stories through `GET /swift/v2/me`, `GET /swift/v2/writings`, `GET /swift/v2/children`, and `GET /swift/v2/cuentacuentos/*`.

Legacy meditation, breathwork, sadhana, and facilitator surfaces were removed from the active product.

Backend/system context lives in the Anky monorepo:

- `WHITEPAPER.pdf`
- `UNDERSTANDING_ANKY.md`
- `SWIFT_AGENT_BRIEF.md`
- `THE_ANKY_MODEL.md`

Monorepo: <https://github.com/jpfraneto/anky-monorepo>

## Current app capabilities

### Identity and auth

- Silent local BIP39 phrase generation on first open
- Solana-native Ed25519 key derivation from `m/44'/501'/0'/0'`
- Canonical base58 Solana wallet address identity
- Private key storage in Keychain, with synchronizable key storage enabled for the seed material
- Four-step welcome flow that quietly explains the 8-minute practice, Face ID, iCloud Keychain storage, and daily notifications
- Face ID lock overlay after onboarding so identity stays invisible in daily use
- Daily 6:00 AM local prompt notification with the starter prompt `how are you?`
- Local recovery import by entering the phrase on-device
- Silent challenge/verify authentication against `/swift/v2/auth/*`
- Backend session token storage in Keychain
- QR browser auth through `anky://seal?challenge=...` and `POST /api/auth/qr/seal`

### Seal and altar

- Reusable eight-second `SealView` with the full kingdom color progression, heavy haptic completion, and flash-to-Poiesis finish
- Seal-driven writing submission inside the active chat writing route, including keyboard, pause-choice, and voice-writing surfaces
- Dedicated QR seal screen with the anky image, challenge signing, and one-second sealed confirmation
- Native altar home screen backed by `/api/altar`
- Generated full-screen altar background image with live totals, leaderboard, and recent burns overlaid on top
- Native Apple Pay flow through Stripe `STPApplePayContext`
- Burn attribution to the user's Solana address after Apple Pay succeeds
- Pending burn-sync persistence so successful payments can be reconciled if the final altar API call fails

### Writing and unlock

- Altar-first root shell with a Face ID-gated button that opens the writing experience from the bottom of the home screen
- Writing/chat surface presented above the altar instead of replacing the root route
- Hidden composer with a dominant center glyph instead of a normal text editor
- Responsive footer that never grows past the screen width and clips overflow instead of expanding the viewport
- Visible single-line writing strip with the newest character pinned to the right edge
- Eight-minute progress bar directly above the status footer
- Active `AnkyChatView` sessions keep counting past 8 minutes, treat 8 minutes as a visual milestone only, and pause into a `seal to send` / `keep writing` choice after 8 seconds of idle once writing has started
- Daily Ankyverse in-app keyboard with comma, period, newline, and `123` / `ABC` symbol toggling
- Legacy `AnkyWritingSession` still contains the older two-life idle mechanic with a text-only `type to resume` pause state after the first lost life
- Local draft persistence and interrupted-session recovery
- Local-only completion for short or unfinished sessions
- Offline queueing only for real ankys
- Full unlock state still depends on persisted real ankys, even though the visible signed-in shell is now shared
- Persisted history view that excludes any local-only or `persisted: false` sessions
- Short writes now fall into a deliberately simple chat surface inside the same writing experience
- Post-reflection quick chat replies still go through `POST /api/chat-quick`, grounded in the latest writing text and current-session chat history
- Reflections from the polled writing status are cached into local writing history instead of being dropped

### Parent and child worlds

- Multi-step child world creation flow with name, birthdate, and emoji-pattern confirmation
- Deterministic child wallet derivation on-device from the parent private key and a SHA-256 salt
- Local child profile persistence in `ChildProfileStore`
- Child world entry buttons below the unlocked shell tabs
- Local 12-emoji child lock screen before entering the story library
- Child story library backed by `/swift/v2/cuentacuentos/ready`, `/swift/v2/cuentacuentos/history`, and `/swift/v2/cuentacuentos/:id/complete`
- Spanish voice preference for `cuentacuentos` playback inside the shared guidance player
- `ANKYS` history indicator for writings that already produced a `cuentacuentos`

### Legacy unlocked shell code

- `NOW`
- `ANKYS`
- `SEED`
- child world buttons below the tab bar

Those screens still compile and can still be presented, but the root route currently lands in `AnkyChatView` instead of the old tab shell.

The app now has a lightweight follow-up conversation surface after a reflected writing response lands. It is not a general-purpose thread API yet; it is a quick back-and-forth loop anchored to the latest writing session.

## Seed identity security note

The recovery phrase is the root secret. It never goes to the backend.

The current iOS code uses a locked local BIP39 + SLIP-0010 implementation built on top of `CryptoKit` and `CommonCrypto`. Because that is security-critical, the repo locks it down with deterministic tests for:

- mnemonic generation and checksum validation
- mnemonic-to-seed derivation
- canonical derivation path `m/44'/501'/0'/0'`
- Ed25519 private key derivation and Solana base58 address output
- Ed25519 challenge signature verification and Base58 encoding/decoding

There is also an opt-in live backend test path in `AnkyTests.swift`, plus a repo-local verifier in `Tools/LiveBackendVerifier.swift` for direct production challenge/verify/write checks.

Do not change the derivation path or phrase handling casually.

## Tech stack

- SwiftUI
- Swift Concurrency
- CryptoKit
- CommonCrypto
- AVFoundation
- Keychain
- PassKit
- Stripe Apple Pay (`stripe-ios-spm`)
- Native iOS haptics

No third-party UI framework is used.

## Project map

```text
Anky/
  AnkyApp.swift               App entry point
  AppState.swift              Root routing, identity state, unlock state
  ContentView.swift           Welcome flow, recovery, locked shell, unlocked shell
  AnkyChatView.swift          Altar-first root shell, writing layer, daily keyboard, quick chat follow-ups
  AnkyAPI.swift               `/swift/v2/*` client plus root `/api/*` endpoints
  AnkyModels.swift            Codable models aligned to backend responses
  SealView.swift              Reusable eight-second seal gesture
  AltarView.swift             Altar screen, Stripe Apple Pay, burn sync
  QRSealAuthView.swift        Deep-link QR auth seal flow
  SeedIdentityManager.swift   Phrase generation, derivation, signing, Keychain
  ChildIdentityDeriver.swift  Deterministic child wallet derivation from the parent key
  SeedAuthService.swift       Challenge/verify auth flow
  KeychainHelper.swift        Secure key and token persistence
  BiometricLockManager.swift  Face ID / biometrics privacy gate
  DailyPromptNotificationManager.swift
                              6:00 AM local reminder scheduling
  AnkyWritingSession.swift    NOW writing state machine and completion flow
  WritingSessionStore.swift   Local in-progress draft persistence
  WritingCacheStore.swift     Local writing history cache
  ChildProfileStore.swift     Local child-profile cache
  ChildWorldComponents.swift  Shared emoji pattern UI pieces
  CreateChildView.swift       Multi-step child world creation flow
  ChildShellView.swift        Child lock screen and `cuentacuentos` library
  OfflineQueue.swift          Deferred sync for persisted real ankys
  AppCopy.swift               Welcome flow and shell localization
  WritingExperienceStrings.swift
                              Writing flow localization
Tools/
  LiveBackendVerifier.swift   Direct live `/swift/v2` auth and write verifier
```

## Build and verification

Build:

```bash
xcodebuild -scheme Anky -project Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build
```

Build tests:

```bash
xcodebuild build-for-testing -scheme Anky -project Anky.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3'
```

The local test target currently builds cleanly. On this machine, `xcodebuild test` is still stalling after destination resolution on the iOS 26.3 simulator runtime, so the strongest verification today is:

- simulator build
- build-for-testing
- deterministic seed/auth unit tests
- direct live verification through `Tools/LiveBackendVerifier.swift`
- live `GET /api/altar` verification against production

Apple Pay itself still requires on-device validation with a real merchant setup. The repo includes the merchant entitlement and Stripe package wiring, but final success still depends on:

- Apple Developer merchant ID configuration
- the payment processing certificate uploaded in Stripe
- a real iPhone with Apple Pay enabled

`Tools/LiveBackendVerifier.swift` is aligned to the current Solana/Ed25519 auth path. Re-run it when you need a fresh production transcript for:

- `POST /swift/v2/auth/challenge`
- `POST /swift/v2/auth/verify`
- `GET /swift/v2/me`
- short vs real `POST /swift/v2/write`

## Documentation rhythm

- Update `CHANGELOG.md` after each meaningful implementation pass.
- Add or update a `JP_TUTORIAL` lesson when a feature meaningfully changes.
- Keep the Swift models, README, and auth/write docs aligned whenever the backend contract changes.
