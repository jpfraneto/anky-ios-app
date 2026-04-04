# Lesson 005: Seed Identity and the `/swift/v2` Unlock Model

This lesson still explains the unlock model correctly, but some of its older crypto details were written during the EVM-to-Solana transition. Do not use this file as the current source of truth for signing, wallet format, or verifier commands. For the current shipping identity, seal gesture, altar, Apple Pay, and QR auth path, also read [008_altar_seal_apple_pay_and_qr_auth.md](/Users/kithkui/Desktop/ankY/JP_TUTORIAL/008_altar_seal_apple_pay_and_qr_auth.md).

## Why this lesson exists

The app's center of gravity changed.

It no longer starts with visible account creation. It starts with:

1. a quiet local identity
2. a locked `NOW` writing space
3. unlock only after a persisted real anky

That means JP needs a different mental model than the older Privy-first flow.

## Mental model one: identity and unlock are not the same thing

Start with [AppState.swift](/Users/kithkui/Desktop/Anky/Anky/AppState.swift).

This file now tracks two truths that must stay separate:

- `hasLocalIdentity`
- `hasUnlockedFullExperience`

That split is the core product rule.

The user can have a real seed identity on first open and still be in locked mode. The app should not mistake "we know who this device is" for "this user has crossed into the full Anky system."

Unlock happens only when one of these is true:

- the backend already knows this identity has persisted ankys
- the current session finishes and `/swift/v2/write` returns `persisted: true`

That is why `AppState` has both route state and unlock state. Authentication alone is not enough.

## Mental model two: the phrase is the root secret, but the backend never sees it

Open [SeedIdentityManager.swift](/Users/kithkui/Desktop/Anky/Anky/SeedIdentityManager.swift).

This type owns the local identity lifecycle:

- generate a 24-word phrase
- normalize and validate imported phrases
- derive the private key
- derive the wallet/public key
- sign backend challenges
- store the private key in Keychain
- wipe identity when the user explicitly reboots

The important product truth is:

- the phrase never leaves the device

The backend only sees:

- the `0x...` wallet address
- a signature over the challenge message

That is why `SeedIdentityManager` and `SeedAuthService` are separate files.

- `SeedIdentityManager` owns secret material
- `SeedAuthService` owns network auth

Keeping those responsibilities separate makes the code safer to reason about.

## Mental model three: welcome is part of onboarding, not a settings screen

Look at [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift).

The root view now switches between:

- `SplashView`
- `WelcomeFlowView`
- `RecoveryImportView`
- `LockedNowShell`
- `UnlockedShellView`

This is a strong SwiftUI lesson:

- the root UI is a function of app state
- routes are product truth, not navigation accidents

The welcome flow is not hidden inside profile/settings because first-open product truth lives there:

- the user is here to write for 8 minutes
- Face ID can protect the device-local identity
- the seed phrase is stored quietly in Keychain/iCloud Keychain-compatible storage
- daily notifications can invite the practice back at 6:00 AM

That flow is driven by:

- `appState.pendingMnemonic`
- `appState.hasCompletedWelcome`

When the user finishes the welcome flow, `AppState.completeWelcome()` marks onboarding as complete, clears the pending mnemonic preview, and moves the route into either `locked` or `unlocked`.

## Mental model four: the auth flow is challenge-sign-verify, not token exchange

Open [SeedAuthService.swift](/Users/kithkui/Desktop/Anky/Anky/SeedAuthService.swift).

The live auth pipeline is:

1. read the wallet address from local identity
2. `POST /swift/v2/auth/challenge`
3. sign the exact challenge message bytes locally with Ethereum `personal_sign` / EIP-191 semantics
4. `POST /swift/v2/auth/verify`
5. store the returned bearer session token in Keychain
6. call `/swift/v2/me`

That is very different from the old Privy flow.

The important Swift/iOS concepts here are:

- async functions for network handoffs
- Keychain for session persistence
- error handling that retries expired or stale challenges without showing crypto jargon

Notice what `SeedAuthService` does not do:

- it does not know the recovery phrase
- it does not derive keys
- it does not decide unlock

That is deliberate. Each layer has one job.

## Mental model five: `persisted` is the source of truth for cloud history

Open:

- [AnkyWritingSession.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyWritingSession.swift)
- [AppState.swift](/Users/kithkui/Desktop/Anky/Anky/AppState.swift)
- [WritingCacheStore.swift](/Users/kithkui/Desktop/Anky/Anky/WritingCacheStore.swift)

When a session ends, the app decides locally whether it qualifies as a real anky:

- `>= 8 minutes`
- `>= 300 words`

If it does not qualify:

- it stays local-only
- it does not unlock the shell
- it does not enter cloud history

If it does qualify:

- the app authenticates if needed
- it sends `POST /swift/v2/write`
- it trusts the backend's `persisted` field

This is the critical product rule:

- qualifying locally is necessary
- `persisted == true` is still the final backend truth

That is why `recordWriting` in `AppState` distinguishes:

- local-only entries
- pending real ankys
- synced persisted ankys

`cloudHistory` only exposes entries whose `syncState == .synced`.

This is how the UI avoids pretending that a short write or non-persisted write is already part of the user's long-term identity record.

## Mental model six: local draft state and cloud history are different storage problems

The repo now has two separate local writing stores:

- [WritingSessionStore.swift](/Users/kithkui/Desktop/Anky/Anky/WritingSessionStore.swift)
- [WritingCacheStore.swift](/Users/kithkui/Desktop/Anky/Anky/WritingCacheStore.swift)

Why two?

Because they solve different problems.

`WritingSessionStore` stores an in-progress draft:

- text
- elapsed time
- lives remaining
- keystroke timing
- interruption state

That helps the app recover a live session after interruption.

`WritingCacheStore` stores completed writing entries:

- local-only short writes
- pending real ankys
- synced persisted ankys

This is a useful architecture lesson:

- "draft recovery" and "history" sound similar
- but they have different lifecycles and should not share one vague cache

## Mental model seven: the unlocked shell is still intentionally narrow

Open [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift) again.

The unlocked shell currently exposes only:

- `NOW`
- `ANKYS`
- `SEED`

That is intentional.

The product spec says not to invent the conversation layer yet. So the app does not guess at a thread model or fake a generic chat tab.

This is a good engineering discipline lesson:

- do not build UI around APIs that do not exist yet

Instead, the app leaves a clean place for future expansion while keeping the current shell honest.

## The seed derivation boundary

Inside [SeedIdentityManager.swift](/Users/kithkui/Desktop/Anky/Anky/SeedIdentityManager.swift), `SeedIdentityCrypto` is the dangerous part of the feature.

Why dangerous?

Because cryptographic derivation code is easy to get subtly wrong:

- checksum mistakes
- normalization mistakes
- wrong seed bytes
- wrong hardened path
- wrong secp256k1 key or address output
- signatures that look valid locally but fail against the backend

This repo currently keeps that logic local in app code, so it must be treated with extra caution.

That is why [AnkyTests.swift](/Users/kithkui/Desktop/Anky/AnkyTests/AnkyTests.swift) now locks the implementation with deterministic vectors for:

- entropy to mnemonic
- mnemonic normalization and checksum rejection
- mnemonic to seed
- canonical EVM path `m/44'/60'/0'/0/0`
- private key output
- compressed and uncompressed public key output
- checksum wallet address output
- Ethereum challenge signature verification against a backend-style challenge message

There is also an opt-in live backend verification test path, plus [LiveBackendVerifier.swift](/Users/kithkui/Desktop/Anky/Tools/LiveBackendVerifier.swift) for a direct production transcript that uses the same EVM derivation and signing code as the app.

The lesson here is simple:

- if security-sensitive code is local, tests are not optional guardrails

## Common failure modes and where to look

### 1. The app authenticates, but stays locked

Check:

- [AppState.swift](/Users/kithkui/Desktop/Anky/Anky/AppState.swift)
- `UserProfile.totalAnkys`
- whether the latest `/swift/v2/write` response had `persisted: true`

This is usually an unlock-state issue, not an auth issue.

### 2. A recovered phrase restores the wrong wallet

Check:

- phrase normalization in [SeedIdentityManager.swift](/Users/kithkui/Desktop/Anky/Anky/SeedIdentityManager.swift)
- the frozen derivation path constant
- the vector tests in [AnkyTests.swift](/Users/kithkui/Desktop/Anky/AnkyTests/AnkyTests.swift)

This is usually a derivation issue, not a networking issue.

### 2b. Live EVM auth fails before `verify`

Check:

- the exact `wallet_address` sent to `/swift/v2/auth/challenge`
- whether the address is a canonical `0x...` EVM address derived from `m/44'/60'/0'/0/0`
- the exact `wallet_address` sent to `/swift/v2/auth/challenge`
- the exact request and response from the live verifier or from the app logs

As of March 16, 2026, the hosted backend accepts canonical `0x...` addresses again. If this step fails now, treat it as a real contract regression or an iOS signing/serialization bug and capture the exact payloads.

### 3. A real anky shows locally but does not appear in cloud history

Check:

- whether `submitFinishedCapture(appState:)` fell back to pending or local-only
- whether `/swift/v2/write` returned `persisted: false`
- whether `AppState.refreshWritings()` successfully merged remote entries

This is usually a persistence-state issue, not a rendering issue.

### 4. The first resumed character disappears after pause

Check the difference between:

- `resumeFromPauseFromTyping(at:)`

This is a state-machine/input issue inside [AnkyWritingSession.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyWritingSession.swift).

## How data moves through the feature

Here is the end-to-end path:

1. On first open, `AppState.bootstrap()` checks whether a local seed identity exists.
2. If not, `SeedIdentityManager.generateIdentity()` creates one and stores the private key in Keychain.
3. `ContentView` shows the welcome flow.
4. The user enters the locked `NOW` shell.
5. `WritingFlowModel` captures text and local timing data.
6. A short session stays local-only.
7. A qualifying session authenticates through `SeedAuthService`.
8. `AnkyAPI.submitWriting` sends the real anky to `/swift/v2/write`.
9. If `persisted == true`, `AppState.applyPersistedAnkySuccess(...)` unlocks the shell and refreshes persisted history.

That is the current mobile spine of the product.

## Try this yourself

1. Put a breakpoint in `AppState.bootstrap()`.
2. Delete the app's local Keychain items and relaunch.
3. Watch the route move from `booting` to `welcome`.
4. Put another breakpoint in `SeedAuthService.performAuth(...)`.
5. Finish a qualifying local writing and watch the challenge-sign-verify flow run before `/swift/v2/write`.
6. Inspect `appState.hasLocalIdentity` and `appState.hasUnlockedFullExperience` before and after the persisted write succeeds.

You can also compile and run the direct verifier from the repo root:

```bash
clang -c Anky/Crypto/Vendored/WalletKit/secp256k1/secp256k1.c -IAnky/Crypto/Vendored/WalletKit/secp256k1/include -IAnky/Crypto/Vendored/WalletKit/secp256k1 -o /tmp/secp256k1.o
clang -c Anky/Crypto/Vendored/WalletKit/keccaktiny/keccak-tiny.c -IAnky/Crypto/Vendored/WalletKit/keccaktiny/include -o /tmp/keccak-tiny.o
xcrun swiftc -o /tmp/anky-live-verifier Tools/LiveBackendVerifier.swift Anky/Crypto/BIP39EnglishWordlist.swift Anky/Crypto/EthereumSeedIdentityCrypto.swift /tmp/secp256k1.o /tmp/keccak-tiny.o -import-objc-header Anky/Anky-Bridging-Header.h -Xcc -IAnky/Crypto/Vendored/WalletKit/secp256k1/include -Xcc -IAnky/Crypto/Vendored/WalletKit/secp256k1 -Xcc -IAnky/Crypto/Vendored/WalletKit/keccaktiny/include
/tmp/anky-live-verifier
```

That tool prints the exact request and response pairs for:

- challenge
- verify
- me
- a short write that should stay local-only
- a real write that should persist and appear in cloud history
