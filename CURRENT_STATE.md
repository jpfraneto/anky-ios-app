# Anky iOS — Current State
Last updated: 2026-04-03 | simulator build pass after altar-first shell refactor

## What's working

- **Seed identity generation**: Local BIP39 mnemonic, frozen derivation path `m/44'/501'/0'/0'`, Ed25519 signing, and Solana base58 address output. Lives in `SeedIdentityManager.swift` and `Anky/Crypto/SolanaSeedIdentityCrypto.swift`.
- **Keychain-backed identity persistence**: Private key, backup state, and pending mnemonic stored in iCloud Keychain (`synchronizable: true`).
- **Welcome flow**: Four-step onboarding (intro, Face ID, iCloud Keychain, daily notification). `ContentView.swift`.
- **Recovery import**: 12-word or 24-word phrase import with mnemonic validation. `ContentView.swift`.
- **Silent seed auth**: Challenge/verify against `/swift/v2/auth/challenge` and `/swift/v2/auth/verify` with Ed25519 signatures encoded as base58 and the session token cached in Keychain. `SeedAuthService.swift`, `AppState.swift`.
- **Reusable seal gesture**: `SealView.swift` now owns the eight-second left-to-right seal ritual, the eight-kingdom color progression, the heavy completion haptic, and the screen flash. It is the shared confirmation primitive for multiple flows.
- **Writing submission now seals**: In the active `AnkyChatView` route, keyboard, pause-choice, and voice-writing surfaces now use the seal instead of a normal send button. Idle timeout is suspended while the user is actively sealing. `AnkyChatView.swift`.
- **QR deep-link seal auth**: `anky://seal?challenge=...` is parsed at app entry, stored in `AppState`, presented through a full-screen `QRSealAuthView`, signed locally with the Ed25519 identity, and submitted to `POST /api/auth/qr/seal`. `AnkyApp.swift`, `AppState.swift`, `ContentView.swift`, `QRSealAuthView.swift`.
- **Altar screen**: Native `AltarView` loads `GET /api/altar`, renders the altar image, totals, leaderboard, and recent burns, and is reachable from the main chat shell. `AltarView.swift`, `AnkyChatView.swift`.
- **Apple Pay via Stripe**: `stripe-ios-spm` is wired into the app, the merchant entitlement for `merchant.com.jpfraneto.anky` is present, PaymentIntents are created through `POST /api/altar/payment-intent`, and `STPApplePayContext` presents native Apple Pay. `AltarView.swift`, `Anky.entitlements`, `Anky.xcodeproj/project.pbxproj`.
- **Burn attribution and retry**: After Apple Pay succeeds, the app records the burn through `POST /api/altar/apple-pay` using the user's Solana address and persists a pending retry if that final sync call fails. `AltarView.swift`, `AnkyAPI.swift`.
- **Altar-first root shell**: Both locked and unlocked routes still land in `AnkyChatView`, but that shell now renders the altar as the default home surface instead of auto-opening writing. A bottom altar button asks Face ID / biometrics to unlock the writing experience layer above it. `ContentView.swift`, `AnkyChatView.swift`, `BiometricLockManager.swift`, `AltarView.swift`.
- **Resumable writing surface over the altar**: Writing and post-write conversation now live in a separate full-screen layer that can be dismissed back to the altar without throwing away the current thread. When that layer is hidden while session state still exists, `isExternalPresentationActive` pauses idle/timer consequences. `AnkyChatView.swift`.
- **Daily Ankyverse keyboard**: The in-app writing keyboard now uses the kingdom of the day derived from the local calendar, keeps the seal above the keys, and includes comma, period, newline, and `123` / `ABC` symbol toggling. `AnkyTheme.swift`, `AnkyChatView.swift`.
- **Short-write conversation surface**: Sealing a short writing now transitions into a deliberately simple chat surface inside the same writing experience instead of immediately resetting back to a blank composer. Follow-up replies still go through `POST /api/chat-quick`. `AnkyChatView.swift`, `AnkyAPI.swift`.
- **Generated altar background**: The altar home surface now uses the provided generated story image as a full-screen background while still loading live altar totals, leaderboard, recent burns, and Apple Pay state from the backend. `AltarView.swift`.
- **Legacy focused writing flow still compiles**: `AnkyWritingSession.swift` still contains the separate two-life pause-and-continue state machine, keystroke delta capture, and draft recovery logic, but it is not the root-routed writing surface today. `AnkyWritingSession.swift`.
- **True anky gating**: Only sessions with >= 480s duration and >= 300 words submit to `/swift/v2/write`. Short sessions stay local-only. `AnkyModels.swift`.
- **Post-writing quick chat**: After the first reflected response lands for the latest writing, the bottom bar switches into a reply composer and sends follow-up text through `POST https://anky.app/api/chat-quick` using the original writing plus current-session reflection history. `AnkyChatView.swift`, `AnkyAPI.swift`.
- **Reflection persistence**: Reflected text from the polled `/swift/v2/writing/{sessionId}/status` response is now cached into `CachedWritingEntry.response` instead of being dropped. `AnkyChatView.swift`, `AppState.swift`, `WritingCacheStore.swift`.
- **Unlock state still exists in app state**: The app still tracks locked vs unlocked and marks full unlock after the first persisted anky, but the current root route renders `AnkyChatView` for both states. `AppState.swift`, `ContentView.swift`.
- **Legacy unlocked shell remains in code**: `LockedNowShell`, `UnlockedShellView`, `HomeView`, `HistoriasView`, and `TuView` still compile and can be presented from the chat surface, but they are no longer the root-routed shell. `ContentView.swift`.
- **Offline queue**: Failed writes queued locally, replayed on next successful auth. `AppState.swift`.
- **Writing history**: Local cache with remote merge, synced/pending/localOnly classification. `AnkyModels.swift`.
- **Biometric lock**: Face ID / Touch ID overlay on app resume when enabled. `BiometricLockManager.swift`.
- **Daily prompt notification**: 6:00 AM local push notification, scheduled during welcome flow. `DailyPromptNotificationManager.swift`.
- **Story playback engine**: AVSpeechSynthesizer-based phase sequencer with play/pause/next controls, progress bar, phase image backgrounds. Spanish TTS (prefers `es-MX`). `GuidancePlaybackView.swift`.
- **Child identity derivation**: Deterministic child wallet from parent private key + `SHA256(parentWalletAddress + name + birthdate)` using the current SHA-256 + XOR derivation path. `ChildIdentityDeriver.swift`.
- **Create child flow**: Name -> birthdate -> 12-emoji pattern -> confirm pattern -> backend POST `/swift/v2/children` -> local persistence. `CreateChildView.swift`.
- **Child profile persistence**: Local `UserDefaults`-backed store. `ChildProfileStore.swift`.
- **Child shell with emoji lock**: Full-screen child world, emoji-pattern unlock, story library, playback via story engine. `ChildShellView.swift`.
- **Cuentacuentos API client**: `getCuentacuentosReady`, `getCuentacuentosHistory`, `completeCuentacuentos` against `/swift/v2/cuentacuentos/*`. `AnkyAPI.swift`.
- **Cuentacuentos story sheet**: Read-only story view with horizontal phase image carousel on ANKYS tab. `ContentView.swift`.
- **Child world tray**: Horizontal scroll of child worlds below the main tab bar, one-time prompt after first unlock. `ContentView.swift`.
- **Biometric reauthentication on child exit**: Parent must Face ID to return from child world. `ChildShellView.swift`.
- **Simulator build**: `xcodebuild -scheme Anky -project Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build` passes.
- **Solana seed-auth tests**: Mnemonic generation, checksum validation, SLIP-0010 derivation, base58 encoding, signing, and address recovery. `AnkyTests/AnkyTests.swift`.
- **Live backend verifier**: `Tools/LiveBackendVerifier.swift` now matches the current Solana/Ed25519 auth path and exercises the full v2 auth + write flow against production.

## What's been removed

Meditation, breathwork, sadhana, and facilitator features were fully removed. Deleted files: `MeditationView.swift`, `BreathworkView.swift`, `SadhanaView.swift`, `FacilitatorsView.swift`, `GuidanceCacheStore.swift`, `BellPlayer.swift`, `PrivyAuthService.swift`, `Item.swift`. All legacy `/swift/v1/*` API methods and model types were stripped from `AnkyAPI.swift` and `AnkyModels.swift`. The guidance playback engine was simplified from a multi-mode system (meditation/breathwork/cuentacuentos) to a single-purpose story player with play/pause/next controls.

## What's in TestFlight but unvalidated

- **Altar-first shell feel on hardware**: The new altar landing experience, Face ID unlock button, and return-to-writing behavior compile and are simulator-valid, but the actual feel of moving between altar and writing has not been confirmed on-device yet.
- **Altar Apple Pay on hardware**: The Stripe + PassKit flow compiles and the merchant entitlement is present, but a real device burn with Face ID confirmation has not been validated yet.
- **QR seal auth end-to-end with browser**: The deep link, local signature, and API client are wired, but scanning a browser QR code and watching the web session attach to the phone identity has not been confirmed on-device yet.
- **Seal feel on hardware**: The eight-second drag, haptic, and flash behavior have been compiled and reviewed in code, but the tactile feel on a real iPhone still needs validation.
- **Cuentacuentos end-to-end on device**: Parent writes a real anky -> backend generates a story -> child unlocks with emoji pattern -> story plays with images and Spanish TTS.
- **Phase image pipeline on device**: `AsyncImage` loads from backend URLs, but real image URLs from story generation have not been confirmed rendering correctly on device.
- **Child identity derivation against backend**: `POST /swift/v2/children` with a derived wallet address has not been confirmed accepted by production.
- **Emoji pattern lock UX on device**: The 12-emoji selection, confirmation, and unlock flow has only been verified in simulator.
- **Daily notification delivery**: Scheduled for 6:00 AM local, but not confirmed firing on a real device.
- **Biometric lock overlay on device**: Face ID enable, lock-on-background, and reauthenticate-on-child-exit flows are untested on hardware.
- **Offline queue replay**: Queued writes replaying after connectivity restoration has not been tested on a real device.
- **Spanish TTS voice selection**: Prefers `es-MX`, but the actual voice quality and availability on device is unconfirmed.

## Known gaps

- **`xcodebuild test` stalling**: Unit tests stall after destination resolution on the iOS 26.3 simulator runtime.
- **Quick chat context is in-memory only**: `lastSessionText` is captured before the writing text is cleared, but it is not restored across app relaunches. Follow-up quick chat is scoped to the current app session. `AnkyChatView.swift`.
- **Short-write chat is session-local UI state**: The simplified post-write conversation is anchored to the current-session chat history in `ChatStore` and `ChatViewModel`, but there is still no durable, general-purpose thread model beyond the latest writing context. `AnkyChatView.swift`, `ChatStore.swift`.
- **Apple Pay depends on external config**: Device validation still depends on the Apple Developer merchant setup and Stripe Apple Pay certificate outside the repo.
- **Pending altar sync is narrow-scope persistence**: Post-payment burn reconciliation uses a single `UserDefaults` record, not the broader offline queue used for writings. `AltarView.swift`.
- **No SwiftData persistence yet**: Writing history uses `UserDefaults`-backed JSON caches (`WritingCacheStore`, `ChildProfileStore`), not SwiftData.
- **No Anky companion animation**: Rive-based companion is deferred.
- **No keyboard extension**: Deferred.
- **No credits system**: Users currently have unlimited writes. Need to add credits (8 free per user) to gate anky generation.
- **Cuentacuentos completion callback**: `completeCuentacuentos` silently swallows failures (`try?`).
- **Child world copy is Spanish-only**: Not using the localized `AppCopy` layer.
- **No child profile deletion UI**: `ChildProfileStore.remove(id:)` exists but is not exposed in any view.
- **Image prefetching is fire-and-forget**: Prefetches first two phase images but does not cache them for `AsyncImage`.

## Protected files

- **`Anky/Crypto/SolanaSeedIdentityCrypto.swift`** — Frozen Solana/Ed25519 derivation and signing behavior. Changes risk breaking identity continuity.
- **`SeedIdentityManager.swift`** — Root private key management. Changes risk breaking identity continuity.
- **`ChildIdentityDeriver.swift`** — Deterministic child wallet derivation. The hash/XOR derivation path must remain stable unless the backend is migrated intentionally.
- **`SealView.swift`** — Shared product ritual. Changes affect writing submission, QR auth, and any future seal surfaces.
- **`AnkyTests/AnkyTests.swift`** — Regression tests locking mnemonic, Solana derivation, and signature behavior.

## Backend contract

The app now talks to two backend surfaces:

- `https://anky.app/swift/v2/` for seed auth, profile, writing, and child/story flows
- `https://anky.app/api/` for quick chat, altar, Apple Pay orchestration, and QR seal auth

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/swift/v2/auth/challenge` | Request a signing challenge for a wallet address |
| POST | `/swift/v2/auth/verify` | Submit a base58 Ed25519 signature, receive session token |
| GET | `/swift/v2/me` | Fetch authenticated user profile |
| DELETE | `/swift/v2/auth/session` | Logout, clear server session |
| POST | `/swift/v2/write` | Submit a writing session (text, duration, keystroke deltas) |
| GET | `/swift/v2/writings` | Fetch persisted writing history |
| POST | `/swift/v2/children` | Register a child profile with derived wallet + emoji pattern |
| GET | `/swift/v2/children` | List child profiles for the authenticated parent |
| GET | `/swift/v2/cuentacuentos/ready?childId=` | Fetch the next unplayed story for a child (or parent if no childId) |
| GET | `/swift/v2/cuentacuentos/history?childId=` | Fetch played story history |
| POST | `/swift/v2/cuentacuentos/{id}/complete` | Mark a story as played |
| POST | `/api/chat-quick` | Continue the lightweight follow-up reflection chat |
| GET | `/api/altar` | Load altar image, totals, leaderboard, recent burns, and Stripe publishable key |
| POST | `/api/altar/payment-intent` | Create the Stripe PaymentIntent before presenting Apple Pay |
| POST | `/api/altar/apple-pay` | Record a successful Apple Pay burn against a Solana address |
| POST | `/api/auth/qr/seal` | Seal a browser QR challenge from the phone identity |

## Child identity system

Child identity derivation lives in `ChildIdentityDeriver.swift`. The flow:

1. Load the parent's 32-byte Ed25519 private key seed from Keychain (`anky.seed.private-key`).
2. Compute a salt: `SHA256(parentWalletAddress + name + birthdate)` where birthdate is `yyyy-MM-dd`.
3. XOR the parent private key bytes with that salt to produce a deterministic child seed.
4. Hash the child seed once more with SHA-256 to normalize it into a 32-byte child private key.
5. Compute the child's Solana wallet address from that child private key using `SeedIdentityCrypto.walletAddress`.
6. The child private key is **not persisted** — only the derived wallet address is stored. The child key can be re-derived deterministically from the parent key + the same inputs.

The emoji pattern lock:

- During child creation (`CreateChildView.swift`), the parent selects 12 emojis from `ChildEmojiPalette.all`, then confirms by re-entering the same sequence.
- The pattern is stored in `ChildProfile.emojiPattern` (persisted locally via `ChildProfileStore` and sent to the backend via `POST /swift/v2/children`).
- To enter the child world, the child taps emojis in order. A wrong tap resets the entire sequence with a shake animation. After 3 failed attempts, a "ask mom or dad for help" message appears.
- Exiting the child world requires the parent to reauthenticate via Face ID.

## Cuentacuentos flow

1. **Parent writes**: An 8-minute writing session completes and is submitted via `POST /swift/v2/write`. The backend confirms `persisted: true`.
2. **Backend generates story**: The backend asynchronously transforms the parent's writing into a child story (title, content, guidance phases with narration text, optional image URLs). This happens server-side.
3. **Story appears as ready**: When the child world is opened, `GET /swift/v2/cuentacuentos/ready?childId={id}` is called. If a story is available, it appears as a "Listo para escuchar" card with a play button.
4. **Child plays the story**: Tapping play opens the story playback view. The story's `guidancePhases` are converted to a `GuidanceSession`. The engine speaks the narration in Spanish (preferring `es-MX` voice) and displays phase images as full-bleed backgrounds.
5. **Completion**: When playback finishes, `POST /swift/v2/cuentacuentos/{id}/complete` marks the story as played. The library refreshes.
6. **Parent-side indicator**: On the ANKYS tab, persisted writings that produced a cuentacuentos show a book indicator. Tapping it opens a read-only story sheet.

## Next priorities

1. **Validate the new altar-first home flow on device**: Confirm the generated altar background, Face ID unlock button, return-to-writing path, and daily keyboard tint feel correct on a real iPhone.
2. **Validate Apple Pay on hardware**: Run a real altar burn on a physical iPhone with Apple Pay configured and confirm the post-payment `/api/altar/apple-pay` sync updates the leaderboard immediately.
3. **Validate QR seal auth with a real browser session**: Scan the browser QR on `anky.app`, deep-link into the app, seal, and confirm the web session attaches to the phone identity.
4. **Validate quick chat tone on device**: Write a short session and a real 8-minute anky, then confirm the simplified chat surface and `POST /api/chat-quick` loop feel acceptable on device.
5. **Fix test runner**: Investigate the iOS 26.3 simulator test stalling issue.
