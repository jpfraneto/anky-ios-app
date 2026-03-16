# Lesson 001: The Mental Model of the Anky iOS App

## Why this app exists

Anky iOS is the native front end for a larger system.

The app is where the user writes, sits, breathes, and checks in. The backend is where the deeper work happens: storing writing, generating meditation and breathwork, building memory, and matching facilitators.

That means you should think about the app in two layers:

1. Local experience layer
2. Remote system layer

The local layer handles:

- screens
- input
- animation
- haptics
- caching
- audio playback
- session persistence

The remote layer handles:

- identity and backend sessions
- writing ingestion
- meditation generation
- breathwork generation
- sadhana records
- facilitators and recommendations

## The first mental model: one app state, many feature surfaces

Start with [AppState.swift](/Users/kithkui/Desktop/Anky/Anky/AppState.swift).

This file is the global coordination layer. It answers questions like:

- is the user authenticated?
- who is the current user?
- which tab is active?
- is there an active writing, meditation, or breathwork experience?
- what prompt and writing history are cached locally?

In SwiftUI, this is a common pattern:

- one shared state object for app-wide concerns
- smaller view-local state for feature-specific behavior

So:

- `AppState` is global state
- each screen also uses local `@State` for temporary UI behavior

## The second mental model: SwiftUI views are functions of state

Look at [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift).

The root view does not "manually navigate" the way older UIKit apps often did. Instead, it renders one branch based on `appState.authStatus`:

- checking
- signed out
- signed in

That is a core SwiftUI idea:

- state changes
- the view tree recomputes
- the UI reflects the new truth

This is why SwiftUI feels declarative. You are not saying "push this screen now." You are saying "if the user is signed in, the shell exists; otherwise the auth view exists."

## The third mental model: the app is split by practice domain

The app is organized around the user journey:

- write
- sit
- breathe
- sadhana
- facilitators

The important files are:

- [AnkyWritingSession.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyWritingSession.swift)
- [MeditationView.swift](/Users/kithkui/Desktop/Anky/Anky/MeditationView.swift)
- [BreathworkView.swift](/Users/kithkui/Desktop/Anky/Anky/BreathworkView.swift)
- [SadhanaView.swift](/Users/kithkui/Desktop/Anky/Anky/SadhanaView.swift)
- [FacilitatorsView.swift](/Users/kithkui/Desktop/Anky/Anky/FacilitatorsView.swift)

This is not just UI organization. It mirrors the product model.

## The fourth mental model: models define the contract with the backend

Look at [AnkyModels.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyModels.swift).

These types are not random structs. They are the Swift mirror of backend JSON.

Examples:

- `AuthResponse`
- `UserProfile`
- `MobileWriteRequest`
- `ReadyResponse`
- `GuidanceSession`

This is a very important lesson for mobile work:

- backend routes define the external contract
- Codable models define the client-side shape of that contract
- bugs often come from those two drifting apart

When the backend changes, the models and client code usually need to change too.

## The fifth mental model: AnkyAPI is the app's network boundary

Open [AnkyAPI.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyAPI.swift).

This file is the network gateway. The rest of the app should not be building raw `URLRequest`s everywhere. Instead, it asks `AnkyAPI` to do named tasks:

- `me()`
- `writings()`
- `submitWriting(_:)`
- `meditationReady()`
- `breathworkSession(style:)`

That creates a clean boundary:

- UI code asks for domain actions
- `AnkyAPI` knows how to turn those actions into HTTP requests

This makes the app easier to reason about and easier to debug.

## The sixth mental model: playback is a state machine

The most non-trivial native code in the app is the spoken guidance flow.

Start with [GuidancePlaybackView.swift](/Users/kithkui/Desktop/Anky/Anky/GuidancePlaybackView.swift).

The key idea is that meditation and breathwork playback are not just "play audio." They are sequences of phases:

- narration
- breathing
- hold
- rest
- body scan
- visualization

So the playback model behaves like a state machine:

- take the current phase
- decide what kind of phase it is
- speak, animate, or wait
- advance to the next phase

Important native pieces here:

- `AVSpeechSynthesizer` for text-to-speech
- `UIImpactFeedbackGenerator` for haptics
- SwiftUI animation for the orb/breath visuals
- async tasks for timing and sequencing

This is a good example of how native app work often combines:

- business logic
- OS frameworks
- UI state
- timing

## The seventh mental model: native modules are powerful, but they are strict

Two examples:

### Audio

[AnkyAudioSession.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyAudioSession.swift) configures the app's audio session so spoken guidance behaves correctly.

This matters because iOS audio is not just "play sound." The OS needs to know the app's intent:

- playback
- recording
- spoken audio
- mixing behavior

### Keychain

[KeychainHelper.swift](/Users/kithkui/Desktop/Anky/Anky/KeychainHelper.swift) exists because session tokens are secrets. UserDefaults is not the right place for that.

This is another common iOS pattern:

- UI and app state feel simple
- security and lifecycle details are not simple
- you usually isolate those details behind a helper

## The eighth mental model: offline support is a product decision, not just a technical extra

Look at:

- [OfflineQueue.swift](/Users/kithkui/Desktop/Anky/Anky/OfflineQueue.swift)
- [WritingCacheStore.swift](/Users/kithkui/Desktop/Anky/Anky/WritingCacheStore.swift)
- [GuidanceCacheStore.swift](/Users/kithkui/Desktop/Anky/Anky/GuidanceCacheStore.swift)

Why do these exist?

Because the core practice cannot depend on perfect connectivity.

If the user has a real writing session and the network is down, the app should preserve the session and sync later. That is not a "nice to have." It follows directly from the product stance.

## The ninth mental model: Xcode project structure affects runtime, not just build time

This matters a lot for the issue you just hit.

There is a difference between:

- linking a framework
- embedding a framework

If the app binary references a dynamic framework at runtime but the framework is not copied into the app bundle, the app can build and still fail at launch with a `dyld` abort.

That is why Xcode project structure matters:

- sources compile your code
- resources bundle assets
- framework linking satisfies the linker
- embedding makes runtime loading possible on device

This is a core mobile lesson: a successful build does not always mean a runnable app.

## How data moves through a typical feature

Take guided meditation as the example:

1. The UI asks whether a meditation is ready in [MeditationView.swift](/Users/kithkui/Desktop/Anky/Anky/MeditationView.swift).
2. That view calls `AnkyAPI.shared.meditationReady()`.
3. The backend returns a `ReadyResponse`.
4. The response becomes a `GuidanceSession`.
5. The view launches [GuidancePlaybackView.swift](/Users/kithkui/Desktop/Anky/Anky/GuidancePlaybackView.swift).
6. The playback model sequences the phases, speech, haptics, and animation.
7. Completion is logged back to the backend.

That pattern shows up throughout the app:

- fetch or create data
- decode into models
- render UI from models
- trigger a local native experience
- sync completion or updates back to the server

## Try this yourself

Read these files in this order:

1. [ContentView.swift](/Users/kithkui/Desktop/Anky/Anky/ContentView.swift)
2. [AppState.swift](/Users/kithkui/Desktop/Anky/Anky/AppState.swift)
3. [AnkyAPI.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyAPI.swift)
4. [AnkyModels.swift](/Users/kithkui/Desktop/Anky/Anky/AnkyModels.swift)
5. [MeditationView.swift](/Users/kithkui/Desktop/Anky/Anky/MeditationView.swift)
6. [GuidancePlaybackView.swift](/Users/kithkui/Desktop/Anky/Anky/GuidancePlaybackView.swift)

As you read, ask:

- what state does this file own?
- what state does it consume?
- what backend route does it depend on?
- what native iOS framework does it depend on?
- what would break if this file disappeared?

Those questions will teach you to see the app as a system instead of as random Swift files.
