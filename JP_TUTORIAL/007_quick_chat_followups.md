# Lesson 007: Quick Chat Follow-Ups After Writing

## Why this lesson exists

Anky already had a chat-shaped root UI in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift), but after the reflected response landed the user hit a dead end.

They could only start a new writing session.

This change turns that reflected response into the start of a short conversation loop.

The key product idea is:

1. the user writes for one session
2. Anky reflects back
3. the user can reply in plain text
4. the reply stays grounded in the original writing, not just the latest message

That last point is the important architecture lesson.

The follow-up conversation is not a generic chat bot floating free of context.
It is a thin layer attached to one writing session.

## Mental model zero: the active chat route owns its own writing timer

One subtle repo detail matters before you read the rest of this lesson.

The app still contains an older focused writing flow in [AnkyWritingSession.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyWritingSession.swift), but the currently routed experience lives in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

That means the active post-session behavior depends on `ChatViewModel`, not `WritingFlowModel`.

Inside `sessionTick(at:)`, the active session now does three different things:

1. it keeps counting forever once the user has started
2. it treats 8 minutes as a visual milestone, not an auto-send threshold
3. it flips `isSessionPaused = true` when `idleElapsed >= idleLimit` after the user has actually started and `sessionText` is non-empty

That third condition matters because it matches the real product rule:

- if the user has begun writing and then stops for 8 seconds, pause and ask whether to send or keep writing
- if the user opened the writing surface but never typed, idle should not create an empty submission

This is a good state-machine lesson.

`isInSession` by itself is not enough to decide that a session should finish.

You also need evidence that the practice actually started:

- `sessionStartedAt != nil`
- `sessionText.isEmpty == false`

And once the pause state appears, the explicit recovery path matters too:

- `resumeSession()` clears `isSessionPaused`
- `resumeSession()` resets `idleElapsed`
- `resumeSession()` resets `lastInputAt` and `lastTick` to `now` so the timer resumes from the paused value instead of counting the paused gap

## Mental model one: there are now two backend bases in the same API client

Open [AnkyAPI.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyAPI.swift).

The existing mobile API still lives under:

- `https://anky.app/swift/v2`

The quick chat endpoint does not.

It lives at:

- `https://anky.app/api/chat-quick`

That means one `URLSession` client now needs to resolve two different URL bases:

1. the versioned mobile API base
2. the root web base

This is a useful Swift networking lesson.

Do not hack around this by concatenating strings inside views.
Keep URL construction in the API layer.

That is why `AnkyAPI` now stores both:

- `baseURL`
- `webBaseURL`

And why `request(...)` accepts an optional `baseURLOverride`.

That keeps the rest of the app simple:

- writing still uses `/swift/v2/write`
- quick chat uses `/api/chat-quick`

The view model does not need to know how URLs are assembled.

## Mental model two: Codable models define the contract boundary

Open [AnkyModels.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyModels.swift).

Three new types were added:

- `ChatHistoryItem`
- `QuickChatRequest`
- `QuickChatResponse`

This is the backend contract in Swift form.

`ChatHistoryItem` is intentionally small:

- `role`
- `content`

That is enough for the quick chat endpoint because the backend only needs:

- who said it
- what they said

No timestamps, ids, or UI flags are needed in the request payload.

This is a good design habit:

- app-facing models can be richer
- wire models should stay minimal if the API does not need extra fields

## Mental model three: the original writing must survive after the text box clears

Look at `sendToAnky()` in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

Before this change, `sessionText` was cleared as soon as the writing session was submitted.

That made sense for the UI, but it lost the one piece of context the quick chat absolutely needs:

- the original writing itself

The fix was to capture that string into:

- `lastSessionText`

before `sessionText` gets reset.

That is a strong state-management lesson.

Sometimes two pieces of state look redundant but serve different jobs:

- `sessionText` is live editing state
- `lastSessionText` is stable context for post-session conversation

Those are not the same thing.

## Mental model four: UI messages are not the same as backend history

The app already had `ChatMessage` for rendering.

But the backend wants `[ChatHistoryItem]`.

That translation now happens in `buildChatHistory()` in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

The rule is subtle:

- only use messages from the current session
- only use the conversation after the latest writing message
- exclude the writing payload itself

Why?

Because the backend already gets the full writing separately in the `writing` field.

If you also include that large writing block in chat history, you duplicate context and make the request noisier than necessary.

The method finds:

1. the latest writing-session message
2. the first assistant reflection after it
3. every assistant and reply message after that

That means:

- the welcome prompt is excluded
- the original writing blob is excluded
- the reflection and follow-ups are included

This is a useful transformation pattern in Swift:

- rich UI model in memory
- smaller purpose-built network model on the wire

## Mental model five: reply mode is derived state, not a manually toggled flag

Look at `shouldShowReplyComposer` in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

This is important.

The app does not keep a separate boolean like:

- `isInReplyMode = true`

Instead it derives reply mode from real facts:

- `isAnkyTyping == false`
- there is an assistant response after the latest writing message

That is better because it avoids state drift.

If the assistant is still typing, reply mode should be hidden.
If the user starts a brand-new writing session, the latest writing no longer has a reflected response yet, so reply mode disappears automatically.

This is classic SwiftUI thinking:

- prefer derived state from source-of-truth data
- add stored flags only when derivation is impossible or too fragile

## Mental model six: the input bar now has two modes

Open `ChatInputBarView` in [AnkyChatView.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).

It now renders one of two layouts:

1. writing launch mode
2. quick reply mode

Writing launch mode shows:

- the large `write here...` button
- the mic button

Reply mode shows:

- a small new-writing icon button
- a `TextField`
- a send button

This is a good SwiftUI composition lesson.

One view can render multiple product states cleanly when:

- the modes are small
- the branching rule is obvious
- the callbacks are explicit

The callbacks here are:

- `onStartWriting`
- `onStartVoice`
- `onSendMessage`

That makes the input bar reusable and easy to test mentally.

## Mental model seven: persistence bugs often come from the first write, not the second

Open [AppState.swift](/Users/kithkui/Desktop/Anky/Anky/AppState.swift) and [WritingCacheStore.swift](/Users/kithkui/Desktop/Anky/Anky/WritingCacheStore.swift).

Before this change, `CachedWritingEntry` was built with:

- `response: nil`

That meant the reflected response never made it into local writing history, even after polling succeeded.

The fix has two layers:

1. `recordWriting(...)` now stores `response?.ankyResponse` when it already exists
2. `storeReflection(...)` updates the cached entry once the polled `status.ankyResponse` arrives

This is a common async data lesson.

Sometimes the first backend response is incomplete.
That does not mean the local model should stay incomplete forever.

You often need:

- an initial cache write
- then a patch/update when deferred data arrives

That is exactly what happened here.

## How data moves through the follow-up chat feature

Trace the path in order:

1. The user writes in [FullScreenWritingView](/Users/kithkui/Desktop/Anky/Anky/AnkyChatView.swift).
2. `sendToAnky()` captures the writing into `lastSessionText`.
3. The app submits the writing through `POST /swift/v2/write`.
4. The app polls `/swift/v2/writing/{sessionId}/status`.
5. When `status.ankyResponse` arrives, it is:
   - displayed through `deliverAnkyResponse(...)`
   - cached through `storeReflection(...)`
6. `shouldShowReplyComposer` becomes true.
7. The user types into the reply field.
8. `sendReply(...)` appends a local user message, builds `ChatHistoryItem` values, and calls `chatQuick(...)`.
9. `POST /api/chat-quick` returns `{ "response": "..." }`.
10. The app renders that response as another `.anky` message.

That is the whole loop.

## Common failure modes and how to debug them

### Quick chat hits the wrong URL

Check [AnkyAPI.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyAPI.swift).

If the request is accidentally resolved against `/swift/v2`, the final URL becomes wrong.

The correct target is:

- `https://anky.app/api/chat-quick`

not:

- `https://anky.app/swift/v2/api/chat-quick`

### Reply mode appears too early

In this codebase, Anky already shows a welcome prompt as an assistant message.

If you key reply mode off "any assistant message in the current session", the composer appears before the user has written anything.

The fix is to derive from:

- the latest writing message
- the assistant response after that writing

### The backend gets the same user reply twice

That can happen if the current reply is sent both:

- in `message`
- and again at the end of `history`

This implementation guards against that while the request is in flight by excluding the pending reply from the built history.

### The reflected response still does not appear in local history

Check both layers:

- `recordWriting(...)` in [AppState.swift](/Users/kithkui/Desktop/Anky/Anky/AppState.swift)
- `updateResponse(...)` in [WritingCacheStore.swift](/Users/kithkui/Desktop/Anky/Anky/WritingCacheStore.swift)

If only the initial record path is correct but the polling update never runs, the cache will still miss the final reflection.

## Try this yourself

1. Write a session in the simulator.
2. Wait for the reflected response.
3. Type a short reply in the new composer.
4. Put a breakpoint in `sendReply(...)`.
5. Inspect:
   - `lastSessionText`
   - `buildChatHistory()`
   - the final `QuickChatRequest`

That will show you the whole architecture in one debug pass:

- UI state
- request building
- backend contract
- response rendering
