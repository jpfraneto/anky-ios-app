# Anky iOS

Anky iOS is the native iPhone client for the Anky writing practice.

The current app centers one product path:

- identity is generated silently on first open
- writing starts before any visible account setup
- unfinished and short writing stays local
- only a persisted real anky unlocks the fuller shell

The app is not a separate product from the backend. It is the mobile surface for the wider Anky system described in the monorepo and whitepaper.

## Current product model

- A local seed identity exists from first open.
- There is no new email, phone, or social-login onboarding path.
- A real anky requires `>= 8 minutes` and `>= 300 words`.
- `persisted` from `POST /swift/v2/write` is canonical.
- If `persisted == false`, the session stays local-only and must not appear in cloud history.
- Unlock happens only after a successful persisted real anky, or when a recovered identity already has persisted ankys on the backend.
- Conversation and thread UI are intentionally hidden until there is a real mobile API/client for them.

## Backend relationship

New mobile identity and writing work targets `https://anky.app/swift/v2`.

The active flow is:

1. The app generates a 24-word BIP39 phrase locally and derives one canonical EVM secp256k1 account from `m/44'/60'/0'/0/0`.
2. The backend issues a one-time challenge through `POST /swift/v2/auth/challenge`.
3. The app signs the exact challenge bytes locally with Ethereum `personal_sign` / EIP-191 semantics and verifies through `POST /swift/v2/auth/verify`.
4. The app writes through `POST /swift/v2/write`.
5. The app reads identity and persisted history through `GET /swift/v2/me` and `GET /swift/v2/writings`.

Legacy meditation, breathwork, sadhana, and facilitator code still exists in the repo and still points at `/swift/v1/*` so those files keep compiling. The new root shell does not route into those legacy surfaces.

Backend/system context lives in the Anky monorepo:

- `WHITEPAPER.pdf`
- `UNDERSTANDING_ANKY.md`
- `SWIFT_AGENT_BRIEF.md`
- `THE_ANKY_MODEL.md`

Monorepo: <https://github.com/jpfraneto/anky-monorepo>

## Current app capabilities

### Identity and auth

- Silent 24-word recovery phrase generation on first open
- Local EVM secp256k1 key derivation from `m/44'/60'/0'/0/0`
- Canonical `0x...` wallet address identity
- Private key storage in Keychain, with synchronizable key storage enabled for the seed material
- One-time backup ceremony with explicit recovery warnings
- Local recovery import by entering the 24 words on-device
- Silent challenge/verify authentication against `/swift/v2/auth/*`
- Backend session token storage in Keychain

### Writing and unlock

- Minimal `WRITE NOW` landing state
- Hidden composer with a dominant center glyph instead of a normal text editor
- Two-life idle mechanic with pause/continue after the first lost life
- Rhythm-scaled bottom ribbon of prior characters
- Local draft persistence and interrupted-session recovery
- Local-only completion for short or unfinished sessions
- Offline queueing only for real ankys
- Unlock gated by persisted real ankys, not by authentication alone
- Persisted history view that excludes any local-only or `persisted: false` sessions

### Current unlocked shell

- `NOW`
- `ANKYS`
- `SEED`

There is no new conversation surface yet. The app keeps that hidden until the backend/thread client is real.

## Seed identity security note

The recovery phrase is the root secret. It never goes to the backend.

The current iOS code uses a locked local BIP39/BIP32 implementation together with vendored `libsecp256k1` and `keccak-tiny` sources from WalletKit under Apache 2.0 instead of pulling a larger external Swift wallet package into this Xcode project. Because that is security-critical, the repo locks it down with deterministic tests for:

- mnemonic generation and checksum validation
- mnemonic-to-seed derivation
- canonical derivation path `m/44'/60'/0'/0/0`
- private key, compressed public key, uncompressed public key, and checksum address output
- Ethereum `personal_sign` challenge signature verification and local address recovery

There is also an opt-in live backend test path in `AnkyTests.swift`.

As of March 16, 2026, the hosted `https://anky.app/swift/v2/auth/challenge` endpoint still rejects `0x...` wallet addresses with `{"error":"invalid public key"}`, so live EVM auth verification is blocked by backend validator mismatch even though the mobile app now treats EVM as canonical.

Do not change the derivation path or phrase handling casually.

## Tech stack

- SwiftUI
- Swift Concurrency
- CryptoKit
- CommonCrypto
- AVFoundation
- Keychain
- Native iOS haptics

No third-party UI framework is used.

## Project map

```text
Anky/
  AnkyApp.swift               App entry point
  AppState.swift              Root routing, identity state, unlock state
  ContentView.swift           Backup, recovery, locked shell, unlocked shell
  AnkyAPI.swift               `/swift/v2/*` client plus legacy `/swift/v1/*` helpers
  AnkyModels.swift            Codable models aligned to backend responses
  SeedIdentityManager.swift   Phrase generation, derivation, signing, Keychain
  SeedAuthService.swift       Challenge/verify auth flow
  KeychainHelper.swift        Secure key and token persistence
  AnkyWritingSession.swift    NOW writing state machine and completion flow
  WritingSessionStore.swift   Local in-progress draft persistence
  WritingCacheStore.swift     Local writing history cache
  OfflineQueue.swift          Deferred sync for persisted real ankys
  AppCopy.swift               Backup ceremony and shell localization
  WritingExperienceStrings.swift
                              Writing flow localization
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
- manual live `/swift/v2/auth/challenge`, `/swift/v2/auth/verify`, and `/swift/v2/me` verification

## Documentation rhythm

- Update `CHANGELOG.md` after each meaningful implementation pass.
- Add or update a `JP_TUTORIAL` lesson when a feature meaningfully changes.
- Keep the Swift models, README, and auth/write docs aligned whenever the backend contract changes.
