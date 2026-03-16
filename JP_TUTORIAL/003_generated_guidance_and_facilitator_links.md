# Lesson 003: Generated Guidance, Facilitator Links, and Writing Images

## Why this lesson exists

This pass simplified three product surfaces:

1. Sit
2. Breathe
3. Facilitator application

It also fixed a real data-flow issue in writing history where an anky image could exist on the backend but still not appear in the iPhone UI yet.

The important lesson for JP is that "simpler UI" does not mean "less architecture." It usually means the architecture gets clearer.

## Mental model: the app should expose the backend's judgment, not ask the user to configure it

Look at:

- [MeditationView.swift](/Users/kithkui/Desktop/Anky/Anky/MeditationView.swift)
- [BreathworkView.swift](/Users/kithkui/Desktop/Anky/Anky/BreathworkView.swift)

Before this simplification, the UI carried more visible choice. That can be useful when the product is exploring. But Anky's deeper model is different:

- the user writes
- the backend interprets that writing
- the app shows what is ready

So the meditation and breathwork home screens now emphasize one path:

- "From writing."
- one generated session card
- one begin action when the session is ready

That is a product decision, but it is also a code-structure decision. The SwiftUI view now aligns more tightly with the backend contract:

- `readyResponse`
- optional `session`
- render if ready

This is a good beginner lesson in declarative UI:

- fewer branches in the product usually means fewer branches in the view tree

## The SwiftUI concept: hide complexity without deleting the engine

In [MeditationView.swift](/Users/kithkui/Desktop/Anky/Anky/MeditationView.swift), the silent sit timer machinery still exists lower in the file.

That is a useful real-world lesson:

- UI surface and implementation surface are not always the same thing

Sometimes you simplify what the user sees first, while keeping lower-level code alive because:

- it may still be reused
- it may return later
- deleting it immediately would create unnecessary risk

What changed is the entry point. The home screen no longer asks the user to make a choice there.

## Facilitator intake: simple inputs, existing backend contract

Open [FacilitatorsView.swift](/Users/kithkui/Desktop/Anky/Anky/FacilitatorsView.swift).

The application sheet now collects only:

- Instagram link
- website link (optional)

That matches the product assumption that almost every facilitator already has an Instagram profile and that Anky can later use that as the canonical social/profile source.

But the current backend request model still expects a broader `FacilitatorApplicationRequest`.

So the code maps simple inputs into the existing contract:

- `name` becomes the Instagram handle
- `bio` stores the Instagram URL
- `approach` stores the optional website
- `contactMethod` uses the Instagram URL

This is an important engineering pattern:

- keep the UI simple
- adapt at the boundary
- avoid forcing backend changes and UI complexity at the same time unless you need both

That mapping lives in `applicationRequest`.

## Writing images: why the image was missing even though the write succeeded

Look at:

- [AnkyWritingSession.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyWritingSession.swift)
- [AppState.swift](/Users/kithkui/Desktop/Anky/Anky/AppState.swift)
- [WritingCacheStore.swift](/Users/kithkui/Desktop/Anky/Anky/WritingCacheStore.swift)
- [AnkyModels.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyModels.swift)

When a write finishes, the app immediately inserts a local history entry with `recordPendingWriting`.

That is good product behavior because the user should see their writing right away.

But that local placeholder does not know the final anky image path yet. The image path belongs to the remote history item returned later by the backend.

So the fix has two parts:

1. After a successful write submission, refresh remote history.
2. When the history sheet opens, refresh remote history again.

Then `WritingCacheStore.mergeRemote` replaces the temporary local synced entry with the real remote entry when the IDs match.

That is the key mental model:

- local write completion gives fast feedback
- remote history gives the richer truth

## URL normalization: backend data is not always shaped the way the UI wants

`CachedWritingEntry.remoteImageURL` in [AnkyModels.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyModels.swift) now accepts:

- full `https://...` image URLs
- relative backend paths

Why does that matter?

Because UI code should not have to wonder whether an image path is:

- absolute
- relative
- prefixed with `/`

The model layer is the right place to normalize that once.

This is a classic client-model responsibility:

- convert API-shaped data into UI-friendly data

## A small SwiftUI detail: placeholders matter

`WritingHistoryRow` now shows a simple placeholder card when:

- the anky image is still loading
- the image is still being prepared
- the image URL fails to load

That is a UX lesson and a SwiftUI lesson:

- conditional rendering is not just for success states
- placeholders make async UI feel intentional instead of broken

## Try this yourself

1. Put a breakpoint in `WritingFlowModel.submitFinishedCapture(appState:)`.
2. Watch `recordPendingWriting` run before `refreshWritings`.
3. Open the history sheet and inspect `appState.writingHistory`.
4. Compare the temporary local entry to the merged remote entry.
5. Change an Instagram input in the facilitator apply sheet and see how `applicationRequest` maps it into the backend model.
