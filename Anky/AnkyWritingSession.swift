//
//  AnkyWritingSession.swift
//  Anky
//

import Combine
import Observation
import SwiftUI
import UIKit

struct WritingOutcome: Equatable {
    enum Delivery: Equatable {
        case synced
        case queued
        case failed(String)
    }

    let capture: LocalWritingCapture
    let delivery: Delivery
}

@MainActor
@Observable
final class WritingFlowModel {
    enum Phase {
        case landing
        case writing
        case paused
        case complete
    }

    static let totalLives = 2

    var prompt: String
    var phase: Phase = .landing
    var text = ""
    var composerFocused = false
    var sessionElapsed: TimeInterval = 0
    var idleElapsed: TimeInterval = 0
    var livesRemaining = totalLives
    var hasCrossedThreshold = false
    var isSubmitting = false
    var glyphPulseCount = 0
    var outcome: WritingOutcome?
    var pendingCapture: LocalWritingCapture?
    var completedCapture: LocalWritingCapture?

    private let sessionGoal = LocalWritingCapture.requiredDurationForAnky
    private let idleWarningStart: TimeInterval = 3
    private let idleLimit: TimeInterval = 8
    private let draftSaveCadence: TimeInterval = 5

    private var sessionID = UUID().uuidString
    private var startedAt: Date?
    private var lastTick = Date()
    private var lastInputAt: Date?
    private var lastDraftSaveAt: TimeInterval = 0
    private var keystrokeDeltas: [Double] = []

    init(prompt: String) {
        self.prompt = prompt
        if let draft = WritingSessionStore.loadDraft() {
            self.prompt = draft.prompt
            self.text = draft.text
            self.sessionElapsed = draft.sessionElapsed
            self.livesRemaining = max(min(draft.livesRemaining, Self.totalLives), 1)
            self.phase = draft.wasInterrupted && !draft.text.isEmpty ? .paused : (draft.text.isEmpty ? .landing : .writing)
            self.sessionID = draft.sessionId
            self.keystrokeDeltas = draft.keystrokeDeltas
            self.startedAt = draft.text.isEmpty ? nil : Date().addingTimeInterval(-draft.sessionElapsed)
            self.hasCrossedThreshold = LocalWritingCapture.qualifiesForAnky(text: draft.text, duration: draft.sessionElapsed)
            self.composerFocused = true
        } else {
            self.text = ""
        }
    }

    var hasStarted: Bool {
        startedAt != nil
    }

    var wordCount: Int {
        LocalWritingCapture.wordCount(in: text)
    }

    var sessionProgress: Double {
        guard hasStarted else { return 0 }
        return min(sessionElapsed / sessionGoal, 1)
    }

    var elapsedLabel: String {
        Self.formatDuration(sessionElapsed)
    }

    var idleDrainProgress: Double {
        guard phase == .writing else { return 0 }
        guard idleElapsed >= idleWarningStart else { return 0 }

        let warningSpan = max(idleLimit - idleWarningStart, 0.01)
        return min(max((idleElapsed - idleWarningStart) / warningSpan, 0), 1)
    }

    var glyphOpacity: Double {
        switch phase {
        case .landing:
            return 1
        case .writing:
            return 1 - (idleDrainProgress * 0.82)
        case .paused:
            return 0.24
        case .complete:
            return completedCapture?.qualifiesForAnky == true ? 0.22 : 0.14
        }
    }

    var glyphFractureProgress: Double {
        switch phase {
        case .landing:
            return 0
        case .writing:
            return idleDrainProgress
        case .paused, .complete:
            return hasStarted ? 1 : 0
        }
    }

    var rhythmMultiplier: CGFloat {
        let recent = Array(keystrokeDeltas.suffix(8))
        guard !recent.isEmpty else { return 1 }

        let mean = recent.reduce(0, +) / Double(recent.count)
        let normalized = min(max((900 - mean) / 700, 0), 1)
        return 1 + CGFloat(normalized * 0.8)
    }

    var currentDisplayGlyph: String {
        guard let character = text.last else { return "•" }
        return Self.displayGlyph(for: character)
    }

    var ribbonCharacters: [String] {
        Array(text.dropLast().suffix(180)).map(Self.displayGlyph(for:))
    }

    var qualifiesForAnky: Bool {
        LocalWritingCapture.qualifiesForAnky(text: text, duration: sessionElapsed)
    }

    func heartFill(for index: Int) -> Double {
        guard phase != .complete else { return 0 }
        guard index < livesRemaining else { return 0 }

        if index < livesRemaining - 1 {
            return 1
        }

        return phase == .writing ? 1 - idleDrainProgress : 1
    }

    func updatePrompt(_ value: String) {
        guard !hasStarted else { return }
        prompt = value
    }

    func beginFocus() {
        composerFocused = true
    }

    func handleInput(_ newText: String) {
        let now = Date()
        let sanitized = Self.sanitizedText(newText)
        text = sanitized

        guard phase != .complete else { return }

        if phase == .paused {
            resumeFromPauseFromTyping(at: now)
        }

        if phase == .landing {
            phase = .writing
        }

        if startedAt == nil {
            startedAt = now
            sessionID = UUID().uuidString
            sessionElapsed = 0
        } else if let lastInputAt {
            let delta = now.timeIntervalSince(lastInputAt) * 1000
            if delta.isFinite && delta > 0 {
                keystrokeDeltas.append(delta.rounded())
            }
        }

        lastInputAt = now
        lastTick = now
        idleElapsed = 0
        glyphPulseCount += 1
        refreshThresholdState()
    }

    func tick(at now: Date) {
        guard phase == .writing else { return }
        defer { lastTick = now }

        guard hasStarted else { return }

        let delta = min(max(now.timeIntervalSince(lastTick), 0), 0.25)
        sessionElapsed += delta
        idleElapsed = lastInputAt.map { now.timeIntervalSince($0) } ?? 0

        saveDraftIfNeeded()
        refreshThresholdState()

        if idleElapsed >= idleLimit {
            loseLifeOrComplete()
        }
    }

    func resumeManually() {
        guard phase == .paused else { return }
        resumeFromPauseManually(at: .now)
    }

    func reset(for prompt: String) {
        self.prompt = prompt
        phase = .landing
        text = ""
        composerFocused = true
        sessionElapsed = 0
        idleElapsed = 0
        livesRemaining = Self.totalLives
        hasCrossedThreshold = false
        isSubmitting = false
        glyphPulseCount = 0
        outcome = nil
        pendingCapture = nil
        completedCapture = nil
        sessionID = UUID().uuidString
        startedAt = nil
        lastTick = Date()
        lastInputAt = nil
        lastDraftSaveAt = 0
        keystrokeDeltas = []
        WritingSessionStore.clearDraft()
    }

    func submitFinishedCapture(appState: AppState) async {
        guard let capture = pendingCapture else { return }
        defer { pendingCapture = nil }

        guard capture.qualifiesForAnky else {
            appState.recordWriting(capture, response: nil, syncState: .localOnly)
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            guard await appState.ensureAuthenticatedForWrite() else {
                await appState.queueWrite(capture)
                appState.recordWriting(capture, response: nil, syncState: .pending)
                outcome = WritingOutcome(
                    capture: capture,
                    delivery: .queued
                )
                return
            }

            let response = try await AnkyAPI.shared.submitWriting(capture.request)
            if response.persisted == true {
                await appState.applyPersistedAnkySuccess(capture: capture, response: response)
                outcome = Self.remoteOutcome(capture: capture)
            } else {
                appState.recordWriting(capture, response: nil, syncState: .localOnly)
                outcome = WritingOutcome(
                    capture: capture,
                    delivery: .failed("saved locally")
                )
            }
        } catch let error as AnkyError {
            if error.isConnectivityIssue || error == .missingSession || error == .unauthorized {
                await appState.queueWrite(capture)
                appState.recordWriting(capture, response: nil, syncState: .pending)
                outcome = WritingOutcome(
                    capture: capture,
                    delivery: .queued
                )
                return
            }

            appState.recordWriting(capture, response: nil, syncState: .localOnly)
            outcome = WritingOutcome(
                capture: capture,
                delivery: .failed(error.errorDescription ?? "saved locally")
            )
        } catch {
            appState.recordWriting(capture, response: nil, syncState: .localOnly)
            outcome = WritingOutcome(
                capture: capture,
                delivery: .failed(error.localizedDescription)
            )
        }
    }

    private func saveDraftIfNeeded() {
        guard !text.isEmpty else { return }
        guard sessionElapsed - lastDraftSaveAt >= draftSaveCadence else { return }
        WritingSessionStore.saveDraft(
            StoredWritingDraft(
                sessionId: sessionID,
                prompt: prompt,
                text: text,
                sessionElapsed: sessionElapsed,
                livesRemaining: livesRemaining,
                keystrokeDeltas: keystrokeDeltas,
                wasInterrupted: phase != .complete,
                updatedAt: .now
            )
        )
        lastDraftSaveAt = sessionElapsed
    }

    private func refreshThresholdState() {
        hasCrossedThreshold = qualifiesForAnky
    }

    private func loseLifeOrComplete() {
        guard livesRemaining > 0 else { return }

        if livesRemaining > 1 {
            livesRemaining -= 1
            phase = .paused
            idleElapsed = idleLimit
            lastInputAt = nil
            lastTick = Date()
            composerFocused = true
            return
        }

        finishSession()
    }

    private func finishSession() {
        guard hasStarted else { return }

        let capture = LocalWritingCapture(
            sessionId: sessionID,
            prompt: prompt,
            text: text,
            duration: sessionElapsed,
            wordCount: wordCount,
            keystrokeDeltas: keystrokeDeltas,
            finishedAt: .now,
            estimatedFlowScore: Self.estimateFlowScore(deltasInMilliseconds: keystrokeDeltas, duration: sessionElapsed)
        )

        composerFocused = false
        phase = .complete
        outcome = nil
        completedCapture = capture
        pendingCapture = capture
        WritingSessionStore.clearDraft()
    }

    private func resumeFromPauseFromTyping(at now: Date) {
        phase = .writing
        composerFocused = true
        idleElapsed = 0
        lastInputAt = nil
        lastTick = now
    }

    private func resumeFromPauseManually(at now: Date) {
        phase = .writing
        composerFocused = true
        idleElapsed = 0
        lastInputAt = now
        lastTick = now
    }

    private static func remoteOutcome(capture: LocalWritingCapture) -> WritingOutcome {
        WritingOutcome(
            capture: capture,
            delivery: .synced
        )
    }

    private static func estimateFlowScore(deltasInMilliseconds: [Double], duration: TimeInterval) -> Double {
        guard !deltasInMilliseconds.isEmpty else { return 0.42 }

        let deltas = deltasInMilliseconds.map { max($0 / 1000, 0.02) }
        let mean = deltas.reduce(0, +) / Double(deltas.count)
        let variance = deltas.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(deltas.count)
        let coefficient = sqrt(variance) / max(mean, 0.001)
        let stability = max(0, 1 - min(coefficient, 1))
        let continuity = max(0, 1 - min(deltas.filter { $0 > 2.2 }.reduce(0, +) / max(duration, 1), 1))
        let density = min(Double(deltas.count) / 700, 1)
        let score = 0.45 * stability + 0.30 * continuity + 0.25 * density
        return min(max((score * 100).rounded() / 100, 0), 1)
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func sanitizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private static func displayGlyph(for character: Character) -> String {
        character.isWhitespace ? "·" : String(character)
    }
}

struct WritingsView: View {
    @Environment(AppState.self) private var appState
    @State private var model = WritingFlowModel(prompt: PromptLibrary.currentPrompt())
    @State private var keyboardOverlap: CGFloat = 0

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private let ribbonHeight: CGFloat = 78
    private let floatingBottomPadding: CGFloat = 12

    var body: some View {
        let copy = WritingExperienceStrings.current

        ZStack {
            backgroundLayer

            switch model.phase {
            case .landing, .writing, .paused:
                composeScreen(copy: copy)
            case .complete:
                completionScreen(copy: copy)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onReceive(tick) { now in
            model.tick(at: now)
        }
        .onAppear {
            model.updatePrompt(appState.prompt)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                model.beginFocus()
            }
        }
        .onChange(of: appState.prompt) { _, newValue in
            model.updatePrompt(newValue)
        }
        .onChange(of: model.phase) { _, newPhase in
            appState.activeExperience = (newPhase == .writing || newPhase == .paused) ? .writing : nil
            appState.hasInProgressWriting = WritingSessionStore.hasDraft()
        }
        .task(id: model.pendingCapture) {
            await model.submitFinishedCapture(appState: appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            updateKeyboardOverlap(from: note)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.22)) {
                keyboardOverlap = 0
            }
        }
        .animation(.easeInOut(duration: 0.6), value: model.phase)
        .animation(.easeInOut(duration: 0.25), value: model.idleElapsed)
        .animation(.easeOut(duration: 0.22), value: keyboardOverlap)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: model.livesRemaining)
        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: model.glyphPulseCount)
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient.ankyBackground

            RadialGradient(
                colors: [
                    model.hasCrossedThreshold ? .ankyGold.opacity(0.22) : .ankyAmber.opacity(0.12),
                    .clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 420
            )
            .blur(radius: 20)

            RadialGradient(
                colors: [
                    Color.ankyPurpleSoft.opacity(0.12 + (model.idleDrainProgress * 0.12)),
                    .clear
                ],
                center: .top,
                startRadius: 30,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    private func composeScreen(copy: WritingExperienceStrings) -> some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top + 12
            let bottomInset = keyboardBottomPadding(for: proxy.safeAreaInsets.bottom)
            let ribbonReserve = model.hasStarted ? ribbonHeight + bottomInset : bottomInset
            let contentHeight = max(proxy.size.height - topInset - ribbonReserve, 0)
            let stageSize = CGSize(width: max(proxy.size.width - 48, 0), height: contentHeight)

            ZStack(alignment: .bottom) {
                AnkyComposerTextView(
                    text: $model.text,
                    isFocused: $model.composerFocused,
                    isVisuallyHidden: true,
                    onUserInput: { model.handleInput($0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                VStack(spacing: 0) {
                    if model.hasStarted {
                        sessionChrome(copy: copy)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 16)
                    }

                    Spacer(minLength: 0)

                    if model.hasStarted {
                        glyphStage(size: stageSize)
                            .padding(.horizontal, 24)
                    } else {
                        landingStage(copy: copy)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: contentHeight, alignment: .top)
                .padding(.top, topInset)

                if model.hasStarted {
                    WritingRibbonView(
                        characters: model.ribbonCharacters,
                        fontSize: CGFloat(16) * model.rhythmMultiplier,
                        pulseCount: model.glyphPulseCount
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, bottomInset)
                }

                if model.phase == .paused {
                    pausedOverlay(copy: copy, bottomPadding: bottomInset + ribbonHeight + 28)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                model.beginFocus()
            }
        }
    }

    private func completionScreen(copy: WritingExperienceStrings) -> some View {
        ZStack {
            if model.hasStarted {
                frozenExperienceBackdrop
            }

            if model.completedCapture?.qualifiesForAnky == true {
                successfulCompletion(copy: copy)
            } else {
                incompleteCompletion(copy: copy)
            }
        }
    }

    private func sessionChrome(copy: WritingExperienceStrings) -> some View {
        HStack(spacing: 12) {
            metricPill(
                value: "\(model.wordCount)",
                label: copy[.wordsLabel],
                accent: model.hasCrossedThreshold
            )

            Spacer()

            HStack(spacing: 10) {
                Text(copy[.livesLabel])
                    .font(.custom("Righteous-Regular", size: 11))
                    .foregroundStyle(Color.ankyMuted)

                HStack(spacing: 6) {
                    ForEach(0..<WritingFlowModel.totalLives, id: \.self) { index in
                        HeartLifeView(fill: model.heartFill(for: index))
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.ankyPanel.opacity(0.84))
            )

            Spacer()

            Text(model.elapsedLabel)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(model.hasCrossedThreshold ? Color.ankyGold : Color.ankyInk)
                .monospacedDigit()
        }
    }

    private func landingStage(copy: WritingExperienceStrings) -> some View {
        VStack(spacing: 14) {
            Text(copy[.writeNow].uppercased(with: .current))
                .font(.custom("Righteous-Regular", size: 44))
                .foregroundStyle(Color.ankyInk)
                .multilineTextAlignment(.center)

            Text(copy[.eightMinutes])
                .font(.custom("Georgia", size: 22))
                .foregroundStyle(Color.ankyMuted)
        }
        .padding(.bottom, 28)
    }

    private func glyphStage(size: CGSize) -> some View {
        let baseSize = min(size.width * 0.62, 260)
        let dynamicSize = min(baseSize * max(model.rhythmMultiplier, 1), size.height * 0.78)

        return FracturedGlyphView(
            glyph: model.currentDisplayGlyph,
            fontSize: max(dynamicSize, 92),
            opacity: model.glyphOpacity,
            fractureProgress: model.glyphFractureProgress,
            isCharged: model.hasCrossedThreshold,
            pulseCount: model.glyphPulseCount
        )
        .frame(maxWidth: .infinity)
    }

    private func pausedOverlay(copy: WritingExperienceStrings, bottomPadding: CGFloat) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 14) {
                Button {
                    model.resumeManually()
                } label: {
                    Text(copy[.continueAction])
                        .font(.custom("Righteous-Regular", size: 18))
                        .foregroundStyle(Color.ankyInk)
                        .padding(.horizontal, 24)
                        .frame(height: 52)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.ankyPanelRaised.opacity(0.95))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.ankyGold.opacity(0.22), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)

                Text(copy[.resumeHint])
                    .font(.custom("Georgia", size: 15))
                    .foregroundStyle(Color.ankyMuted)
            }
            .padding(.bottom, bottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ankyBlack.opacity(0.24))
    }

    private var frozenExperienceBackdrop: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            FracturedGlyphView(
                glyph: model.currentDisplayGlyph,
                fontSize: 190,
                opacity: model.completedCapture?.qualifiesForAnky == true ? 0.18 : 0.1,
                fractureProgress: 1,
                isCharged: model.completedCapture?.qualifiesForAnky == true,
                pulseCount: model.glyphPulseCount
            )
            .padding(.horizontal, 28)

            Spacer(minLength: 0)

            if model.hasStarted {
                WritingRibbonView(
                    characters: model.ribbonCharacters,
                    fontSize: CGFloat(16) * model.rhythmMultiplier,
                    pulseCount: model.glyphPulseCount
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
                .opacity(0.34)
            }
        }
        .allowsHitTesting(false)
    }

    private func incompleteCompletion(copy: WritingExperienceStrings) -> some View {
        VStack(spacing: 8) {
            Spacer()

            Button {
                model.reset(for: appState.prompt)
            } label: {
                Text(copy[.tryAgainAction])
                    .font(.custom("Georgia", size: 24))
                    .foregroundStyle(Color.ankyInk)
                    .padding(.horizontal, 26)
                    .frame(height: 56)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.ankyPanel.opacity(0.78))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)

            Text(copy[.eightMinutes])
                .font(.custom("Georgia", size: 13))
                .foregroundStyle(Color.ankyMuted)

            Spacer(minLength: 150)
        }
        .padding(.horizontal, 24)
    }

    private func successfulCompletion(copy: WritingExperienceStrings) -> some View {
        let appCopy = AppCopy.current

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 90)

                if model.isSubmitting || (model.completedCapture?.qualifiesForAnky == true && model.outcome == nil) {
                    submissionCard(
                        title: copy[.ankyListeningTitle],
                        body: copy[.ankyListeningBody],
                        loading: true
                    )
                } else if let outcome = model.outcome {
                    switch outcome.delivery {
                    case .synced:
                        submissionCard(
                            title: copy[.ankyBornTitle],
                            body: copy[.ankyBornBody],
                            loading: false
                        )

                        Button {
                            appState.currentTab = .ankys
                            model.reset(for: appState.prompt)
                        } label: {
                            primaryActionLabel(appCopy[.openAnkysAction])
                        }
                        .buttonStyle(.plain)

                    case .queued:
                        submissionCard(
                            title: copy[.writingSafeTitle],
                            body: copy[.writingSafeBody],
                            loading: false
                        )

                    case .failed(let message):
                        VStack(alignment: .leading, spacing: 10) {
                            submissionCard(
                                title: copy[.writingSafeTitle],
                                body: copy[.writingSafeBody],
                                loading: false
                            )

                            Text(message)
                                .font(.custom("Georgia", size: 14))
                                .foregroundStyle(Color.ankyMuted)
                        }
                    }

                    Button {
                        model.reset(for: appState.prompt)
                    } label: {
                        secondaryActionLabel(copy[.writeAgainAction])
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 120)
            }
            .padding(.horizontal, 22)
        }
    }

    private func submissionCard(title: String, body: String, loading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if loading {
                ProgressView()
                    .tint(Color.ankyGold)
            }

            Text(title)
                .font(.custom("Righteous-Regular", size: 30))
                .foregroundStyle(Color.ankyInk)

            Text(body)
                .font(.custom("Georgia", size: 18))
                .foregroundStyle(Color.ankyInk.opacity(0.9))
                .lineSpacing(6)
        }
        .padding(24)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.ankyPanelRaised.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.ankyGold.opacity(0.12), lineWidth: 1)
            )
    }

    private func primaryActionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.custom("Righteous-Regular", size: 18))
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(Color.ankyBlack)
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.ankyGold)
        )
    }

    private func secondaryActionLabel(_ title: String) -> some View {
        Text(title)
            .font(.custom("Righteous-Regular", size: 17))
            .foregroundStyle(Color.ankyInk)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.ankyPanel.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }

    private func metricPill(value: String, label: String, accent: Bool) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.custom("Righteous-Regular", size: 16))
                .foregroundStyle(accent ? Color.ankyGold : Color.ankyInk)

            Text(label)
                .font(.custom("Righteous-Regular", size: 11))
                .foregroundStyle(Color.ankyMuted)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            Capsule(style: .continuous)
                .fill(Color.ankyPanel.opacity(0.84))
        )
    }

    private func keyboardBottomPadding(for safeAreaBottom: CGFloat) -> CGFloat {
        max(keyboardOverlap, safeAreaBottom) + floatingBottomPadding
    }

    private func updateKeyboardOverlap(from note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let screenMaxY = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
            .bounds
            .maxY
            ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.screen.bounds.maxY }
                .first
            ?? frame.maxY
        let overlap = max(0, screenMaxY - frame.minY)
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.22
        let curveRaw = (note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? UIView.AnimationCurve.easeInOut.rawValue

        withAnimation(animation(for: duration, curveRawValue: curveRaw)) {
            keyboardOverlap = overlap
        }
    }

    private func animation(for duration: Double, curveRawValue: Int) -> Animation {
        switch UIView.AnimationCurve(rawValue: curveRawValue) {
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        case .linear:
            return .linear(duration: duration)
        default:
            return .easeInOut(duration: duration)
        }
    }
}

private struct HeartLifeView: View {
    let fill: Double

    var body: some View {
        ZStack {
            Image(systemName: "heart")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.12))

            Image(systemName: "heart.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient.ankyWarmGlow)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: CGFloat(16) * CGFloat(fill))
                }
        }
        .frame(width: 18, height: 18)
    }
}

private struct FracturedGlyphView: View {
    let glyph: String
    let fontSize: CGFloat
    let opacity: Double
    let fractureProgress: Double
    let isCharged: Bool
    let pulseCount: Int

    var body: some View {
        ZStack {
            baseGlyph

            ForEach(Array(Self.shards.enumerated()), id: \.offset) { index, shard in
                glyphLayer
                    .mask(ShardMask(shard: shard))
                    .offset(
                        x: shard.xDrift * fractureProgress,
                        y: shard.yDrift * fractureProgress
                    )
                    .rotationEffect(.degrees(Double(shard.rotation) * fractureProgress))
                    .opacity(opacity * (0.2 + (fractureProgress * 0.7)))
            }
        }
        .scaleEffect(CGFloat(1 + (fractureProgress * 0.03) + (pulseScale * 0.035)))
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: pulseScale)
        .onChange(of: pulseCount) { _, _ in
            pulseScale = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                pulseScale = 0
            }
        }
    }

    @State private var pulseScale = 0.0

    private var baseGlyph: some View {
        glyphLayer
            .opacity(opacity)
            .blur(radius: fractureProgress * 1.4)
    }

    private var glyphLayer: some View {
        Text(glyph)
            .font(.system(size: fontSize, weight: .semibold, design: .serif))
            .foregroundStyle(
                LinearGradient(
                    colors: isCharged
                        ? [Color.ankyInk, Color.ankyGold.opacity(0.92), Color.ankyInk]
                        : [Color.ankyInk, Color.white.opacity(0.88), Color.ankyInk],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: (isCharged ? Color.ankyGold : Color.ankyPurpleSoft).opacity(0.2 + (fractureProgress * 0.2)), radius: 24)
    }

    fileprivate struct ShardConfiguration {
        let start: CGFloat
        let end: CGFloat
        let topInset: CGFloat
        let bottomInset: CGFloat
        let xDrift: CGFloat
        let yDrift: CGFloat
        let rotation: CGFloat
    }

    private static let shards: [ShardConfiguration] = [
        .init(start: 0.00, end: 0.18, topInset: 0.00, bottomInset: 0.03, xDrift: -10, yDrift: -18, rotation: -4),
        .init(start: 0.18, end: 0.37, topInset: -0.02, bottomInset: 0.02, xDrift: 14, yDrift: -8, rotation: 5),
        .init(start: 0.37, end: 0.58, topInset: 0.01, bottomInset: -0.02, xDrift: -18, yDrift: 10, rotation: -6),
        .init(start: 0.58, end: 0.79, topInset: -0.01, bottomInset: 0.03, xDrift: 16, yDrift: 14, rotation: 6),
        .init(start: 0.79, end: 1.00, topInset: 0.02, bottomInset: 0.00, xDrift: -8, yDrift: 18, rotation: -4),
    ]
}

private struct ShardMask: Shape {
    let shard: FracturedGlyphView.ShardConfiguration

    func path(in rect: CGRect) -> Path {
        let top = rect.height * shard.start
        let bottom = rect.height * shard.end
        let topOffset = rect.height * shard.topInset
        let bottomOffset = rect.height * shard.bottomInset

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: top + topOffset))
        path.addLine(to: CGPoint(x: rect.maxX, y: top - topOffset))
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom + bottomOffset))
        path.addLine(to: CGPoint(x: rect.minX, y: bottom - bottomOffset))
        path.closeSubpath()
        return path
    }
}

private struct WritingRibbonView: View {
    let characters: [String]
    let fontSize: CGFloat
    let pulseCount: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: max(fontSize * 0.18, 4)) {
                    ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                        Text(character)
                            .font(.system(size: fontSize, weight: .medium, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.84))
                            .shadow(color: accentColor(for: index).opacity(0.18), radius: 8)
                    }

                    Color.clear
                        .frame(width: 1, height: 1)
                        .id("tail")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .mask(
                LinearGradient(
                    colors: [.clear, .white, .white, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 78)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.ankyBlack.opacity(0.76))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    )
            )
            .onAppear {
                proxy.scrollTo("tail", anchor: .trailing)
            }
            .onChange(of: characters.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("tail", anchor: .trailing)
                }
            }
            .onChange(of: pulseCount) { _, _ in
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo("tail", anchor: .trailing)
                }
            }
        }
    }

    private func accentColor(for index: Int) -> Color {
        let colors: [Color] = [
            .red,
            .orange,
            .yellow,
            .green,
            .cyan,
            .blue,
            .purple,
        ]
        return colors[index % colors.count]
    }
}

private struct WritingHistorySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    ForEach(appState.writingHistory) { entry in
                        WritingHistoryRow(entry: entry)
                    }
                }
                .padding(20)
            }
            .background(Color.ankyBlack.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Writing History")
                        .font(.custom("Righteous-Regular", size: 18))
                        .foregroundStyle(Color.ankyInk)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.ankyGold)
                }
            }
        }
        .presentationBackground(Color.ankyBlack)
        .task {
            await appState.refreshWritings()
        }
    }
}

private struct WritingHistoryRow: View {
    let entry: CachedWritingEntry
    @State private var expanded = false

    private let copy = WritingExperienceStrings.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.createdAtLabel)
                        .font(.custom("Righteous-Regular", size: 15))
                        .foregroundStyle(Color.ankyInk)

                    Text("\(entry.durationLabel) · \(entry.wordCount) \(copy[.wordsLabel])")
                        .font(.custom("Georgia", size: 14))
                        .foregroundStyle(Color.ankyMuted)
                }

                Spacer()

                if entry.isAnky {
                    Text("ANKY")
                        .font(.custom("Righteous-Regular", size: 11))
                        .foregroundStyle(Color.ankyGold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.ankyPanel.opacity(0.95))
                        )
                }
            }

            if entry.isAnky {
                ankyImage
            }

            Text(entry.content)
                .font(.custom("Georgia", size: 17))
                .foregroundStyle(Color.ankyInk.opacity(0.9))
                .lineSpacing(6)
                .lineLimit(expanded ? nil : 6)

            Button(expanded ? "Show less" : "Read full writing") {
                expanded.toggle()
            }
            .font(.custom("Righteous-Regular", size: 12))
            .foregroundStyle(Color.ankyGold)
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.ankyPanelRaised.opacity(0.92))
        )
    }

    @ViewBuilder
    private var ankyImage: some View {
        if let imageURL = entry.remoteImageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    imagePlaceholder("Image unavailable.")
                case .empty:
                    imagePlaceholder("Loading image.")
                @unknown default:
                    imagePlaceholder("Loading image.")
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            imagePlaceholder("Image preparing.")
        }
    }

    private func imagePlaceholder(_ text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.ankyPanel)

            VStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.ankyPurpleSoft)

                Text(text)
                    .font(.custom("Righteous-Regular", size: 13))
                    .foregroundStyle(Color.ankyMuted)
            }
        }
        .frame(height: 180)
    }
}

#Preview {
    WritingsView()
        .environment(AppState())
}
