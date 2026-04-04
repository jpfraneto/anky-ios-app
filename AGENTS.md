## Shared memory

Before starting any session, read CURRENT_STATE.md in full.
It is the authoritative record of what is working, what is broken,
and what is deferred. Update it at the end of every session that
makes meaningful changes.

Do not rely on conversation history or your own assumptions about
what was shipped. CURRENT_STATE.md is the truth.

# Anky iOS Agent Guide

## What Anky is

Anky is not a generic journaling app. It is a native iPhone container for a deeper system.

The core practice is 8 minutes of uninterrupted stream-of-consciousness writing. The session ends if the user stops writing for 8 seconds. That writing is the door. Everything else exists in service of what surfaces there.

From that writing, the broader Anky system can generate:

- reflections
- personalized meditation
- mood-matched breathwork
- image-based ankys
- longitudinal memory
- facilitator recommendations when a human should step in

This repo is the iOS client for the Rust/Axum backend described in the Anky monorepo whitepaper and companion docs. The app should be built with that relationship in mind. The phone experience is not separate from the system. It is the native interface to it.

## Product stance

- Build Anky like a contemplative space, not a productivity tool.
- The writing flow is the highest priority surface.
- Never punish the user for imperfect practice.
- Always preserve writing locally if submission fails.
- Keep the technology invisible. The user should feel listened to, not processed.
- Prefer native iOS behavior and clear architecture over clever abstractions.

## Design stance

- Dark, cave-like atmosphere by default.
- Warm amber/gold accents with restraint.
- Minimal chrome. Every control must earn its place.
- Motion should feel slow, intentional, and calm.
- Avoid flashy, gamified, or productivity-app patterns.

## Engineering stance

- Treat the backend contract as real. Verify `/swift/v1/*` behavior against the backend when needed.
- Preserve offline behavior for writing and queued sync whenever practical.
- Be careful with native frameworks like AVFoundation, haptics, audio session management, Keychain, and authentication SDKs.
- When adding dynamic frameworks, make sure they are embedded correctly for device builds, not just linked for simulator builds.
- Keep the app understandable. JP is learning from this codebase.

## Teaching requirement for JP

This repo is also JP's Swift learning ground. The agent must actively teach while it builds.

When doing meaningful work, the agent should:

- explain the mental model behind the change in clear, plain English
- connect the implementation to the relevant Swift and iOS concepts
- reference the actual files and code paths involved
- prefer explaining why a structure exists, not just what was typed
- point out how a feature connects to the backend and to the rest of the app

## JP tutorial workflow

Maintain a root folder named `JP_TUTORIAL`.

When the agent completes a meaningful feature, refactor, integration, or bug fix, it should add or update a lesson in `JP_TUTORIAL` that teaches JP what was touched.

Each lesson should aim to teach:

- the mental model
- the Swift language concepts involved
- the SwiftUI or UIKit/native framework concepts involved
- how the relevant files fit together
- how data moves through the feature
- how the app talks to the backend
- common failure modes and how to debug them

Good lesson topics include:

- app state and navigation
- async networking
- Codable models and backend contracts
- Keychain and auth flows
- audio session configuration
- AVSpeechSynthesizer playback sequencing
- haptics and animation timing
- offline queues and local caching
- Xcode project structure, frameworks, signing, and runtime loading

## Lesson format

- Use numbered files with clear names, for example `001_app_mental_model.md`.
- Write lessons for a smart beginner who is learning by reading the real codebase.
- Use concrete references to files in this repo.
- Keep the tone direct and practical.
- Include a short "try this yourself" section when useful.

## Docs to keep aligned

When behavior materially changes, update the docs that matter:

- `README.md`
- `CHANGELOG.md`
- `JP_TUTORIAL/*` lessons relevant to the change

## Existing local context

Use these files as context when relevant:

- `README.md`
- `CHANGELOG.md`
- `CLAUDE.md`

When backend/system meaning matters, ground the app in the Anky monorepo whitepaper and supporting docs rather than treating this app as an isolated project.

