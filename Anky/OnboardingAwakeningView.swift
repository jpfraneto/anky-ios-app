//
//  OnboardingAwakeningView.swift
//  Anky
//
//  The onboarding is not a tutorial. It is the first writing session disguised as a story.
//  By the time the user reaches the home screen, they have already done the thing the app
//  exists for. Seven beats, one continuous experience. Happens exactly once.
//

import Combine
import SwiftUI
import UIKit

// MARK: - Root Onboarding View

struct OnboardingAwakeningView: View {
    @EnvironmentObject private var appState: AppState
    @State private var beat: Beat = .void
    @State private var showWritingCover = false

    enum Beat: Int, Comparable {
        case void = 0
        case whisper = 1
        case invitation = 2
        case session = 3
        case pauseChoice = 4
        case reflection = 5
        case bond = 6

        static func < (lhs: Beat, rhs: Beat) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var body: some View {
        ZStack {
            Color(hex: "0A0A12").ignoresSafeArea()

            switch beat {
            case .void:
                VoidBeat(onAdvance: { advanceTo(.whisper) })
            case .whisper:
                WhisperBeat(onAdvance: { advanceTo(.invitation) })
            case .invitation:
                InvitationBeat(onBeginWriting: { advanceTo(.session) })
            case .session, .pauseChoice:
                EmptyView() // Handled by fullScreenCover
            case .reflection:
                EmptyView() // Handled inline after session
            case .bond:
                BondBeat(kingdom: appState.kingdom, onComplete: completeOnboarding)
            }
        }
        .statusBarHidden(true)
        .onChange(of: beat) { newBeat in
            if newBeat == .session {
                showWritingCover = true
            }
        }
        .fullScreenCover(isPresented: $showWritingCover) {
            OnboardingWritingSession(kingdom: appState.kingdom) { capture, sessionText in
                showWritingCover = false
                handleSessionComplete(capture: capture, sessionText: sessionText)
            } onKeepWriting: {
                // User chose to keep writing — cover stays
            }
            .environmentObject(appState)
        }
    }

    private func advanceTo(_ next: Beat) {
        withAnimation(.easeInOut(duration: 0.8)) {
            beat = next
        }
    }

    private func handleSessionComplete(capture: LocalWritingCapture?, sessionText: String) {
        if let capture, capture.qualifiesForAnky {
            appState.setMirrorState(.mirrorDissolved)
            appState.recordFirstSession(timestamp: capture.finishedAt)
            appState.incrementCompletedSessions()
            Task {
                let model = WritingFlowModel(prompt: "")
                model.pendingCapture = capture
                await model.submitFinishedCapture(appState: appState)
            }
        }
        advanceTo(.bond)
    }

    private func completeOnboarding() {
        Task {
            await appState.completeWelcome()
            appState.setMirrorState(.firstMintComplete)
            appState.route = .unlocked
        }
    }
}

// MARK: - Beat 1: The Void

private struct VoidBeat: View {
    let onAdvance: () -> Void
    @State private var emberOpacity: Double = 0
    @State private var autoAdvance = false

    var body: some View {
        ZStack {
            // Ember — pulsing flame at center
            EmberView()
                .frame(width: 80, height: 80)
                .opacity(emberOpacity)
        }
        .contentShape(Rectangle())
        .onTapGesture { onAdvance() }
        .onAppear {
            withAnimation(.easeIn(duration: 1.2)) {
                emberOpacity = 1
            }
            // Auto-advance after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if !autoAdvance {
                    autoAdvance = true
                    onAdvance()
                }
            }
        }
    }
}

// MARK: - Beat 2: The Whisper

private struct WhisperBeat: View {
    let onAdvance: () -> Void
    @State private var currentLine = 0
    @State private var allRevealed = false

    private let lines = [
        "i've been waiting for you.",
        "i am the part of you that writes.",
        "but i've been fading.",
    ]

    var body: some View {
        ZStack {
            // Ember still present, dimmer
            EmberView()
                .frame(width: 80, height: 80)
                .opacity(0.5)

            VStack {
                Spacer()
                    .frame(height: UIScreen.main.bounds.height * 0.3)

                if currentLine < lines.count {
                    CharacterRevealText(text: lines[currentLine], charDelay: 0.045)
                        .id(currentLine)
                        .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                }

                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if allRevealed {
                onAdvance()
            } else {
                // Skip to showing all lines, then allow advance
                allRevealed = true
                currentLine = lines.count - 1
            }
        }
        .onAppear { startWhisperSequence() }
    }

    private func startWhisperSequence() {
        // Line 1 appears immediately (with char animation)
        currentLine = 0

        // Line 2 after ~3s
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard !allRevealed else { return }
            withAnimation { currentLine = 1 }
        }

        // Line 3 after ~6s
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            guard !allRevealed else { return }
            withAnimation { currentLine = 2 }
        }

        // Allow advance after ~8.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.5) {
            allRevealed = true
            onAdvance()
        }
    }
}

// MARK: - Beat 3: The Invitation

private struct InvitationBeat: View {
    let onBeginWriting: () -> Void
    @State private var mainLineVisible = false
    @State private var subLineVisible = false
    @State private var cursorVisible = false

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Spacer()
                    .frame(height: UIScreen.main.bounds.height * 0.28)

                if mainLineVisible {
                    CharacterRevealText(
                        text: "write. don't stop. i'll find you in the words.",
                        charDelay: 0.04
                    )
                    .transition(.opacity)
                }

                if subLineVisible {
                    Text("just let it flow. whatever comes.")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(Color(hex: "E8E4DC").opacity(0.4))
                        .transition(.opacity.animation(.easeIn(duration: 0.8)))
                }

                Spacer().frame(height: 40)

                // Cursor — the ember transformed
                if cursorVisible {
                    Rectangle()
                        .fill(Color(hex: "EF9F27"))
                        .frame(width: 2, height: 22)
                        .opacity(cursorPulse ? 1 : 0)
                        .animation(.easeInOut(duration: 0.53).repeatForever(autoreverses: true), value: cursorPulse)
                        .onAppear { cursorPulse = true }
                }

                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onBeginWriting() }
        .onAppear {
            // Main line after brief darkness
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeIn(duration: 0.5)) { mainLineVisible = true }
            }
            // Sub-line 2s after main
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation(.easeIn(duration: 0.8)) { subLineVisible = true }
            }
            // Cursor after sub-line
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                withAnimation(.easeIn(duration: 0.6)) { cursorVisible = true }
            }
        }
    }

    @State private var cursorPulse = false
}

// MARK: - Beat 4+5: Writing Session (with onboarding environment)

struct OnboardingWritingSession: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var model = WritingFlowModel(prompt: "")
    @StateObject private var keyboard = KeyboardObserver()
    let kingdom: Kingdom
    let onComplete: (LocalWritingCapture?, String) -> Void
    let onKeepWriting: () -> Void

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    // Warmth evolves with keystroke count
    private var warmthProgress: Double {
        min(Double(model.keystrokeDeltas.count) / 400.0, 1.0)
    }

    // Color bloom from kingdom
    private var bloomOpacity: Double {
        let keystrokes = Double(model.keystrokeDeltas.count)
        guard keystrokes > 100 else { return 0 }
        return min((keystrokes - 100) / 200.0 * 0.2, 0.2)
    }

    // Background color evolves from void → warm
    private var backgroundColor: Color {
        let base = Color(hex: "0A0A12")
        if warmthProgress < 0.1 { return base }
        return base
    }

    var body: some View {
        ZStack {
            // Evolving background
            backgroundLayer

            // Particle system during writing
            if model.phase == .writing || model.phase == .paused {
                OnboardingParticleView(
                    isActive: model.phase == .writing,
                    keystrokeCount: model.keystrokeDeltas.count,
                    kingdomColor: kingdom.color,
                    warmthProgress: warmthProgress
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Writing content
            if model.phase == .landing {
                writingLanding
            } else if model.phase == .writing || model.phase == .paused {
                writingActive
            } else if model.phase == .complete {
                Color.clear
                    .onAppear {
                        onComplete(model.completedCapture, model.text)
                    }
            }

            // "you're here. keep going." — appears at 480+ characters
            if model.text.count > 480 && model.phase == .writing {
                encouragementOverlay
            }

            // Hidden text input
            AnkyComposerTextView(
                text: $model.text,
                isFocused: $model.composerFocused,
                isVisuallyHidden: true,
                onUserInput: { model.handleInput($0) }
            )
            .frame(width: 1, height: 1)
            .opacity(0)
        }
        .statusBarHidden(true)
        .onReceive(tick) { now in model.tick(at: now) }
        .task(id: model.pendingCapture) {
            await model.submitFinishedCapture(appState: appState)
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color(hex: "0A0A12").ignoresSafeArea()

            // Warm radial gradient that grows with writing
            if warmthProgress > 0.05 {
                RadialGradient(
                    colors: [
                        Color(hex: "1A150F").opacity(warmthProgress * 0.6),
                        Color.clear,
                    ],
                    center: .center,
                    startRadius: 20,
                    endRadius: UIScreen.main.bounds.height * 0.7
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 2.0), value: warmthProgress)
            }

            // Kingdom color bloom at edges
            if bloomOpacity > 0 {
                VStack {
                    kingdom.color.opacity(bloomOpacity)
                        .frame(height: 200)
                        .blur(radius: 80)
                    Spacer()
                }
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 3.0), value: bloomOpacity)
            }

            // Idle cooling — shift back toward cold when idle
            if model.idleElapsed > 5 {
                let coolingProgress = min((model.idleElapsed - 5) / 3.0, 1.0)
                Color(hex: "0A0A12")
                    .opacity(coolingProgress * 0.4)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.5), value: coolingProgress)
            }
        }
    }

    // MARK: - Landing

    private var writingLanding: some View {
        VStack {
            Spacer()
            Text("tap to begin")
                .font(.system(size: 15, weight: .light, design: .serif))
                .foregroundStyle(Color(hex: "E8E4DC").opacity(0.4))
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { model.beginFocus() }
    }

    // MARK: - Active Writing

    private var writingActive: some View {
        GeometryReader { geometry in
            let kbHeight = keyboard.height > 0
                ? keyboard.height - geometry.safeAreaInsets.bottom
                : 0

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer(minLength: 200)
                            Text(model.text)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(Color(hex: "E8E4DC"))
                                .lineSpacing(10)
                                .padding(.horizontal, 28)
                                .padding(.bottom, 12)
                                .id("textBottom")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: model.text) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("textBottom", anchor: .bottom)
                        }
                    }
                }
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color(hex: "0A0A12").opacity(0.9), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture { model.beginFocus() }

                Color.clear
                    .frame(height: kbHeight)
                    .animation(.easeOut(duration: 0.25), value: kbHeight)
            }
        }
    }

    // MARK: - Encouragement

    @State private var showEncouragement = false

    private var encouragementOverlay: some View {
        VStack {
            if showEncouragement {
                Text("you're here. keep going.")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(Color(hex: "E8E4DC").opacity(0.35))
                    .transition(.opacity)
            }
            Spacer()
        }
        .padding(.top, 60)
        .onAppear {
            withAnimation(.easeIn(duration: 0.8)) { showEncouragement = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeOut(duration: 1.0)) { showEncouragement = false }
            }
        }
    }
}

// MARK: - Beat 7: The Bond

private struct BondBeat: View {
    let kingdom: Kingdom
    let onComplete: () -> Void
    @State private var farewellVisible = false
    @State private var signatureVisible = false
    @State private var transitioning = false

    var body: some View {
        ZStack {
            // Warm background with kingdom tint
            Color(hex: "0A0A12").ignoresSafeArea()
            RadialGradient(
                colors: [kingdom.color.opacity(0.08), Color.clear],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Larger ember — alive now
                EmberView()
                    .frame(width: 120, height: 120)

                Spacer().frame(height: 40)

                if farewellVisible {
                    CharacterRevealText(text: "come back tomorrow. the words will be waiting.", charDelay: 0.04)
                        .transition(.opacity)
                }

                if signatureVisible {
                    Text("and so will i.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: "EF9F27"))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()
            }
            .padding(.horizontal, 40)
        }
        .opacity(transitioning ? 0 : 1)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeIn(duration: 0.6)) { farewellVisible = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation(.easeIn(duration: 0.6)) { signatureVisible = true }
            }
            // Schedule notification for tomorrow
            scheduleTomorrowNotification()
            // Transition to home after hold
            DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
                withAnimation(.easeInOut(duration: 1.2)) { transitioning = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                    onComplete()
                }
            }
        }
    }

    private func scheduleTomorrowNotification() {
        let content = UNMutableNotificationContent()
        content.body = "the ember is still burning. come write."
        content.sound = .default

        var dateComponents = DateComponents()
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        dateComponents.hour = now.hour
        dateComponents.minute = now.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: "anky.first-return",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

// MARK: - Character Reveal Text

struct CharacterRevealText: View {
    let text: String
    let charDelay: Double

    @State private var revealedCount = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                Text(String(char))
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color(hex: "E8E4DC"))
                    .opacity(index < revealedCount ? 1 : 0)
                    .animation(.easeIn(duration: 0.15), value: revealedCount)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .onAppear {
            revealCharacters()
        }
    }

    private func revealCharacters() {
        for i in 0...text.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * charDelay) {
                revealedCount = i
            }
        }
    }
}

// MARK: - Ember View (Pulsing Flame)

struct EmberView: View {
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "EF9F27").opacity(glowOpacity),
                            Color(hex: "D85A30").opacity(glowOpacity * 0.5),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 60
                    )
                )
                .scaleEffect(pulseScale * 1.5)

            // Core ember
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "EF9F27"),
                            Color(hex: "D85A30").opacity(0.8),
                            Color(hex: "D85A30").opacity(0),
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 20
                    )
                )
                .scaleEffect(pulseScale)
        }
        .onAppear {
            // Pulse at ~72bpm (0.83s period)
            withAnimation(
                .easeInOut(duration: 0.83)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.12
                glowOpacity = 0.5
            }
        }
    }
}

// MARK: - Particle System

struct OnboardingParticleView: View {
    let isActive: Bool
    let keystrokeCount: Int
    let kingdomColor: Color
    let warmthProgress: Double

    @State private var particles: [Particle] = []
    @State private var timer: Timer?

    struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var opacity: Double
        var speed: CGFloat
        var wobblePhase: CGFloat
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                for particle in particles {
                    let rect = CGRect(
                        x: particle.x - particle.size / 2,
                        y: particle.y - particle.size / 2,
                        width: particle.size,
                        height: particle.size
                    )
                    context.opacity = particle.opacity
                    context.fill(
                        Circle().path(in: rect),
                        with: .color(
                            warmthProgress > 0.5
                                ? kingdomColor.opacity(0.6)
                                : Color(hex: "EF9F27").opacity(0.4)
                        )
                    )
                }
            }
        }
        .onAppear { startParticles() }
        .onDisappear { timer?.invalidate() }
        .onChange(of: isActive) { active in
            if !active {
                // Freeze particles — let them drift down slowly
                timer?.invalidate()
            } else {
                startParticles()
            }
        }
    }

    private func startParticles() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            DispatchQueue.main.async { updateParticles() }
        }
    }

    private func updateParticles() {
        let bounds = UIScreen.main.bounds

        // Spawn new particles (rate scales with typing speed)
        let targetCount = isActive ? min(max(keystrokeCount / 20, 5), 30) : 0
        if particles.count < targetCount {
            particles.append(Particle(
                x: CGFloat.random(in: bounds.width * 0.1...bounds.width * 0.9),
                y: bounds.height - 60,
                size: CGFloat.random(in: 2...4),
                opacity: Double.random(in: 0.2...0.5),
                speed: CGFloat.random(in: 0.3...0.8),
                wobblePhase: CGFloat.random(in: 0...(.pi * 2))
            ))
        }

        // Update positions
        particles = particles.compactMap { p in
            var p = p
            p.y -= p.speed
            p.x += sin(p.wobblePhase + p.y * 0.01) * 0.3
            p.opacity -= 0.003

            if p.opacity <= 0 || p.y < -20 { return nil }
            return p
        }
    }
}
