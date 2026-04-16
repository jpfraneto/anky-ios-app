# Changelog

This file tracks meaningful work on the Anky iOS app.

## How to update this file

- Add a new entry at the top for each material work session.
- Use `YYYY-MM-DD` dates.
- Keep the sections short and concrete.
- Prefer `Added`, `Changed`, `Fixed`, and `Verified`.
- Reference the user-facing behavior and the system integration, not just file edits.

## 2026-04-16

### Added

- Added a new JP tutorial lesson for the runtime cutover and an architecture handoff at `../architecture/IOS_RUNTIME_CUTOVER_SUMMARY.md`.
- Added regression coverage for the proof-readback sealing path, canonical proof metadata mapping, canonical title validation, and prevention of legacy remote history from falsely sealing local canonical sessions.

### Changed

- Changed the live `/api/anky/submit` completion path so accepted sessions persist into the canonical local archive immediately, then reconcile title, reflection, image, proof, and backend anky id through `GET /api/anky/sessions/{session_hash}` and `GET /api/anky/sessions/{session_hash}/proof`.
- Changed archive/profile/history runtime behavior so the active profile surface, pending retry flow, daily prompt recovery, and background sealing path now derive from `LocalArchiveRecord` instead of treating `/swift/v2/writings` or `/swift/v2/writing/{sessionId}/status` as canonical truth for finished Ankys.
- Changed local-vs-remote archive merging so legacy `/swift/v2/writings` data can still enrich the archive, but it can no longer promote a canonical local session to `.synced` before proof and the other required artifacts actually exist.

### Verified

- Could not run `xcodebuild` or `swift` in this environment because the Apple toolchain is not installed here. Validation for this pass is limited to code review and test additions in-repo.

## 2026-04-15

### Added

- Added `LocalArchiveStore.swift` as the canonical local archive persistence layer for `LocalArchiveRecord`, with migration from the older `anky.cached.writings` cache and legacy projection writes kept only as compatibility output.
- Added canonical processor readback/proof client models and API hooks for `GET /api/anky/sessions/{session_hash}` and `GET /api/anky/sessions/{session_hash}/proof`, plus mapping helpers back into `AnkyProofMetadata` and `LocalArchiveRecord`.
- Added regression coverage for canonical retry payload retention inside `LocalArchiveRecord`, local-vs-remote archive merge behavior, and canonical processor status/proof mapping onto the local archive model.
- Added a JP tutorial lesson and the required `architecture/IOS_ARCHIVE_NORMALIZATION_SUMMARY.md` handoff for this normalization pass.

### Changed

- Changed archive persistence so `AppState` now owns canonical `localArchiveRecords` and projects `writingHistory` from that archive state instead of mutating `CachedWritingEntry` as the source of truth.
- Changed active write capture, pending submit state, generated-artifact updates, retry payload repair, and sync-state transitions to flow through `AnkySessionBundle` and `LocalArchiveRecord` before adapting back to legacy UI models.
- Changed pending retry logic to sweep and reconstruct from canonical archive records first, leaving `CachedWritingEntry` as a UI adapter instead of the retry source of truth.
- Changed `AnkySessionBundle` to retain the local `.anky` payload handle directly (`canonicalSessionString` and canonical file path), so local-first resend durability no longer depends on the legacy cache shape.

### Verified

- Could not run `xcodebuild` or `swift` in this environment because the toolchain is not installed here. Validation for this pass is limited to code review and test additions in-repo.

## 2026-04-15

### Added

- Added `AnkyContractFoundation.swift` with the first iOS contract-foundation layer: canonical `AnkySessionBundle`, `LocalArchiveRecord`, `AnkyProofMetadata`, `AnkyImageArtifact`, centralized qualification constants, 3-word title validation, and required-artifact completeness validation.
- Added adapters from `LocalWritingCapture`, `CachedWritingEntry`, `WritingItem`, and `WritingStatusResponse` into the new canonical contract types so later refactors can cut over without inventing more names.
- Added unit coverage for the canonical title rule, artifact completeness, local capture to session-bundle projection, and rejection of legacy placeholder titles as canonical completed titles.
- Added a JP tutorial lesson on the contract-foundation mental model and an architecture-side `IOS_CONTRACT_FOUNDATION_SUMMARY.md` handoff document for the next PR.

### Changed

- Changed the core 8-minute / 300-word qualification rule to resolve through one obvious source of truth in `AnkyContractFoundation.swift`, with low-risk call sites updated across writing, cache, queue, profile, and flow-score code.
- Changed the canonical `/api/anky/submit` request builder to derive its timing/hash semantics from the new session-bundle projection instead of ad hoc per-call calculations.
- Changed legacy cache/history/archive/proof types and paths to be labeled explicitly as legacy projections or non-canonical flows, including older sealed-write, relay, Arweave, and app-group archive code paths.

### Verified

- Could not run `xcodebuild` or `swift` in this environment because the toolchain is not installed here. Validation for this pass is limited to code review and test additions in-repo.

## 2026-04-15

### Added

- Added a Connected Devices section to the active settings sheet, including current-device pinning, remote session listing through `/swift/v2/auth/sessions` when available, and revoke controls for non-current devices.
- Added a `Subscribe to Premium` row that opens a custom bottom sheet inspired by the reference, plus the footer copy `Created with 💚 by Anky, Inc.` at the bottom of settings.
- Added a JP tutorial lesson covering how `SettingsView` now composes local writing preferences, backend-backed device sessions, and a presentation-only premium sheet.

### Changed

- Changed the settings screen to refresh device sessions on open and pull-to-refresh, while degrading gracefully to the current iPhone when the backend session route is still unavailable.
- Changed the premium sheet to be explicit that checkout and restore are preview-only until StoreKit exists, instead of pretending purchases are already wired.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild test -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:AnkyTests/AnkyFlowTests`

## 2026-04-15

### Added

- Added a JP tutorial lesson covering `UIViewRepresentable` first-responder teardown, why keyboard dismissal can race SwiftUI removal, and how the writer close path now avoids that crash.

### Changed

- Changed the red close path in the active writing overlay to end editing on the active key window and defer the actual exit/send action to the next main-loop turn so UIKit can settle first-responder teardown cleanly.
- Changed `AnkyComposerTextView` to cancel stale async focus work and resign cleanly in `dismantleUIView`, instead of letting old `becomeFirstResponder` work fire after the writer is already disappearing.

### Fixed

- Fixed the crash when the user tapped the red close button on the untouched writing overlay and the custom `UITextView` was being removed during keyboard teardown.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild test -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:AnkyTests/AnkyFlowTests`

## 2026-04-15

### Added

- Added a formalities section to the active settings sheet with Terms of Service, Privacy Policy, and Frequently Asked Questions links pointing at the `https://anky.app/*.md` documents.
- Added an in-app Safari presentation path for those settings links so legal/help pages open inside the native modal flow.

### Changed

- Changed the active settings screen away from SwiftUI `Form` chrome and into a custom dark card layout that matches the calmer profile/settings surface shown in design references.
- Changed the writing font picker, wallet copy row, recovery-phrase status, and reboot action to live inside the same grouped-card settings layout.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-04-14

### Added

- An automatic pending-anky retry sweep during auth refresh on app launch/login, using the same canonical `.anky` resend path as the profile `send again` button.

### Changed

- Moved pending-anky retry logic out of the profile sheet into a shared service so launch/login replay and manual archive retry cannot drift apart.
- Changed retried ankys to trigger the same post-persist follow-up hooks as the normal submit path, including cNFT mint/archive fire-and-forget work.

### Fixed

- Fixed the gap where a stalled real anky could only recover if the user manually opened profile and tapped retry, even after a fresh authenticated app launch.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-04-14

### Added

- A profile-side fallback resend button for pending real ankys, plus on-device recovery of older canonical `.anky` files when a pending cache entry predates the new retry metadata.
- A new JP tutorial lesson covering why pending archive entries need canonical submit metadata, how the profile retry path checks backend status before reposting, and where a true backend idempotency guarantee should live.

### Changed

- Changed cached writing history so real ankys now preserve the canonical `.anky` session string, file path, and session hash alongside profile/archive metadata instead of dropping that retry-critical state during cache rewrites.
- Changed `/api/anky/submit` requests to attach the canonical session hash as `Idempotency-Key` and `X-Anky-Session-Hash`, so the client already speaks a stable duplicate key while the backend catches up.

### Fixed

- Fixed the profile/archive dead-end where a pending real anky could be visible locally but had no safe way to be sent to the backend again later if the original SSE processing died.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-04-14

### Added

- A new JP tutorial lesson covering why a finished real anky must hit `writingHistory` immediately, how the skip/background path now streams the same `/api/anky/submit` contract as the sealing surface, and how pending vs synced real ankys show up in profile.

### Changed

- Changed the skip/background submit path in `AnkyChatView` so it no longer waits for the full helper/poll cycle before updating the rest of the app. Real ankys are now recorded locally as `.pending` the moment writing ends, then reflection/title/image stream back into chat and cache while the backend is still working.
- Changed the background submit completion logic so accepted real ankys can still finalize through status polling if the SSE stream closes or drops before every artifact arrives.

### Fixed

- Fixed the case where skipping the sealing surface could leave chat on typing dots and profile at `0` ankys even though the user had just finished a qualifying anky.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-04-14

### Added

- A full profile-v2 archive surface with the compact hero row, three stat buttons, real-anky image cards, a tappable month calendar, a full territories list across all eight kingdoms, a large archived-conversation sheet with inline reply, and a medium kingdom detail sheet.
- A new JP tutorial lesson covering how the profile derives its own stats from cached real ankys, how the conversation sheet reconstructs and continues a thread, and why profile metadata has to survive cache merges.

### Changed

- Changed the active profile to derive points, level, streak, total words, average flow, and dominant kingdom directly from `writingHistory` instead of relying on a separate profile payload.
- Changed archived follow-up chat so the profile sheet prefers `POST /api/anky/{id}/conversation` when the backend anky id exists and falls back to `POST /api/chat-quick` for older or local-only sessions.

### Fixed

- Fixed remote-history decoding and cache update paths so `flow_score`, `kingdom`, `energy`, and `reason` are preserved instead of being dropped, which keeps the profile territories and flow-based stats populated after reloads.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-04-14

### Added

- Broader interaction haptics for entering writing mode, starting the meditation timer, reaching the final second before the 8-second idle cutoff, and confirming a copy action on a sent writing bubble.
- A new JP tutorial lesson covering bottom-pinned chat scrolling, inline copy feedback, immediate keyboard dismissal, live font-size preview, and full-screen recovery presentation.

### Changed

- Changed the main chat surface so it re-pins to the newest content as soon as the user sends a message, Anky starts typing, or a reply lands, instead of leaving the latest exchange off-screen.
- Changed the writing copy affordance so the same button flips inline from `copy` to `copied` with a local visual state instead of throwing a separate top-screen toast.
- Changed settings font previews to render at the actual selected writing size, and changed recovery-phrase presentation from settings/profile into a full-screen cover so the ceremony matches the viewport.
- Changed the chat-to-writing presentation so Anky mode enters as one continuous full-screen motion, removing the delayed second-stage content reveal and rounded-card peek that caused a brief visual glimpse before the writer fully opened.

### Fixed

- Fixed a keyboard-dismiss timing gap in the writing overlay by resigning first responder immediately when the red close button is tapped.
- Fixed the recovery screen being clipped or oversized on smaller phones when opened from settings/profile by removing the nested sheet-height constraint and letting the recovery flow own the screen.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-04-14

### Added

- Per-anky thread mirroring for post-reflection quick chat, so follow-up user/Anky replies are stored locally and can be reopened from the archive conversation view.
- Regression coverage for real-anky classification and history-merge behavior, including short-session rejection and preservation of fresh local synced ankys while `/swift/v2/writings` catches up.
- A new JP tutorial lesson covering writing chrome state, true-anky archive truth, local-vs-remote history merging, and profile thread replay.

### Changed

- Changed the active writing chrome so the idle warning only appears after 3 seconds of silence, drains from right to left, hides the red exit button once typing begins, hides the timer after 20 seconds, and keeps extra bottom inset so new lines stay above the session bar.
- Changed the active chat-first submit path so only real ankys continue into `/api/anky/submit`; short sessions now stay local-only instead of being promoted into the real-anky flow.
- Changed the profile/archive surface so map, hero, stats, and tap targets are driven by real ankys only, with the latest anky image used in the hero when available.
- Changed the full-screen writer so the top bar is visible from the start of writing mode alongside the bottom bar, and the prompt always stays in the `UITextView` placeholder path until the user has actual text.

### Fixed

- Fixed the sealing submit flow hanging forever on the loading dots when the backend accepted an anky and then closed the SSE stream without sending the exact final event sequence.
- Fixed writing-history merging so a freshly completed local anky no longer disappears from profile while the backend history endpoint is still behind.
- Fixed backend `is_anky` leakage from short sessions so incomplete or non-qualifying writings are no longer treated like real ankys in the archive.
- Fixed the recovery-phrase backup sheet overflowing past the viewport by moving the ceremony phases into a scroll-safe container, so the swipe control stays reachable on smaller heights.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`
- `xcodebuild test -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:AnkyTests/AnkyFlowTests`

## 2026-04-13

### Added

- Canonical `.anky` file writing for both the active chat-first writer and the legacy writer, including first-keystroke epoch capture, `SPACE` tokens for literal spaces, hash-named files under `ankys/yyyy/mm/dd/`, and immediate on-disk SHA-256 verification.
- A shared `AnkySessionFileStore` that owns canonical payload normalization, file-path construction, backup-flag enforcement, and file-hash verification.
- iCloud Documents entitlements for the app target, using the ubiquity container `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)` when it is available and falling back to Documents when it is not.
- A JP tutorial lesson covering the `.anky` protocol artifact, how the writer models build it, and how the submit path now reuses the exact file content.
- Partial `.anky` crash recovery for the active live-writing path, with `partial_{sessionId}.anky` refreshed every 300ms and atomically renamed into the final hash filename when the session seals.

### Changed

- Changed the submit request builder so `POST /api/anky/submit` now prefers the written `.anky` file bytes when available, derives `started_at` from the first line's epoch timestamp, and reuses the file hash rather than recomputing from a transformed string.
- Changed `LocalWritingCapture` so it carries the canonical `.anky` file path and the file-byte SHA-256 alongside the in-memory session string.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`
- Real `.anky` file written at `/Users/kithkui/Documents/ankys/2026/04/13/f55148e80382dd4d252544c0fbc02b5fb212af4e2f3d9a224adcf345b0d004f4.anky`, with `shasum -a 256` matching the filename and the backup flag resolved to `false`
- Simulated crash/relaunch recovery through `WritingSessionStore`, producing `/Users/kithkui/Documents/ankys/2026/04/13/partial_crash-probe-001.anky`, reloading it successfully, and sealing it into `/Users/kithkui/Documents/ankys/2026/04/13/8857731ec72f42de1a035e242e25033582d9bf4be4040492973b05ac2df567ce.anky`

## 2026-04-13

### Added

- A new full-screen `SealingView` between writing completion and chat reveal, with a kingdom-of-the-day presentation, swipe-to-seal track, sealing pulse state, sealed preview state, and a direct handoff back into chat.
- SSE submit support for `POST /api/anky/submit`, including session-hash signing with the local Solana identity, event parsing for `accepted`, `reflection_chunk`, `reflection_complete`, `image_url`, `solana`, and `done`, and tutorial/docs updates for the new flow.
- A JP tutorial lesson covering the sealing intercept, `pendingCapture` hold-and-release model, SSE streaming, and how the new write lifecycle connects `AnkyChatView`, `SealingView`, `AnkyAPI`, and `AppState`.

### Changed

- Changed the active chat-first writer so session completion no longer reveals chat immediately; it now pauses on the sealing screen and only dismisses the writing overlay after the user seals or skips.
- Changed the active chat-first write path away from immediate `/swift/v2/write` semantics and into the new `/api/anky/submit` SSE contract, while leaving legacy surfaces in place during the migration.
- Changed the background skip path so it keeps using the existing `pendingCapture` task and polling fallback, but no longer treats `accepted` as fully persisted success.

### Fixed

- Fixed a race where the existing `pendingCapture` task could have submitted the session before the new sealing screen had a chance to intercept it.
- Fixed the SSE parser so the new stream events are decoded without Swift isolation warnings.
- Fixed the background completion semantics so fatal `claude` / `persist` failures from the SSE path do not mark the session as stored just because an `accepted` event arrived first.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-04-07

### Added

- Native save-to-Photos support for completed generated Ankys, including the required Photos add-only permission string and a full-width save action inside the generated-image detail sheet.

### Changed

- Changed the native generate screen to show a prominent in-progress card while Flux is being called and while the backend is still rendering, with visible placeholder collage tiles so generation is unmistakably active.
- Changed the collapsed writing dock into a stable three-part chat bar with a fixed mic slot, center composer, and send slot so the bottom controls read like a normal messaging UI.

### Fixed

- Fixed the bottom writing dock's shifting layout so the controls no longer reflow awkwardly as text appears and the user moves between idle and active typing.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-04-07

### Added

- A native `GenerateView` with Flux prompt entry, aspect-ratio selection, backend polling through `/api/v1/generate` and `/api/v1/anky/:id`, and a full-screen detail sheet for generated Ankys.
- `GeneratedAnkyStore` for persisting pending generation ids and locally completed generated Ankys so the app can recover native generations after dismissal or relaunch.
- Public generated-gallery support through `GET /api/ankys?origin=generated`, rendered natively as a tight collage grid.
- Decoding and URL-normalization tests for the new generated-Anky models and gallery payloads.

### Changed

- Replaced the temporary Safari handoff from the chat header with the native generate route.
- Changed the left-header `Generate` action from a web page launch into a native creation surface that feels like the rest of the app.
- Changed the generate experience to show the user's completed local generations first and the wider generated feed underneath instead of bouncing the user out to the web app.
- Updated README, CURRENT_STATE, and the JP tutorial lesson so the repo now teaches the native generate/gallery path rather than the earlier web handoff.

### Fixed

- Fixed generated-image normalization for the new gallery path so absolute URLs, relative `/data/images/...` paths, and bare `.webp` filenames all resolve correctly.
- Fixed the unified chat composer so the collapsed writing dock stays anchored to the bottom of the screen instead of jumping upward when keyboard state changes.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-04-07

### Added

- An in-app web handoff to `https://anky.app/generate` using `SFSafariViewController`, so the main chat shell can route into the backend's existing Flux generation surface without inventing a partial native client.
- A new JP tutorial lesson covering the header mental model, equal-width SwiftUI layout zones, avatar rendering, and the native-to-web route handoff.

### Changed

- Replaced the old altar-style chat header with a simpler messenger-style shell: `Generate` on the left, Anky centered, and the user's profile/history entry on the right.
- Removed the extra kingdom timestamp strip from the top of the main chat screen so the conversation surface reads more like a familiar chat app.
- Moved the primary altar entry point off the main chat header; it now stays reachable from the profile support entry instead.
- Updated README and CURRENT_STATE so the documented root navigation matches the shipped app shell.

### Fixed

- Normalized header avatar URLs so profile images still load when the backend returns relative paths instead of absolute URLs.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

## 2026-04-07

### Added

- A forward-only UIKit writing composer for the active `AnkyChatView` route, with delete, paste, newline, autocorrect, autocapitalization, spellcheck, smart substitutions, and QuickType all blocked.
- Live session snapshots saved on every keystroke with a 500ms debounce, plus relaunch / foreground recovery for interrupted active drafts.
- An 8-minute milestone effect with haptics and a centered "Anky is ready." overlay before the write submission continues.
- A profile redesign with image-first session cards, archived UTC chat days, full-session detail sheets, and a support/donation entry.
- A JP tutorial lesson covering the one-composer mental model, UIKit text enforcement, autosave, archive storage, and post-write sequencing.

### Changed

- Reworked the active root writing route into one persistent composer that starts in the bottom chat dock and grows into the full writing surface after 8 seconds of continuous typing.
- Replaced the old active writing layout with the fixed Anky stack: top idle bar, full-height writing area, bottom 8-minute progress bar, countdown label, and keyboard.
- Changed post-write delivery so the raw user writing appears first with a visible `COPY` action, then Anky's reflection arrives, then the generated image arrives as its own full-width message.
- Changed chat persistence from one long undifferentiated thread to UTC-day archives so a new day starts fresh without deleting older conversations.
- Updated README, CURRENT_STATE, and JP tutorial docs to match the current routed shell instead of the earlier altar-first write surface notes.

### Fixed

- Fixed content loss during the chat-to-writing transition by keeping one composer instance and one text binding instead of replacing the editor when Anky mode begins.
- Fixed active writing recovery so drafts are no longer limited to a 30-second checkpoint cadence.
- Fixed generated-image layout shifts in chat and profile surfaces by giving image containers stable dimensions before load.
- Fixed older thread and history views so they understand persisted image messages instead of failing exhaustiveness checks after the new image bubble path.
- Fixed processed-history decoding so profile can recover title, reflection, image, and anky id from either flat `/swift/v2/writings` fields or a nested `anky` object returned by the backend.
- Fixed processed-history decoding so profile also reads the backend's flat `anky_reflection` field directly instead of depending on `response` backfill behavior.

### Verified

- `xcodebuild -scheme Anky -project /Users/kithkui/Desktop/Anky/Anky.xcodeproj -destination 'generic/platform=iOS Simulator' build`

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
