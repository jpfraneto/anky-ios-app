# Anky iOS — Current State
Last updated: 2026-04-16 | server reachability and runtime environment indicator, canonical local-archive-first runtime cutover, live session-hash snapshot/proof reconciliation, proof-aware archive/profile status, canonical local archive source-of-truth promotion, legacy backend-history demotion for canonical Anky completion, local-vs-remote merge hardening, runtime cutover tutorial/docs handoff, local-archive normalization onto `AnkySessionBundle` and `LocalArchiveRecord`, canonical retry payload retention, contract-foundation bundle/archive/proof models, centralized qualification/title/artifact validators, explicit legacy path labeling, settings connected-device management, premium subscription sheet preview, settings formalities links, custom settings card layout, in-app legal/help Safari presentation, profile-v2 archive redesign, inline profile conversation sheets, preserved profile metadata, writing-entry transition polish, chat-scroll/copy/haptics polish, full-screen recovery presentation, writing-feedback polish, backup-flow viewport fix, sealing stream completion fix, skip-path streaming parity, immediate pending archive truth, profile-side pending anky resend fallback, automatic pending anky retry on launch/login, writer-dismiss crash hardening, and focused flow-test pass

## What's working

- **Seed identity generation**: Local BIP39 mnemonic, frozen derivation path `m/44'/501'/0'/0'`, Ed25519 signing, and Solana base58 address output. Lives in `SeedIdentityManager.swift` and `Anky/Crypto/SolanaSeedIdentityCrypto.swift`.
- **Keychain-backed identity persistence**: Private key, backup state, and pending mnemonic stored in iCloud Keychain (`synchronizable: true`).
- **Recovery phrase backup flow now fits the viewport**: `SeedPhraseBackupView` now wraps each ceremony phase in a geometry-aware vertical scroll container, and both settings/profile now present that ceremony as a full-screen cover instead of a cramped nested sheet. The recovery copy, 12-word reveal, and swipe-to-secure controls stay reachable on smaller iPhones instead of overflowing past the screen. `SeedPhraseBackupView.swift`, `SettingsView.swift`, `ProfileView.swift`.
- **Welcome flow**: Four-step onboarding (intro, Face ID, iCloud Keychain, daily notification). `ContentView.swift`.
- **Recovery import**: 12-word or 24-word phrase import with mnemonic validation. `ContentView.swift`.
- **Silent seed auth**: Challenge/verify against `/swift/v2/auth/challenge` and `/swift/v2/auth/verify` with Ed25519 signatures encoded as base58 and the session token cached in Keychain. `SeedAuthService.swift`, `AppState.swift`.
- **Chat-first root shell with writing-first entry**: `ContentView.swift` now routes directly into `AnkyChatView`. Fresh launches default into the writing overlay, but deeplinks win and can open QR login, shared Ankys, `Now` rooms, or prompt-specific writing instead of being covered by the writer. The visible chat header is now reduced to the hamburger/profile entry. `ContentView.swift`, `AnkyChatView.swift`, `AnkyApp.swift`, `AppState.swift`.
- **Runtime environment + reachability indicator**: `ServerIndicator.swift` now pings the active backend root with a quiet `HEAD` request every 30 seconds and renders a tiny top-right health dot across the main chat, writing, and profile surfaces. Debug builds also show a monospaced environment label beside the dot (`staging` for the current runtime-cutover setup); release builds keep only the dot so the affordance stays invisible to normal users. `ServerIndicator.swift`, `AnkyChatView.swift`, `AnkyProfileView.swift`, `AnkyAPI.swift`.
- **Native Flux generation**: `GenerateView.swift` now hits `POST /api/v1/generate` for Flux prompt generation, shows an obvious in-progress activity card while the request is being sent and while the backend is still rendering, polls `GET /api/v1/anky/{id}` until completion, persists pending/completed generations locally so interrupted native generations can recover when the view is reopened, and lets the user save finished generated images directly to Photos from the detail sheet. `GenerateView.swift`, `GeneratedAnkyStore.swift`, `AnkyAPI.swift`, `Info.plist`.
- **Generated Anky collage gallery**: The native generate route now shows a collage grid of Ankys with the user's locally completed generations first and the broader generated feed loaded from `GET /api/ankys?origin=generated` underneath. Tapping a tile opens the full prompt/reflection detail. `GenerateView.swift`, `AnkyAPI.swift`, `AnkyModels.swift`.
- **Reusable seal gesture**: `SealView.swift` still owns the eight-second left-to-right ritual, kingdom color progression, heavy completion haptic, and flash. It remains the shared confirmation primitive for QR auth, altar flows, and legacy/voice writing surfaces. `SealView.swift`, `AnkyChatView.swift`, `QRSealAuthView.swift`, `AltarView.swift`.
- **Forward-only active composer**: The active typed writing path now uses one UIKit-backed `UITextView` that blocks delete, return, paste, autocorrect, autocapitalization, spellcheck, smart substitutions, and the QuickType bar. Typed sessions are append-only. `AnkyComposerTextView.swift`, `AnkyChatView.swift`.
- **Dedicated writing overlay**: The active writing surface now opens as its own overlay instead of pretending to be the bottom chat field growing upward. The prompt now always stays owned by the `UITextView` placeholder path until there is real text, the top and bottom bars are both visible before the first keystroke, the text view is inset so new lines stay above the bottom chrome, the visible writing area is clearly bounded between the idle warning bar and the bottom session bar, and the chat-to-writing handoff now enters as one continuous full-screen motion instead of a blank staged reveal. `AnkyChatView.swift`, `AnkyComposerTextView.swift`.
- **Canonical `.anky` file output**: The active chat-first writer and the legacy writer now convert literal spaces into `SPACE`, capture the absolute millisecond timestamp of the first keystroke at input time, build protocol-compliant `.anky` files with that epoch on line 1, write the immutable file under `ankys/yyyy/mm/dd/{session_hash}.anky`, verify the SHA-256 hash against the filename immediately after write, and carry the file path/hash forward with the session capture. The active live-session path also writes `partial_{sessionId}.anky` every 300ms so crash recovery can resume and later seal the same session canonically. `AnkySessionFileStore.swift`, `AnkyChatView.swift`, `AnkyWritingSession.swift`, `WritingSessionStore.swift`, `AnkyModels.swift`, `AnkyAPI.swift`.
- **Canonical contract foundation and local archive now drive the live runtime**: `AnkyContractFoundation.swift` defines the locked session-bundle/archive/proof vocabulary, `LocalArchiveStore.swift` persists `LocalArchiveRecord` as the canonical local archive, `AppState` owns `localArchiveRecords`, and the active profile/history/archive surfaces now derive primarily from that archive instead of treating `CachedWritingEntry` or backend history as the source of truth. `writingHistory` still exists, but only as a compatibility projection. `AnkyContractFoundation.swift`, `LocalArchiveStore.swift`, `AppState.swift`, `AnkyProfileView.swift`, `AnkyChatView.swift`, `PendingAnkyRetryService.swift`, `WritingCacheStore.swift`, `AnkyModels.swift`, `AnkyAPI.swift`.
- **Canonical processor readback/proof runtime cutover is now live**: accepted `/api/anky/submit` sessions now reconcile title, reflection, image, proof, and backend anky id through `GET /api/anky/sessions/{session_hash}` and `GET /api/anky/sessions/{session_hash}/proof`. `SealingView`, the background-skip path in `AnkyChatView`, `PendingAnkyRetryService`, daily prompt recovery, and `AppState.refreshWritings()` all now route active canonical completion through those session-hash surfaces instead of `GET /swift/v2/writing/{sessionId}/status`. `AnkyModels.swift`, `AnkyAPI.swift`, `AppState.swift`, `SealingView.swift`, `AnkyChatView.swift`, `PendingAnkyRetryService.swift`.
- **Post-write sealing intercept**: When the active chat-first writing session ends, chat no longer reveals immediately. `AnkyChatView` now intercepts the `pendingCapture`, presents a full-screen `SealingView`, and only drops the writing surface once the user swipes to seal or explicitly skips. `AnkyChatView.swift`, `SealingView.swift`.
- **Bottom-docked short-message composer**: The collapsed main chat dock now pins explicitly to the bottom safe area, uses actual keyboard overlap for message-list padding, and keeps a stable left hourglass / center field / right pen-or-send layout. The right action glows as a pen in idle state and swaps immediately to send when text exists. `AnkyChatView.swift`, `ContentView.swift`.
- **Writing timing and exit behavior are calmer**: The idle warning bar now stays hidden for the first 3 seconds of silence, then drains from right to left over the remaining 5 seconds. The red exit button disappears as soon as writing begins, the timer row only stays visible during the first 20 seconds, the keyboard dismisses immediately when the close button is tapped, and the writing surface now emits haptics on open, meditation-timer start, and the final second before idle timeout. `AnkyChatView.swift`, `MeditationTimerView.swift`.
- **Writing close no longer tears down the composer unsafely**: The red close path now ends editing on the active key window, waits one main-loop turn before dismissing the writer, and the UIKit-backed `AnkyComposerTextView` now cancels stale async focus work plus resigns cleanly in `dismantleUIView`. That prevents the untouched writing overlay from crashing during first-responder teardown. `AnkyChatView.swift`, `AnkyComposerTextView.swift`.
- **Live autosave and recovery**: Active text now saves on every keystroke with a 300ms debounce into a live snapshot, restores on app relaunch / foreground resume, and clears only when the session is discarded or sent. `WritingSessionStore.swift`, `AnkyChatView.swift`, `AppState.swift`.
- **8-minute threshold effect and auto-send**: Crossing 8 minutes now triggers a centered full-screen golden overlay, haptic burst, and an automatic send path once the short celebration ends. `AnkyChatView.swift`.
- **Streaming submit path for the active writer**: The chat-first writing flow now signs the local `.anky` session hash with `SeedIdentityManager`, submits through `POST /api/anky/submit`, and parses SSE events for accepted/title/reflection/image/done. `SealingView` records the pending anky into the canonical local archive before the stream finishes, and the skip/background path in `AnkyChatView` now does the same instead of waiting for the whole backend cycle to resolve first. Reflection chunks still accumulate in `ChatViewModel`, and a normal stream close after acceptance now still resolves instead of hanging forever on the loading dots. `AnkyAPI.swift`, `AnkyChatView.swift`, `SealingView.swift`, `AnkyTheme.swift`.
- **Post-writing chat sequencing**: After a session sends, the raw user writing appears first as a copyable chat bubble, then Anky's reflection appears, then the generated image arrives as its own fixed-height message bubble. The chat surface now pins itself to the bottom immediately as messages and typing state change, the copy affordance flips inline from `copy` to `copied` with haptic confirmation instead of using a toast, and both the sealing path and the skip/background path stream reflection/title/image data back into the canonical local archive as soon as it exists. `AnkyChatView.swift`, `WritingCacheStore.swift`, `AppState.swift`.
- **Settings preview reflects actual writing size**: The settings text-size preview now renders its sample line at the live selected writing point size, so the user sees the real writing scale instead of a fixed placeholder size. `SettingsView.swift`.
- **Settings formalities live inside the native modal**: `SettingsView` now uses a custom dark card layout instead of `Form`, so the sheet matches the quieter Anky chrome. The modal now includes a dedicated formalities section with Terms of Service, Privacy Policy, and Frequently Asked Questions, each opening its `https://anky.app/*.md` document inside an in-app Safari sheet instead of ejecting the user from the settings flow. `SettingsView.swift`, `AnkyProfileView.swift`.
- **Settings connected-device management lives in the same sheet**: `SettingsView` now includes a Connected Devices section that asks `/swift/v2/auth/sessions` for the account's active sessions, keeps the current iPhone pinned locally when the backend list is unavailable, supports pull-to-refresh, and lets the user revoke non-current devices without leaving settings. `SettingsView.swift`, `AnkyAPI.swift`, `AnkyModels.swift`.
- **Premium preview now opens as a native bottom sheet**: The settings modal now includes a `Subscribe to Premium` row that opens a custom bottom sheet with plan selection, legal links, restore placeholder behavior, and the footer copy `Created with 💚 by Anky, Inc.` at the bottom of settings. Checkout remains an honest preview until StoreKit exists. `SettingsView.swift`.
- **Per-anky conversation threads**: Follow-up chat after a reflected real anky is now mirrored into `AnkyThreadChatStore`, so the active profile sheet can reopen the original writing, the first reflection, and later replies as one thread. Archived replies now try `POST /api/anky/{id}/conversation` when a real backend anky id exists, and fall back to `POST /api/chat-quick` for older/local-only sessions. `AnkyChatView.swift`, `AnkyProfileView.swift`, `AnkyThreadChatStore.swift`, `AnkyAPI.swift`.
- **UTC daily archive behavior**: Chat history now loads per UTC day, starts a fresh conversation when the day rolls, and keeps older days archived instead of deleting them. `ChatStore.swift`, `AnkyChatView.swift`.
- **Profile v2 archive surface**: `AnkyProfileView` now owns the active profile/archive experience with a compact hero row, locally derived points/level/streak/words, three stat buttons, a real-anky list with image/title/writing previews, a tappable month grid that expands that day's ankys, and a territories section that lists all eight kingdoms with progress bars and drill-in sheets. `AnkyProfileView.swift`, `AnkyTheme.swift`.
- **Profile conversation and kingdom sheets**: Tapping an archived anky now opens a large bottom sheet with the writing, first reflection, stored follow-ups, inline reply composer, auto-scroll-to-bottom behavior, and for pending real ankys a `send again` fallback action that retries backend processing from the same canonical `.anky` payload. The same pending-anky retry service also runs automatically after launch/login auth refresh, so older stalled ankys can heal themselves before the user opens profile. Tapping a territory opens a medium kingdom detail sheet. `AnkyProfileView.swift`, `PendingAnkyRetryService.swift`, `AnkyThreadChatStore.swift`, `AnkyAPI.swift`, `AppState.swift`.
- **Processed Anky history decode is more tolerant**: `WritingItem` now accepts flat `/swift/v2/writings` fields including `response`, `anky_reflection`, `anky_title`, `anky_image_path`, `flow_score`, `kingdom`, `energy`, and `reason`, plus nested `anky` payloads for title, reflection, image, and id, so processed sessions can repopulate profile/history and territory stats correctly after relaunch. `AnkyModels.swift`, `WritingCacheStore.swift`, `AnkyProfileView.swift`.
- **Stable image layout**: Chat, profile, and detail surfaces now render generated images inside fixed-height containers with matched placeholders and lightweight prefetching, so loaded images no longer collapse or shift surrounding layout. `AnkyChatView.swift`, `AnkyProfileView.swift`, `AnkyModels.swift`.
- **QR deep-link seal auth**: `anky://seal?challenge=...` is parsed at app entry, stored in `AppState`, presented through a full-screen `QRSealAuthView`, signed locally with the Ed25519 identity, and submitted to `POST /api/auth/qr/seal`. `AnkyApp.swift`, `AppState.swift`, `ContentView.swift`, `QRSealAuthView.swift`.
- **Shared generated-Anky deeplink presentation**: Universal links under `https://anky.app/anky/{id}` now open a native full-screen detail surface that fetches the shared generated Anky instead of dropping the user into the default writing overlay. `AnkyApp.swift`, `AppState.swift`, `AnkyChatView.swift`, `AnkyAPI.swift`.
- **Altar screen**: Native `AltarView` loads `GET /api/altar`, renders the altar image, totals, leaderboard, and recent burns, and is now reached from the profile support sheet rather than the main chat header. `AltarView.swift`, `ProfileView.swift`.
- **Apple Pay via Stripe**: `stripe-ios-spm` is wired into the app, the merchant entitlement for `merchant.com.jpfraneto.anky` is present, PaymentIntents are created through `POST /api/altar/payment-intent`, and `STPApplePayContext` presents native Apple Pay. `AltarView.swift`, `Anky.entitlements`, `Anky.xcodeproj/project.pbxproj`.
- **Burn attribution and retry**: After Apple Pay succeeds, the app records the burn through `POST /api/altar/apple-pay` using the user's Solana address and persists a pending retry if that final sync call fails. `AltarView.swift`, `AnkyAPI.swift`.
- **Legacy focused writing flow still compiles**: `AnkyWritingSession.swift` still contains the separate two-life pause-and-continue state machine, keystroke delta capture, and draft recovery logic, but it is not the root-routed writing surface today. `AnkyWritingSession.swift`.
- **True anky gating**: Only sessions with >= 480s duration and >= 300 words continue into an Anky submit path. The active chat-first writer no longer submits short sessions through `/api/anky/submit`, cached `/swift/v2/writings` entries only count as real ankys if they also meet those thresholds locally, and real ankys now stay visible in history immediately as pending even if the user skips the sealing surface before backend persistence finishes. `AnkyModels.swift`, `AnkyAPI.swift`, `AnkyChatView.swift`, `WritingCacheStore.swift`, `AppState.swift`.
- **Post-writing quick chat**: After the first reflected response lands for the latest writing, the bottom bar switches into a reply composer and sends follow-up text through `POST https://anky.app/api/chat-quick` using the original writing plus current-session reflection history. `AnkyChatView.swift`, `AnkyAPI.swift`.
- **Unlock state still exists in app state**: The app still tracks locked vs unlocked and marks full unlock after the first persisted anky, but the current root route renders `AnkyChatView` for both states. `AppState.swift`, `ContentView.swift`.
- **Legacy unlocked shell remains in code**: `LockedNowShell`, `UnlockedShellView`, `HomeView`, `HistoriasView`, and `TuView` still compile and can be presented from the chat surface, but they are no longer the root-routed shell. `ContentView.swift`.
- **Offline queue**: Failed writes queued locally, replayed on next successful auth. `AppState.swift`.
- **Writing history**: Legacy projected cache derived from the canonical local archive, still carrying synced/pending/localOnly compatibility state for older surfaces. `AnkyModels.swift`, `AppState.swift`, `LocalArchiveStore.swift`.
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

- **Forward-only composer feel on hardware**: The UIKit-backed append-only text view compiles and behaves in simulator, but the actual keyboard feel, cursor behavior, and QuickType suppression still need confirmation on a real iPhone.
- **Chat-to-writing growth on hardware**: The single-composer transition from docked chat input to full-screen writing is simulator-valid, but the animation and keyboard-safe layout need real-device validation on both smaller and larger screens.
- **8-minute celebration on hardware**: The golden overlay, bar completion, and haptic cadence compile, but the tactile feel on a real device still needs validation.
- **Profile/archive browsing on hardware**: The new hero/stats/list/calendar/territories profile, large conversation sheet, and kingdom detail sheet compile and are simulator-valid, but the scrolling feel, sheet presentation, and image prefetch behavior still need device checks.
- **Fresh-launch writing feel on hardware**: The simplified placeholder-first writing overlay, delayed idle warning, right-to-left drain, short-lived timer row, hidden close button after typing starts, and safer bottom insets compile and feel correct in simulator, but the overall calmness and keyboard feel still need confirmation on a real iPhone.
- **Sealing screen feel on hardware**: The new swipe-to-seal track, pulse timing, success haptic, and transition into revealed chat compile and behave in simulator, but the tactile feel still needs confirmation on a physical iPhone.
- **Generated image saving on hardware**: The native save-to-Photos path compiles and the add-only Photos permission string is present, but the real permission prompt and save behavior still need confirmation on a physical iPhone.
- **Altar Apple Pay on hardware**: The Stripe + PassKit flow compiles and the merchant entitlement is present, but a real device burn with Face ID confirmation has not been validated yet.
- **QR seal auth end-to-end with browser**: The deep link, local signature, and API client are wired, but scanning a browser QR code and watching the web session attach to the phone identity has not been confirmed on-device yet.
- **Shared generated-Anky deeplinks on device**: `/anky/{id}` now resolves into a native detail surface, but opening a real shared Anky from Messages or Safari still needs device confirmation.
- **Cuentacuentos end-to-end on device**: Parent writes a real anky -> backend generates a story -> child unlocks with emoji pattern -> story plays with images and Spanish TTS.
- **Phase image pipeline on device**: `AsyncImage` loads from backend URLs, but real image URLs from story generation have not been confirmed rendering correctly on device.
- **Child identity derivation against backend**: `POST /swift/v2/children` with a derived wallet address has not been confirmed accepted by production.
- **Emoji pattern lock UX on device**: The 12-emoji selection, confirmation, and unlock flow has only been verified in simulator.
- **Daily notification delivery**: Scheduled for 6:00 AM local, but not confirmed firing on a real device.
- **Biometric lock overlay on device**: Face ID enable, lock-on-background, and reauthenticate-on-child-exit flows are untested on hardware.
- **Offline queue replay**: Queued writes replaying after connectivity restoration has not been tested on a real device.
- **Spanish TTS voice selection**: Prefers `es-MX`, but the actual voice quality and availability on device is unconfirmed.

## Known gaps

- **Pending anky retry still depends on auth refresh cadence**: Pending real ankys now retry automatically on launch/login and can still be resent manually from profile, but there is still no always-on timer/network-reachability queue that keeps replaying failed `/api/anky/submit` jobs while the app stays open without another auth refresh. `AnkyAPI.swift`, `AnkyChatView.swift`, `AnkyProfileView.swift`, `PendingAnkyRetryService.swift`, `SealingView.swift`, `AppState.swift`.
- **Legacy compatibility surfaces still remain around the cutover**: canonical Anky completion no longer depends on `/swift/v2/writings` or `/swift/v2/writing/{sessionId}/status`, but `refreshWritings()` still merges `/swift/v2/writings` as a compatibility enrichment path, `writingHistory` still exists as a projected adapter for older UI, and legacy `applyPersistedAnkySuccess(...)` / `POST /swift/v2/write` behavior still remains for non-core surfaces like `AnkyWritingSession.swift`, `ProfileView.swift`, and `AnkyThreadsView.swift`. `AppState.swift`, `AnkyWritingSession.swift`, `ProfileView.swift`, `AnkyThreadsView.swift`, `LocalArchiveStore.swift`, `AnkyAPI.swift`.
- **Idempotent resubmit still needs device-level validation**: The backend now reportedly enforces `(user_id, session_hash)` idempotency for `/api/anky/submit`, and the iOS client is aligned with that contract, but a real device flow still needs to confirm that an interrupted anky retries into the same `anky_id` without duplicate side effects. `AnkyAPI.swift`, `PendingAnkyRetryService.swift`, backend `/api/anky/submit`.
- **iCloud Drive still depends on runtime availability**: The app target now carries iCloud Documents entitlements and the `.anky` writer attempts the ubiquity container `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)` first, but simulator and devices without iCloud Drive availability still fall back to the app's Documents directory. `Anky.entitlements`, `Anky.xcodeproj/project.pbxproj`, `AnkySessionFileStore.swift`.
- **Post-write quick chat context is still in-memory only**: `lastSessionText` is captured before the writing text is cleared, but it is not restored across app relaunches. Follow-up quick chat is still scoped to the current app session. `AnkyChatView.swift`.
- **Per-anky thread history is still reconstructed client-side on open**: `AnkyThreadChatStore` persists follow-up messages for each real anky on the current device, and the profile sheet can continue a thread through `POST /api/anky/{id}/conversation`, but the backend still does not provide a canonical `GET` endpoint for the full historical post-reflection thread when the app first opens an older session. `AnkyThreadChatStore.swift`, `AnkyProfileView.swift`, `AnkyChatView.swift`, `AnkyAPI.swift`.
- **Connected-device backend contract is still provisional**: The settings client now expects `GET /swift/v2/auth/sessions` and `DELETE /swift/v2/auth/sessions/{id}` for the Connected Devices section, but it still falls back to showing only the current iPhone when that backend route is not live yet. `SettingsView.swift`, `AnkyAPI.swift`, `AnkyModels.swift`.
- **Premium billing is still UI-only**: The premium bottom sheet exists in settings, but plan pricing, purchase, and restore behavior are still placeholder interactions until StoreKit and any receipt/backend handling are wired. `SettingsView.swift`.
- **Legacy shells still teach older writing UI**: `ActiveWritingSessionView`, `HomeView`, and the legacy unlocked shell still compile with older checkpoint / word-count-era assumptions, but they are not the routed product surface now. `ContentView.swift`, `AnkyWritingSession.swift`.
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

- `https://anky.app/swift/v2/` for seed auth, profile, legacy writing surfaces, and child/story flows
- `https://anky.app/api/` for the active chat-first write submit stream, quick chat, altar, Apple Pay orchestration, and QR seal auth

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/swift/v2/auth/challenge` | Request a signing challenge for a wallet address |
| POST | `/swift/v2/auth/verify` | Submit a base58 Ed25519 signature, receive session token |
| GET | `/swift/v2/me` | Fetch authenticated user profile |
| DELETE | `/swift/v2/auth/session` | Logout, clear server session |
| GET | `/swift/v2/auth/sessions` | List connected account sessions for the settings Connected Devices surface |
| DELETE | `/swift/v2/auth/sessions/{id}` | Revoke a non-current connected device session from settings |
| POST | `/api/anky/submit` | Active chat-first writing submission with SSE events for accepted/title/reflection/image/solana/done |
| GET | `/api/anky/sessions/{session_hash}` | Canonical processor snapshot readback for title/reflection/image/status reconciliation after submit |
| GET | `/api/anky/sessions/{session_hash}/proof` | Canonical processor proof readback for proof status, receipt, proof URL, and sealing completion |
| POST | `/api/anky/{id}/conversation` | Continue a real archived anky conversation from the profile sheet when the backend anky id is known |
| POST | `/swift/v2/write` | Submit a writing session (text, duration, keystroke deltas) |
| GET | `/swift/v2/writings` | Legacy compatibility history enrichment for persisted sessions; no longer canonical completion truth for local Ankys |
| POST | `/swift/v2/children` | Register a child profile with derived wallet + emoji pattern |
| GET | `/swift/v2/children` | List child profiles for the authenticated parent |
| GET | `/swift/v2/cuentacuentos/ready?childId=` | Fetch the next unplayed story for a child (or parent if no childId) |
| GET | `/swift/v2/cuentacuentos/history?childId=` | Fetch played story history |
| POST | `/swift/v2/cuentacuentos/{id}/complete` | Mark a story as played |
| POST | `/api/chat-quick` | Continue the lightweight follow-up reflection chat |
| POST | `/api/v1/generate` | Queue a native Flux Anky generation from a prompt |
| GET | `/api/v1/anky/{id}` | Poll a generated Anky until the image and reflection are ready |
| GET | `/api/ankys?origin=generated` | Load the public generated-Anky gallery used by the native collage view |
| GET | `/api/my-ankys` | Load the authenticated user's generated Ankys when available |
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

1. **Parent writes**: In the active chat-first writer, an 8-minute writing session completes, hits the sealing intercept, and then submits via `POST /api/anky/submit`. Legacy writer surfaces still compile against `POST /swift/v2/write`.
2. **Backend generates story**: The backend asynchronously transforms the parent's writing into a child story (title, content, guidance phases with narration text, optional image URLs). This happens server-side.
3. **Story appears as ready**: When the child world is opened, `GET /swift/v2/cuentacuentos/ready?childId={id}` is called. If a story is available, it appears as a "Listo para escuchar" card with a play button.
4. **Child plays the story**: Tapping play opens the story playback view. The story's `guidancePhases` are converted to a `GuidanceSession`. The engine speaks the narration in Spanish (preferring `es-MX` voice) and displays phase images as full-bleed backgrounds.
5. **Completion**: When playback finishes, `POST /swift/v2/cuentacuentos/{id}/complete` marks the story as played. The library refreshes.
6. **Parent-side indicator**: On the ANKYS tab, persisted writings that produced a cuentacuentos show a book indicator. Tapping it opens a read-only story sheet.

## Next priorities

1. **Validate the active writing feel on hardware**: Confirm the forward-only composer, keyboard-safe layout, sealing swipe, copy affordance, and 8-minute celebration feel correct on both a small iPhone and a large iPhone.
2. **Validate Apple Pay on hardware**: Run a real altar burn on a physical iPhone with Apple Pay configured and confirm the post-payment `/api/altar/apple-pay` sync updates the leaderboard immediately.
3. **Validate deeplink-priority flows on device**: Confirm browser QR login, shared `/anky/{id}` links, and `Now` links all beat the default writing overlay on a real iPhone.
4. **Validate archive/profile flows on device**: Confirm the hero/stats/list/calendar/territories profile, large archived-conversation sheet, kingdom detail sheet, and daily UTC rollover feel correct on a real device.
5. **Live-verify the canonical readback/proof loop**: Run a real `POST /api/anky/submit` session end-to-end against the backend, confirm the reflection/image stream arrives on device, and confirm `GET /api/anky/sessions/{session_hash}` plus `/proof` settle the local archive into a proof-complete sealed anky even if processor completion is delayed.
