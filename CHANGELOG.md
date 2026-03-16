# Changelog

This file tracks meaningful work on the Anky iOS app.

## How to update this file

- Add a new entry at the top for each material work session.
- Use `YYYY-MM-DD` dates.
- Keep the sections short and concrete.
- Prefer `Added`, `Changed`, `Fixed`, and `Verified`.
- Reference the user-facing behavior and the system integration, not just file edits.

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
- As of March 16, 2026, `POST https://anky.app/swift/v2/auth/challenge` still returns `{"error":"invalid public key"}` for canonical EVM addresses such as `0xF278cF59F82eDcf871d630F28EcC8056f25C1cdb`, so live backend EVM auth verification remains blocked pending backend validator alignment.

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
