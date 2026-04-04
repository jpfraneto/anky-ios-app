# Changelog

This file tracks meaningful work on the Anky iOS app.

## How to update this file

- Add a new entry at the top for each material work session.
- Use `YYYY-MM-DD` dates.
- Keep the sections short and concrete.
- Prefer `Added`, `Changed`, `Fixed`, and `Verified`.
- Reference the user-facing behavior and the system integration, not just file edits.

## 2026-04-03

### Added

- Reusable eight-second `SealView` with the full kingdom color progression, heavy completion haptic, and screen flash so the same ritual can be reused for writing submission and browser QR auth.
- Native `AltarView` with live `/api/altar` data, leaderboard, recent burns, amount entry, and post-burn glow feedback.
- Stripe Apple Pay support through the `stripe-ios-spm` package, app entitlements for `merchant.com.jpfraneto.anky`, and native PaymentIntent confirmation through `STPApplePayContext`.
- QR deep-link seal auth for `anky://seal?challenge=...`, including local Ed25519 signing, base58 signature encoding, and `POST /api/auth/qr/seal`.
- A new JP tutorial lesson covering the seal architecture, Apple Pay flow, and QR auth path.
- A second JP tutorial lesson covering the altar-first shell, Face ID writing gate, daily keyboard theming, and the simplified post-write chat surface.

### Changed

- Replaced the active writing flow's send buttons with the eight-second seal in the keyboard, pause-choice, and voice-writing surfaces so writing is now "sealed" instead of tapped-to-send.
- Extended the root app state and URL handling so incoming seal links become a full-screen auth flow instead of ad-hoc navigation.
- Extended the API client and models with root web endpoints for altar reads, PaymentIntent creation, Apple Pay burn recording, and QR seal verification.
- Updated the repo docs to describe the current Solana/Ed25519 identity path and the new altar/seal behavior instead of the older EVM-focused notes.
- Reworked the active `AnkyChatView` shell so signed-in users now land on the altar instead of auto-opening writing, with a Face ID-gated bottom button that presents the writing experience above the altar.
- Updated the altar home surface to use the provided generated story image as a full-screen background while keeping the live altar data and Apple Pay flow intact.
- Reworked the in-app writing keyboard to use the current Ankyverse day from the calendar and added comma, period, newline, and `123` / `ABC` symbol toggling.
- Simplified the post-write continuation path so short writing now falls into a lightweight conversation surface inside the same writing experience instead of resetting back to blank space.

### Fixed

- Added pending burn-sync persistence so a successful Apple Pay charge can still be attached to the correct Solana identity if the final `/api/altar/apple-pay` call fails immediately afterward.

### Verified

- `curl -sS https://anky.app/api/altar`
- `xcodebuild -resolvePackageDependencies -project /Users/kithkui/Desktop/ankY/Anky.xcodeproj -clonedSourcePackagesDirPath /Users/kithkui/Desktop/ankY/.build/spm`
- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/ankY/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-03-30

### Added

- Lightweight follow-up conversation inside `AnkyChatView` so users can reply in text after the first reflected response to a writing session.
- Root web API support for `POST /api/chat-quick` with `QuickChatRequest`, `ChatHistoryItem`, and `QuickChatResponse` models.
- In-memory retention of the latest writing text so quick-chat replies stay grounded in the original session.

### Changed

- Switched the bottom chat input bar into a reply-composer mode after the latest writing receives an assistant response, while keeping a small new-writing button available.
- Built quick-chat history from the current-session thread after the latest writing message, excluding the writing payload itself and the pre-writing prompt messages.
- Reworked the active `AnkyChatView` session timer so it no longer auto-sends at 8 minutes; the timer now keeps counting, 8 minutes is a visual milestone only, and 8 seconds of idle pauses into explicit `send` / `keep writing` controls.

### Fixed

- Fixed local writing-history caching so the reflected response from `/swift/v2/writing/:sessionId/status` is stored instead of being dropped as `nil`.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-03-17

### Added

- Parent-to-child world flow with `ChildProfile`, `CreateChildRequest`, `Cuentacuentos`, `/swift/v2/children`, and `/swift/v2/cuentacuentos/*` client support.
- `ChildProfileStore`, `CreateChildView`, `ChildShellView`, and shared emoji-pattern UI components for local child profile persistence, emoji confirmation, and child-world unlocking.
- Deterministic on-device child wallet derivation from the parent private key plus `SHA256(parentWalletAddress + name + birthdate)`.

### Changed

- Extended the unlocked shell with a child-world tray below the existing tab bar and a one-time prompt after the first unlocked anky when no child worlds exist yet.
- Extended the shared guidance player with a `cuentacuentos` mode, Spanish voice preference, and a completion callback so child stories reuse the existing playback engine.
- Extended the `ANKYS` history cards with a `📖` indicator and read-only story sheet when a writing already produced a child story.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-03-16

### Added

- A four-step welcome flow that introduces the 8-minute practice, Face ID privacy, iCloud Keychain-backed seed storage, and a daily 6:00 AM local prompt notification.

### Changed

- Simplified the `NOW` writing footer into a responsive three-layer stack: visible writing line, progress bar, and status row.
- Moved the latest typed text into a right-anchored single-line strip so overflow stays clipped instead of stretching the viewport wider than the screen.
- Removed the visible `CONTINUE` pause button in favor of a text-only `type to resume` pause state after the first lost life.
- Normalized current routed-shell text styling onto the bundled Righteous font.

### Fixed

- Fixed the heart-drain animation so the active life now empties vertically instead of left-to-right.
- Fixed writing-session layout overflow so the screen stays bounded to the device width and hides excess content instead of expanding.
- Fixed the center glyph sizing again so it stays smaller and more stable while typing.

## 2026-03-16

### Added

- `Tools/LiveBackendVerifier.swift`, a repo-local production verifier that uses the shipped EVM derivation and `personal_sign` code to exercise `/swift/v2/auth/challenge`, `/swift/v2/auth/verify`, `/swift/v2/me`, and `/swift/v2/write`.

### Changed

- Updated the root docs and JP tutorial to remove the stale EVM backend-blocker note and point verification at the live verifier transcript instead.

### Verified

- Production `POST https://anky.app/swift/v2/auth/challenge` now accepts canonical `0x...` EVM wallet addresses.
- Production `POST https://anky.app/swift/v2/auth/verify` accepts the app's hex-prefixed EIP-191 `personal_sign` signature payloads.
- Production `GET https://anky.app/swift/v2/me` returns the expected wallet-backed identity after verify.
- Production short `POST https://anky.app/swift/v2/write` returns `persisted: false` and does not appear in `GET https://anky.app/swift/v2/writings`.
- Production real `POST https://anky.app/swift/v2/write` returns `persisted: true` and appears in `GET https://anky.app/swift/v2/writings`.

## 2026-03-16

### Added

- Canonical EVM seed identity support using a 24-word BIP39 phrase, the frozen derivation path `m/44'/60'/0'/0/0`, and Ethereum `personal_sign` / EIP-191 challenge signing.
- Vendored `libsecp256k1` and `keccak-tiny` sources, bridged into the Xcode target for deterministic local derivation, signing, and address recovery.
- Deterministic EVM seed-auth tests covering mnemonic generation, checksum validation, seed derivation, private key derivation, compressed and uncompressed public key output, checksum address output, and challenge signatures.

### Changed

- Replaced the new mobile seed identity model from the earlier Solana/Base58 implementation to the canonical EVM `0x...` wallet model.
- Changed `/swift/v2/auth/verify` signing payloads from Base58 to hex-prefixed Ethereum signatures.
- Updated README and JP tutorial guidance so the repo now teaches EVM seed identity as the source of truth.

### Fixed

- Fixed the app target build settings so the bridged crypto headers and vendored C sources compile on simulator builds.
- Fixed the vendored secp256k1 source so it compiles cleanly under the current Apple clang toolchain.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild build-for-testing -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'platform=iOS Simulator,id=F50867E4-26A0-481A-B6FC-1AAD3CA68F38'`
- The hosted backend was later aligned to accept canonical `0x...` addresses, so the live EVM auth blocker noted during this earlier pass is no longer current.

## 2026-03-16

### Added

- Local seed identity generation, backup-state tracking, recovery import, and Keychain-backed private-key persistence for the new mobile auth model.
- Silent `/swift/v2/auth/challenge` and `/swift/v2/auth/verify` login flow with backend session caching in Keychain.
- Root app routing for `backupCeremony`, `recoveryImport`, `locked`, and `unlocked`, with `hasLocalIdentity` separated from `hasUnlockedFullExperience`.
- Local writing draft persistence and recovery so interrupted `NOW` sessions can resume without losing text.
- Deterministic seed-auth tests covering mnemonic generation, checksum validation, seed derivation, the canonical EVM derivation path, public key output, checksum wallet output, and challenge signatures.
- A new JP tutorial lesson on seed identity, `/swift/v2/*`, and the locked-to-unlocked writing model.

### Changed

- Moved new identity, write, profile, and history work to `/swift/v2/*` as the canonical mobile path.
- Replaced the old auth-first shell with a seed-first flow: identity is created on first open, but the app stays locked until a persisted real anky exists.
- Made `persisted` from `/swift/v2/write` the source of truth for unlock and cloud history.
- Hid conversation/thread UI from the unlocked shell until a real thread API/client exists.
- Updated root docs and JP tutorial docs so the repo now describes seed identity and the `NOW` shell instead of presenting Privy as the primary path.

### Fixed

- Fixed writing history classification so short or non-persisted sessions stay local-only and never appear in the persisted ankys view.
- Fixed unlock timing so authentication alone does not unlock the full experience for a new seed identity.
- Fixed reboot identity behavior so local key material, backup state, in-progress drafts, and pending cached writes are cleared together.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild build-for-testing -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'platform=iOS Simulator,id=F50867E4-26A0-481A-B6FC-1AAD3CA68F38'`
- Live backend challenge creation, signature verification, session issuance, and `/swift/v2/me` lookup against `https://anky.app/swift/v2`
- `xcodebuild test` and `xcodebuild test-without-building` are still stalling after destination resolution on the iOS 26.3 simulator runtime on this machine

## 2026-03-16

### Added

- A localized write-session copy layer covering the supported device languages for the new landing, pause, resume, and completion strings.
- A JP tutorial lesson on the focused writing state machine, true-anky gating, and how the native client now decides what stays local versus what reaches the backend.
- Unit tests for true-anky qualification, legacy short-write migration, and the new write-copy fallback behavior.

### Changed

- Rebuilt the writing experience around a now-focused center glyph, a rhythm-scaled ribbon, and a two-life idle system with pause-and-continue behavior after the first loss.
- Simplified incomplete-session completion to a minimal retry state instead of reflection/loading surfaces.
- Limited `/swift/v1/write` submission to true ankys only, with local-only storage for short sessions and migration of older pending short writes already cached on-device.
- Refreshed profile state after successful real ankys so wallet data can catch up when the backend returns or reuses a wallet.

### Fixed

- Fixed resumed writing so the first printable character after a pause is preserved instead of being swallowed by the state transition.
- Fixed legacy offline queue behavior so older short writes do not keep syncing to the outdated mobile write route.
- Fixed the current-glyph idle behavior so it fades and fractures with the life drain instead of disappearing on a separate timer.
- Fixed the writing viewport so the center glyph and bottom ribbon now lay out against the visible screen above the keyboard instead of the full device height.
- Fixed the hidden composer so paste payloads are discarded through UIKit paste delegates in addition to the existing backspace and edit blocking.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild test -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:AnkyTests` is currently blocked on first-boot simulator data migration for the iOS 26.3.1 runtime on this machine.

## 2026-03-10

### Added

- A regression test that locks the mobile API client to the real `/swift/v1/*` backend path resolution.
- A JP tutorial lesson on auth flow, Privy callback schemes, and backend URL construction.

### Changed

- Simplified the signed-out auth screen to a black, grey, and purple palette with a scrollable, keyboard-safe layout.
- Registered the app's callback URL scheme in a real `Info.plist` and passed it explicitly into Privy OAuth login.
- Simplified meditation and breathwork home screens to a single generated path with shorter copy and no visible mode/style chooser.
- Simplified facilitator application intake to an Instagram profile link plus an optional website link.

### Fixed

- Corrected the API client so `/auth/privy`, `/me`, and the rest of the mobile routes resolve under `https://anky.app/swift/v1/` instead of collapsing to the wrong host path.
- Fixed Google and Apple sign-in startup by giving Privy the callback URL scheme it requires on iOS.
- Fixed the auth screen so inline errors and status messages are reachable while the keyboard is open.
- Fixed writing history so successful submissions refresh remote entries and can pick up generated anky image paths.
- Fixed writing history image rendering for both relative backend paths and fully qualified image URLs.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild test -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`

## 2026-03-09

### Added

- Real Privy authentication on iOS, including email code flow, Apple sign-in, Google sign-in, backend token exchange, secure session persistence, silent session restore, and logout.
- Full writing flow with local prompt/history cache, keystroke delta capture, idle-based ending, offline submission queueing, and completion states for both Anky and non-Anky outcomes.
- Guided meditation playback with AVSpeechSynthesizer, phase sequencing, breathing visuals, haptics, pause/resume, ready polling, offline cache reuse, and meditation session logging.
- Guided and generic breathwork playback with cached sessions, style loading, breathing visuals, haptics, ready polling, and history support.
- Sadhana commitment tracking with creation, detail view, daily honesty check-ins, and heatmap-style progress rendering.
- Facilitator marketplace screens for discovery, recommendations, detail, booking handoff, reviews, and facilitator applications.
- Bundled Righteous typography support and audio session bootstrapping for spoken guidance playback.
- Root project documentation with this changelog and a repo README.
- Root `AGENTS.md` guidance for future agents and a `JP_TUTORIAL` folder for ongoing Swift/iOS teaching material tied to real implementation work.

### Changed

- Aligned the iOS models and API client with the real `/swift/v1/*` contract from the Rust/Axum backend in the Anky monorepo.
- Framed the app shell around the four pillars of the practice: Write, Sit, Breathe, and Sadhana, with Facilitators accessible from profile.
- Treated the iOS app as the native client for the larger Anky system described in the backend whitepaper: writing feeds reflection, guidance generation, memory, and human facilitator matching.

### Fixed

- Removed the temporary "paste a Privy JWT" gap by wiring the actual Privy SDK.
- Removed the placeholder guided session gap by implementing real playback and backend completion flows.
- Corrected model assumptions that did not match the backend, including optional history fields and breathwork/meditation response shapes.
- Fixed device launch failure caused by linking `PrivySDK.framework` without embedding it into the app bundle for runtime loading.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`
