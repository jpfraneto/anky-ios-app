# Anky iOS

Anky iOS is the native iPhone client for the Anky writing practice.

The current app centers one product path:

- the parent gets a silent local seed identity on first open
- the routed surface is now a conversation-first `AnkyChatView`, not a separate home tab shell
- fresh launches open a dedicated forward-only writing overlay, while the main chat shell underneath keeps a separate short-message composer
- the untouched writing overlay can now close cleanly again without crashing because the custom `UITextView` focus bridge tears down safely during dismissal
- settings now includes connected-device session management with revoke controls plus a premium subscription preview sheet; the device list falls back to the current iPhone if `/swift/v2/auth/sessions` is not live yet, and billing remains UI-only until StoreKit is wired
- when a real session ends, a full-screen sealing screen now sits between writing completion and chat reveal, but the finished anky is recorded locally right away even if the user skips that ritual
- every finished writing session now becomes a canonical `.anky` file with first-keystroke epoch timing, `SPACE` tokens for literal spaces, SHA-256 filename hashing, on-disk verification before submission, and a recoverable `partial_` artifact while the session is still live
- unfinished and short writing stay local, while the active chat-first writer now submits real ankys through `/api/anky/submit` SSE
- a persisted real anky still advances the deeper unlock state, but the visible signed-in shell is now the same chat-first route for both locked and unlocked users
- active drafts autosave every 300ms and restore on relaunch / foreground resume
- crossing 8 minutes triggers a distinct milestone effect, then the session seals and moves into the reflection pipeline
- after a session sends, the user's raw writing appears first, then Anky reflects, then the generated image arrives inline in chat, and profile/history update from the same pending local record instead of waiting for `/swift/v2/writings`
- if that backend processing stalls, the pending anky stays visible in profile, retries automatically on the next authenticated launch/login, and can still be resent manually from the archive using the same canonical `.anky` payload and session hash
- the conversation resets by UTC day without deleting older days, and the profile screen becomes the archive/history surface
- that writing can become a Spanish `cuentacuentos` inside a child's world in the same app
- the same eight-second seal gesture is now the shared confirmation ritual for writing, browser auth, and altar actions
- the altar remains a native Apple Pay flow tied back to the phone's Solana identity

The app is not a separate product from the backend. It is the mobile surface for the wider Anky system described in the monorepo and whitepaper.

## Current product model

- A local seed identity exists from first open.
- There is no new email, phone, or social-login onboarding path.
- The phone's master identity is a local BIP39 phrase that derives one canonical Solana Ed25519 address.
- A real anky requires `>= 8 minutes` and `>= 300 words`.
- `done` or a tolerated `image` / `solana` terminal error from `POST /api/anky/submit` is canonical for the active chat-first writer; legacy surfaces still compile against `POST /swift/v2/write`.
- If `persisted == false`, the session stays local-only and must not appear in cloud history.
- Unlock state still advances only after a successful persisted real anky, or when a recovered identity already has persisted ankys on the backend, but the visible signed-in shell is now shared.
- The routed signed-in shell is `AnkyChatView`; fresh launches default into the writing overlay, but deeplinks take priority and can open QR login, Now rooms, shared Ankys, or prompt-specific writing instead.
- The native generate route now keeps generation state visually obvious with a live activity card and pending collage placeholders, and completed generated Ankys can be saved directly to Photos.
- The altar still exists, but it now lives behind the profile support entry instead of the main chat header.
- The active typed writing surface uses one persistent UIKit `UITextView` with delete, paste, newline, autocorrect, autocapitalization, spellcheck, and QuickType disabled.
- The canonical write artifact is a UTF-8 `.anky` file written under `ankys/yyyy/mm/dd/{session_hash}.anky`, with line 1 storing the first accepted keystroke's absolute epoch milliseconds and every later line storing delta milliseconds. While a session is still live, the app also refreshes `partial_{sessionId}.anky` every 300ms so a crash can resume without losing the keystroke stream.
- Pending real ankys preserve that canonical payload metadata in local history, so the profile sheet can ask the backend to process the same session later instead of losing the submission path when the original SSE request dies.
- The active writing overlay uses the prompt itself as the `UITextView` placeholder, shows both the top and bottom bars before the first keystroke, only turns the top bar into an active idle warning after 3 seconds of silence, drains that warning from right to left, keeps the 8-minute progress bar at the bottom, hides the timer/exit chrome once writing is underway so the text area feels cleaner, dismisses the keyboard immediately when the user exits the writing surface, and now opens from chat as one continuous full-screen transition instead of a staged blank reveal.
- The red close path now ends editing on the key window and dismisses the overlay on the next main turn, while `AnkyComposerTextView` cancels stale focus work during teardown so keyboard dismissal cannot race the SwiftUI removal path.
- The settings sheet now owns text-size preview, wallet copy, recovery-phrase presentation, connected-device session management, formalities links, a premium preview bottom sheet, and the branded `Created with 💚 by Anky, Inc.` footer.
- Connected-device settings speak `/swift/v2/auth/sessions` when that backend route exists, but the UI still degrades gracefully to the current iPhone when the route is unavailable.
- Premium checkout is currently a high-fidelity native preview surface only; real App Store purchase and restore behavior are not wired yet.
- The collapsed chat dock stays bottom-anchored and uses a stable hourglass / message field / pen-or-send layout, with the right action swapping immediately from glowing pen to send as soon as text exists.
- Active writing is autosaved locally on every keystroke with a 300ms debounce and restored if the app relaunches before completion.
- Crossing 8 minutes triggers a milestone overlay and haptics, then the session drops into the sealing screen before chat is revealed.
- Short or incomplete sessions stay local-only and must not be promoted into the real-anky archive.
- Browser login can be completed by deep-linking into the phone and sealing a QR challenge.
- Shared generated Ankys opened from `https://anky.app/anky/{id}` now present their own native full-screen detail view instead of falling through to the default writing overlay.
- The altar uses Apple Pay via Stripe, then records the burn against the user's Solana address.
- The profile screen now owns the archive with a compact hero, locally derived stats, real-anky cards, a month calendar, territories, kingdom detail sheets, and inline archived-conversation sheets.
- After unlock, the parent can create one or more child worlds derived from the parent seed identity.
- Each child world has a backend child profile and a local 12-emoji pattern lock.
- Child stories are fetched from `/swift/v2/cuentacuentos/*` and played through the shared guidance player.
- After the first reflected response to a writing session, the user can reply in a lightweight text chat grounded in that latest writing, and those follow-ups are mirrored into a per-anky local thread archive so the same conversation can be reopened from profile.

## Backend relationship

Anky now talks to two backend surfaces:

- `https://anky.app/swift/v2` for seed auth, profile, legacy writing paths, and child/story flows
- `https://anky.app/api/*` for the active chat-first submit stream, quick chat, altar data, Apple Pay orchestration, and QR seal auth

The active flow is:

1. The app generates a local BIP39 phrase and derives one canonical Solana Ed25519 identity from `m/44'/501'/0'/0'`.
2. The backend issues a one-time challenge through `POST /swift/v2/auth/challenge`.
3. The app signs the exact challenge bytes locally with Ed25519, base58-encodes the signature, and verifies through `POST /swift/v2/auth/verify`.
4. The active chat-first writer writes `partial_{sessionId}.anky` while the session is in progress, then atomically renames that file into the final hash-named canonical `.anky` file on completion, signs that exact file hash with the user's Solana seed identity, and submits the file contents through `POST /api/anky/submit`, which streams `accepted`, `reflection_chunk`, `reflection_complete`, `image_url`, `solana`, and `done` events over SSE.
5. The sealing screen intercepts the end of writing before chat is revealed, records the pending real anky locally, accumulates reflection chunks in `ChatViewModel`, and now tolerates a normal stream close after acceptance so the UI does not hang forever waiting for one last event. If the user skips the sealing ritual, `AnkyChatView` still records that same pending anky immediately and streams the same submit contract in the background, so chat/profile stop lagging behind the finished session.
6. Legacy writing surfaces still compile against `POST /swift/v2/write` until the parallel migration branch lands.
7. After the reflected response lands, the live chat surface still uses `POST /api/chat-quick` with the latest writing text plus the current-session reflection thread, while archived profile sheets prefer `POST /api/anky/{id}/conversation` when a real backend anky id exists and fall back to `POST /api/chat-quick` for older/local-only sessions. All of those follow-ups are mirrored into `AnkyThreadChatStore` for later profile replay.
8. The seal gesture is reused in the writing flow, QR browser login, and altar-related confirmation surfaces.
9. The altar loads through `GET /api/altar`, creates PaymentIntents through `POST /api/altar/payment-intent`, confirms Apple Pay through Stripe, then records the burn through `POST /api/altar/apple-pay`.
10. Browser QR auth deep-links into `anky://seal?challenge=...`, the phone signs the challenge token locally, and the app sends it to `POST /api/auth/qr/seal`.
11. The parent can create child profiles through `POST /swift/v2/children` using a deterministic child address derived from the parent key plus a SHA-256-based salt built from parent address, name, and birthdate.
12. The app reads identity, persisted history, child profiles, and child stories through `GET /swift/v2/me`, `GET /swift/v2/writings`, `GET /swift/v2/children`, and `GET /swift/v2/cuentacuentos/*`.

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
- A recovery-phrase backup ceremony that now opens full-screen from settings/profile and stays scroll-safe, so the reveal and secure swipe controls remain reachable on smaller screens
- Silent challenge/verify authentication against `/swift/v2/auth/*`
- Backend session token storage in Keychain
- Connected-device session list and revoke support through `/swift/v2/auth/sessions` when the backend route is available, with a local current-device fallback when it is not
- QR browser auth through `anky://seal?challenge=...` and `POST /api/auth/qr/seal`

### Seal and altar

- Reusable eight-second `SealView` with the full kingdom color progression, heavy haptic completion, and flash-to-Poiesis finish
- Seal-driven confirmation still exists in QR auth, altar flows, and legacy / voice writing submission surfaces
- Dedicated QR seal screen with the anky image, challenge signing, and one-second sealed confirmation
- Native altar home screen backed by `/api/altar`
- Generated full-screen altar background image with live totals, leaderboard, and recent burns overlaid on top
- Native Apple Pay flow through Stripe `STPApplePayContext`
- Burn attribution to the user's Solana address after Apple Pay succeeds
- Pending burn-sync persistence so successful payments can be reconciled if the final altar API call fails

### Writing and unlock

- Chat-first root shell with the active prompt/history surface in `AnkyChatView`
- Fresh launches now open directly into the writing overlay, while deeplinks for QR auth, `Now`, shared Ankys, and prompt-specific writing override that default presentation
- A stripped chat header with a hamburger on the left that opens the profile/archive surface
- A native Flux generation screen with prompt input, aspect-ratio selection, an obvious in-progress generation card, backend polling through `/api/v1/generate` and `/api/v1/anky/:id`, a collage gallery of generated Ankys, and save-to-Photos for finished images
- A dedicated forward-only `UITextView` writing overlay whose prompt lives inside the text view as the placeholder instead of separate prompt chrome
- A full-screen `SealingView` that intercepts the end of writing, shows kingdom-of-the-day presentation, streams `/api/anky/submit`, and only reveals chat after seal or skip
- A stable collapsed chat dock with a fixed left hourglass action, center message field, and right pen/send action
- Forward-only typed writing: no delete, no paste, no spellcheck, no autocorrect, no autocapitalization, no newline insertion, and no QuickType bar
- A calmer writing chrome: the idle warning bar appears only after 3 seconds of silence, drains from right to left, the timer row disappears after 20 seconds, the red exit control disappears as soon as typing begins, the text view keeps extra bottom inset so lines stay above the session bar, and the keyboard resigns immediately when the user closes the surface
- Exact active writing layout: a top idle-warning region that only becomes visible after 3 seconds of silence, a full-height scrollable writing surface with the prompt as placeholder, a bottom 8-minute progress bar, and a short-lived timer/exit row that disappears once writing is established
- Active typed sessions autosave locally on every keystroke with a 300ms debounce and restore automatically on relaunch / foreground resume
- Eight-minute milestone overlay with haptics and automatic send into the sealing-and-streaming submit pipeline
- Raw writing bubble with an inline `copy` -> `copied` affordance after send, followed by Anky's reflection bubble and a fixed-height generated image bubble
- Conversation view auto-pins to the newest message or typing state so send and reply transitions land at the bottom without manual scrolling
- Interaction haptics now mark writing-mode entry, meditation-timer start, the final idle-warning second, and copy confirmation
- Settings font samples now preview at the live selected writing size instead of a fixed placeholder size
- The active settings sheet now uses grouped dark cards instead of default `Form` chrome, includes connected-device revoke controls, and opens Terms of Service, Privacy Policy, and FAQ inside an in-app Safari sheet
- The active settings sheet also includes a premium subscription preview bottom sheet inspired by the design reference, while keeping purchase and restore behavior explicit placeholders until StoreKit is wired
- Real-anky-only archive truth: short sessions stay local-only, real ankys are recorded locally as pending immediately, and fresh local real ankys remain visible even before `/swift/v2/writings` catches up
- Daily UTC chat reset with archived previous days instead of destructive clearing
- Profile v2 archive surface with a compact hero row, locally derived points/level/streak/words, real-anky image cards, tappable calendar drill-down, full territories list across all eight kingdoms, and large bottom-sheet conversation replay for each archived anky
- Legacy `AnkyWritingSession` still contains the older two-life idle mechanic with a text-only `type to resume` pause state after the first lost life
- Local draft persistence and interrupted-session recovery
- Local-only completion for short or unfinished sessions
- Offline queueing only for real ankys
- Full unlock state still depends on persisted real ankys, even though the visible signed-in shell is now shared
- Persisted history view that excludes any local-only or `persisted: false` sessions
- Post-reflection follow-up replies use `POST /api/chat-quick` in the live chat surface and prefer `POST /api/anky/{id}/conversation` inside archived profile sheets when a real backend anky id exists; both paths are mirrored into the per-anky local thread store
- Reflections, titles, and generated image paths from the polled writing status are cached back into local writing history instead of being dropped

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

The app now has two follow-up conversation surfaces after a reflected writing response lands: the live chat composer, and the archived profile sheet for each real anky. It is still not a fully backend-synced thread platform, but those replies are mirrored into a per-anky local archive so profile can reopen the conversation later.

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
  AppState.swift              Root routing, identity state, unlock state, writing-history updates
  ContentView.swift           Root pass-through into the active chat shell plus legacy shells that still compile
  AnkyChatView.swift          Active chat shell, fresh-launch writing overlay, deeplink priority handling, shared-Anky presentation, milestone flow, daily archive chat
  GenerateView.swift          Native Flux generation screen, polling loop, and collage gallery
  GeneratedAnkyStore.swift    Local persistence for completed and pending generated Ankys
  AnkyAPI.swift               `/swift/v2/*` client plus root `/api/*` endpoints including native generate/gallery routes
  AnkyModels.swift            Codable models aligned to backend responses
  SealingView.swift           Full-screen post-write sealing surface and SSE-driven reveal gate
  SealView.swift              Reusable eight-second seal gesture
  AltarView.swift             Altar screen, Stripe Apple Pay, burn sync, reachable from profile support
  AnkyProfileView.swift       Active profile/archive surface with hero, section switching, calendar, territories, and archived conversation sheets
  SettingsView.swift          Active settings modal with connected devices, premium sheet preview, legal links, and identity controls
  ChatStore.swift             Daily UTC conversation persistence and archived-day loading
  AnkyThreadChatStore.swift   Per-anky follow-up thread persistence used by live chat and profile replay
  QRSealAuthView.swift        Deep-link QR auth seal flow
  SeedIdentityManager.swift   Phrase generation, derivation, signing, Keychain
  ChildIdentityDeriver.swift  Deterministic child wallet derivation from the parent key
  SeedAuthService.swift       Challenge/verify auth flow
  KeychainHelper.swift        Secure key and token persistence
  BiometricLockManager.swift  Face ID / biometrics privacy gate
  DailyPromptNotificationManager.swift
                              6:00 AM local reminder scheduling
  AnkyWritingSession.swift    Legacy NOW writing state machine and completion flow
  WritingSessionStore.swift   Legacy drafts plus live session snapshot persistence
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
xcodebuild test -scheme Anky -project Anky.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:AnkyTests/AnkyFlowTests
```

The strongest local verification from this machine is currently:

- simulator build
- focused `AnkyFlowTests` execution on `iPhone 17 Pro` / `iOS 26.3.1`
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
