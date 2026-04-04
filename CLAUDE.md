# Anky iOS App

## What this is

Consciousness writing app. Core mechanic: 8 minutes of uninterrupted writing,
session dies if you stop for 8 seconds. That's it. Everything else serves that.

## Design principles

- Never punish. Always save the writing, no matter what.
- No features in onboarding. Only feeling.
- Memory is the silent killer — build it in from the start.
- The keyboard extension is v1, not v2.

## Stack

SwiftUI + SwiftData, iOS 17+. Rive for companion animation (later).
AudioKit for soundscapes (later). MVVM with @Observable.

## Architecture

Chat-centric. No tab bar. AnkyChatView is the root for both locked/unlocked routes.
- Header: Anky pfp (left, opens stories sheet) + user pfp (right, opens profile sheet)
- Center: message list (Anky messages in Georgia serif, user bubbles in SF Pro)
- Bottom: chat input bar with mic, text field, pen/send button
- Writing sessions launch as fullScreenCover, inject session card into chat on completion
- Progress bar represents 8-minute journey through ankyverse chakra colors (not 8-second idle)

## Current state

AnkyChatView: root chat interface, conversation with Anky.
AnkyWritingSession: 8min timer, 8sec pause detection, lives system.
ContentView: routes between boot/welcome/recovery/chat based on AppState.

## Next priorities

1. Anky responds intelligently after writing sessions (API integration)
2. Voice input (speech-to-text) in chat input bar
3. Persist chat messages across sessions
4. Onboarding awakening sequence
5. Keyboard extension
