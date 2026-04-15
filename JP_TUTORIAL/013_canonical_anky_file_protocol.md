# 013 Canonical `.anky` File Protocol

This lesson explains how Anky now turns a finished writing session into the protocol artifact described at `https://anky.app/protocol.md`.

The important mental model is simple:

1. The UI captures forward-only text.
2. The writer model also captures a parallel keystroke stream.
3. When the session ends, that keystroke stream becomes one immutable `.anky` file.
4. The file is hashed on-device.
5. That exact file content is what the submit API sends.

If you remember that the file is the canonical artifact and chat/reflection are downstream side effects, the implementation makes sense.

## The files involved

- `Anky/AnkySessionFileStore.swift`
- `Anky/AnkyChatView.swift`
- `Anky/AnkyWritingSession.swift`
- `Anky/AnkyModels.swift`
- `Anky/AnkyAPI.swift`

## The shared writer helper

`AnkySessionFileStore.swift` now owns the protocol-specific rules:

- converting literal spaces into the token `SPACE`
- NFC-normalizing character payloads
- building the canonical line format
- hashing the exact UTF-8 file bytes with SHA-256
- choosing the storage path
- writing the file
- refreshing `partial_{sessionId}.anky` while a session is still live
- verifying that the file hash matches the filename

This is important architecturally because it keeps protocol rules out of the UI. `ChatViewModel` and `WritingFlowModel` should know when a session starts and ends. They should not each invent their own file format logic.

The shared types in that file are:

- `AnkyKeystrokeRecord`
- `AnkyStoredSessionArtifact`
- `AnkySessionFileStore`

## How keystrokes are captured

The active writer captures keystrokes in:

- `ChatViewModel.recordKeystroke()` in `Anky/AnkyChatView.swift`

The legacy writer captures keystrokes in:

- `WritingFlowModel.handleInput(_:)` in `Anky/AnkyWritingSession.swift`

Both paths now do the same protocol-safe transformation:

- if the literal key was a space, store `"SPACE"`
- otherwise store the NFC-normalized string payload
- if this is the first accepted key, store `firstKeystrokeEpochMs`

That last part matters. The protocol's first line is not "session started" time. It is the absolute Unix epoch in milliseconds of the first accepted keystroke.

## How the canonical string is built

Both writer models still expose `buildAnkySessionString()`, but they now delegate to `AnkySessionFileStore.buildSessionString(...)`.

The canonical format is:

- line 1: `{epoch_ms_of_first_keystroke} {first_payload}`
- later lines: `{delta_ms_since_previous_key} {payload}`
- payload for literal spaces: `SPACE`
- UTF-8
- LF newlines only
- no trailing newline after the last key

That means a real session starts like this:

```text
1776098721818 w
48 r
131 i
41 t
162 e
173 SPACE
```

## Where the file gets written

The file writer uses this path shape:

```text
ankys/yyyy/mm/dd/{session_hash}.anky
```

`session_hash` is the lowercase hex SHA-256 of the exact bytes written to disk.

The helper prefers an iCloud ubiquity container when one exists. If it does not, it falls back to the app's Documents directory.

The app target now ships iCloud Documents entitlements for `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`, so real devices can use the ubiquity container when iCloud Drive is available. Simulator still commonly falls back to Documents.

## Partial files and crash recovery

The active live-writing path now also writes:

```text
ankys/yyyy/mm/dd/partial_{sessionId}.anky
```

every 300ms through `WritingSessionStore.scheduleLiveSave(...)`.

That file uses the exact same line format as the final `.anky` file. The only difference is the filename prefix. It signals: this session is real, but not sealed yet.

On recovery:

- `LiveWritingSessionSnapshot` now carries `firstKeystrokeEpochMs` and `partialAnkyFilePath`
- `ChatViewModel.restoreLiveSessionIfNeeded()` loads the partial file back through `AnkySessionFileStore.loadRecoveredSession(...)`
- the writer rebuilds `ankyKeystrokes`, `firstKeystrokeEpochMs`, and visible text from the partial artifact

On completion:

- the writer rewrites the partial file with the final keystroke stream
- `FileManager.moveItem(at:to:)` renames it to `{session_hash}.anky` in the same directory
- verification runs immediately after the rename

That rename is the sealing boundary for the file on Apple filesystems.

## Why verification happens immediately

After write, `AnkySessionFileStore.verify(filepath:)` recomputes the SHA-256 of the file bytes and compares it to the filename stem.

That gives you a very direct invariant:

- if the filename says `abc123....anky`
- then `sha256(file_bytes)` must equal `abc123...`

This is a good example of keeping a system honest with one cheap, local check right at the boundary where data becomes canonical.

## How the submit API uses the file

`AnkyAPI.makeAnkySubmitRequest(...)` now prefers `capture.ankyFilePath`.

That means the request is built from the actual file bytes on disk when the file exists. The method:

- reads the file data
- decodes it as UTF-8 text for the JSON `session` field
- reuses the stored SHA-256 when available
- parses the first line back into a real `Date`
- sends that as `started_at`

That is a good Swift pattern to notice: the capture model carries just enough metadata for later layers to stay honest without forcing the UI layer to know networking details.

## Why `LocalWritingCapture` changed

`LocalWritingCapture` now carries:

- `ankySessionString`
- `ankyFilePath`
- `sessionHash`

This does not make the capture itself canonical. The file is still canonical.

The capture just becomes the app's handoff object between:

- writing UI
- sealing UI
- background submission
- local history bookkeeping

## Failure modes to watch

- If `firstKeystrokeEpochMs` is missing, the file cannot be protocol-compliant.
- If the written file hash does not match the filename, something is wrong with the bytes and the app should log loudly.
- If you later change line endings, whitespace handling, or normalization, you are changing the protocol artifact, not just refactoring UI code.
- Live-session restore still does not persist the full keystroke stream yet, so a restored mid-session draft is still a protocol edge case worth revisiting later.
- Legacy draft recovery still uses its older draft path; the new partial-file crash recovery is currently wired into the active live snapshot route that powers the chat-first writer.

## Swift concepts this touches

- value types for session artifacts (`struct`)
- helper namespaces with `enum`
- `Data` and UTF-8 encoding
- `CryptoKit.SHA256`
- `URL` path composition
- `URLResourceValues` for backup behavior
- sharing one protocol implementation across multiple writer models

## Try this yourself

1. Open `AnkySessionFileStore.buildSessionString(...)`.
2. Follow where `firstKeystrokeEpochMs` comes from in `recordKeystroke()` and `handleInput(_:)`.
3. Follow the call into `persistSession(...)`.
4. Then read `AnkyAPI.makeAnkySubmitRequest(...)` and confirm that the request is built from the file when `ankyFilePath` exists.

That full chain is the core data flow for the `.anky` artifact.
