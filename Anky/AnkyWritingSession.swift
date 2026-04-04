//
//  AnkyWritingSession.swift
//  Anky
//

import Combine
import SwiftUI
import UIKit

// MARK: - Writing Session Haptics

enum WritingHaptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()

    /// First keystroke — the session is alive.
    static func sessionStarted() {
        mediumImpact.impactOccurred(intensity: 0.8)
    }

    /// Phase transition.
    static func phaseTransition(_ phase: WritingFlowModel.Phase) {
        switch phase {
        case .writing:
            lightImpact.impactOccurred(intensity: 0.5)
        case .paused:
            notification.notificationOccurred(.warning)
        case .complete:
            heavyImpact.impactOccurred(intensity: 1.0)
        case .landing:
            break
        }
    }

    /// Idle warning ticks at 5s, 6s, 7s.
    static func idleWarningTick(seconds: Int) {
        switch seconds {
        case 5:
            lightImpact.impactOccurred(intensity: 0.3)
        case 6:
            lightImpact.impactOccurred(intensity: 0.5)
        case 7:
            mediumImpact.impactOccurred(intensity: 0.7)
        default:
            break
        }
    }

    /// 8-minute threshold crossed — you made it.
    static func thresholdCrossed() {
        notification.notificationOccurred(.success)
    }

    /// Session ended by idle timeout — final thud.
    static func sessionEnded() {
        heavyImpact.impactOccurred(intensity: 1.0)
    }
}

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
final class WritingFlowModel: ObservableObject {
    enum Phase {
        case landing
        case writing
        case paused
        case complete
    }

    static let totalLives = 2

    @Published var prompt: String
    @Published var phase: Phase = .landing
    @Published var text = ""
    @Published var composerFocused = false
    @Published var sessionElapsed: TimeInterval = 0
    @Published var idleElapsed: TimeInterval = 0
    @Published var livesRemaining = totalLives
    @Published var hasCrossedThreshold = false
    @Published var isSubmitting = false
    @Published var glyphPulseCount = 0
    @Published var outcome: WritingOutcome?
    @Published var pendingCapture: LocalWritingCapture?
    @Published var completedCapture: LocalWritingCapture?

    private let sessionGoal = LocalWritingCapture.requiredDurationForAnky
    private let idleWarningStart: TimeInterval = 3
    private let idleLimit: TimeInterval = 8
    private let draftSaveCadence: TimeInterval = 5
    private let checkpointCadence: TimeInterval = 30

    private var sessionID = UUID().uuidString
    private var startedAt: Date?
    private var lastTick = Date()
    private var lastInputAt: Date?
    private var lastDraftSaveAt: TimeInterval = 0
    private var lastCheckpointAt: TimeInterval = 0
    private(set) var keystrokeDeltas: [Double] = []
    private var lastIdleWarningSecond: Int = 0
    private var didFireThresholdHaptic = false

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
        return 1 + CGFloat(normalized * 0.22)
    }

    var currentDisplayGlyph: String {
        guard let character = text.last else { return "•" }
        return Self.displayGlyph(for: character)
    }

    var visibleWritingLine: String {
        let sanitized = Self.sanitizedText(text)
        return String(sanitized.suffix(320))
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

    func submitEarlyIfQualified() {
        guard qualifiesForAnky else { return }
        finishSession()
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
            WritingHaptics.sessionStarted()
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
        sendCheckpointIfNeeded()
        refreshThresholdState()

        // Idle warning haptics at 5s, 6s, 7s
        let idleSecond = Int(idleElapsed)
        if idleSecond >= 5 && idleSecond <= 7 && idleSecond != lastIdleWarningSecond {
            lastIdleWarningSecond = idleSecond
            WritingHaptics.idleWarningTick(seconds: idleSecond)
        }
        if idleElapsed < 5 { lastIdleWarningSecond = 0 }

        if idleElapsed >= idleLimit {
            loseLifeOrComplete()
        }
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
        lastCheckpointAt = 0
        keystrokeDeltas = []
        WritingSessionStore.clearDraft()
    }

    func submitFinishedCapture(appState: AppState) async {
        guard let capture = pendingCapture else { return }
        defer { pendingCapture = nil }

        isSubmitting = true
        defer { isSubmitting = false }

        // Seal the session (encrypt on-device) before sending anything
        let sealedSession = sealCaptureIfPossible(capture: capture, appState: appState)
        if sealedSession == nil {
            print("[AnkyProtocol] Encryption failed — submitting in degraded mode (plaintext only)")
        }

        // Always try to send to backend (v2 handles short sessions too)
        do {
            guard await appState.ensureAuthenticatedForWrite() else {
                // Not authenticated — queue if anky-worthy, otherwise save locally
                if capture.qualifiesForAnky {
                    await appState.queueWrite(capture)
                    appState.recordWriting(capture, response: nil, syncState: .pending)
                    outcome = WritingOutcome(capture: capture, delivery: .queued)
                } else {
                    appState.recordWriting(capture, response: nil, syncState: .localOnly)
                }
                return
            }

            // TODO: Remove plaintext transmission once enclave reflection pipeline is live.
            // The sealed envelope sent to POST /api/sessions/seal is the cryptographic source of truth.
            // Plaintext is only sent now because the reflection generation (Claude API) needs to read it.
            // When the enclave handles reflection generation, this line gets deleted.
            let response = try await AnkyAPI.shared.submitWriting(capture.request)

            // Send sealed session to enclave endpoint (with retry on failure)
            if let sealed = sealedSession {
                Task {
                    do {
                        _ = try await AnkyAPI.shared.sealSession(sealed)
                        SealedSessionStore.clearPending(sealed.sessionId)
                    } catch {
                        // Queue for retry on next app launch / network reconnection
                        SealedSessionStore.markPending(sealed.sessionId)
                    }
                }
            }

            if response.isAnky && response.persisted == true {
                await appState.applyPersistedAnkySuccess(capture: capture, response: response)
                // Auto-mint cNFT + archive to Arweave for every persisted anky
                Self.autoMintCNFT(sessionId: capture.sessionId, appState: appState)
                Self.archiveToArweave(sessionId: capture.sessionId, text: capture.text)
                outcome = Self.remoteOutcome(capture: capture)
            } else if response.persisted == true {
                appState.recordWriting(capture, response: response, syncState: .synced)
                outcome = WritingOutcome(capture: capture, delivery: .synced)
            } else {
                appState.recordWriting(capture, response: response, syncState: .localOnly)
                outcome = WritingOutcome(capture: capture, delivery: .failed("saved locally"))
            }
        } catch let error as AnkyError {
            if error.isConnectivityIssue || error == .missingSession || error == .unauthorized {
                if capture.qualifiesForAnky {
                    await appState.queueWrite(capture)
                    appState.recordWriting(capture, response: nil, syncState: .pending)
                    outcome = WritingOutcome(capture: capture, delivery: .queued)
                } else {
                    appState.recordWriting(capture, response: nil, syncState: .localOnly)
                }
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

    /// Encrypt the session on-device. Encryption is the primary path.
    /// If it fails, we submit plaintext as a degraded fallback so the user still gets their
    /// reflection. But this is NOT normal operation.
    private func sealCaptureIfPossible(capture: LocalWritingCapture, appState: AppState) -> SealedSession? {
        do {
            let walletAddress = (try? SeedIdentityManager.shared.walletAddress()) ?? ""
            let metadata = SessionMetadata(
                sessionId: capture.sessionId,
                timestamp: capture.finishedAt,
                durationSeconds: capture.duration,
                kingdom: appState.kingdom.rawValue,
                wordCount: capture.wordCount,
                keystrokeCount: capture.keystrokeDeltas.count,
                walletAddress: walletAddress
            )
            let sealed = try AnkyProtocol.sealSession(content: capture.text, metadata: metadata)
            SealedSessionStore.save(sealed)
            return sealed
        } catch {
            print("[AnkyProtocol] Encryption failed — submitting in degraded mode (plaintext only): \(error.localizedDescription)")
            return nil
        }
    }

    private func sendCheckpointIfNeeded() {
        guard !text.isEmpty else { return }
        guard sessionElapsed - lastCheckpointAt >= checkpointCadence else { return }
        lastCheckpointAt = sessionElapsed

        let request = MobileWriteRequest(
            text: text,
            duration: sessionElapsed,
            sessionId: sessionID,
            keystrokeDeltas: keystrokeDeltas,
            isCheckpoint: true
        )

        Task {
            do {
                _ = try await AnkyAPI.shared.submitWriting(request)
            } catch {
                // Checkpoint failures are silent — local draft is the fallback
            }
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
        let nowQualifies = qualifiesForAnky
        if nowQualifies && !hasCrossedThreshold && !didFireThresholdHaptic {
            didFireThresholdHaptic = true
            WritingHaptics.thresholdCrossed()
        }
        hasCrossedThreshold = nowQualifies
    }

    private func loseLifeOrComplete() {
        guard livesRemaining > 0 else { return }

        if livesRemaining > 1 {
            livesRemaining -= 1
            phase = .paused
            WritingHaptics.phaseTransition(.paused)
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
        WritingHaptics.sessionEnded()

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

    /// Auto-mint a cNFT for every persisted anky. Fire-and-forget with retry queue.
    static func autoMintCNFT(sessionId: String, appState: AppState) {
        Task {
            do {
                let walletAddress = try SeedIdentityManager.shared.walletAddress()
                let mintResponse = try await AnkyAPI.shared.mintMirror(
                    writingSessionId: sessionId,
                    recipient: walletAddress
                )
                if mintResponse.success {
                    appState.saveMirrorMint(response: mintResponse)
                    PendingMintStore.dequeue(sessionId: sessionId)
                    print("[cNFT] Minted anky \(sessionId) → tx: \(mintResponse.txSignature ?? "pending")")
                } else if mintResponse.alreadyMinted == true {
                    PendingMintStore.dequeue(sessionId: sessionId)
                    print("[cNFT] Already minted: \(sessionId)")
                } else {
                    PendingMintStore.enqueue(sessionId: sessionId)
                    print("[cNFT] Mint failed, queued for retry: \(mintResponse.error ?? "unknown")")
                }
            } catch {
                PendingMintStore.enqueue(sessionId: sessionId)
                print("[cNFT] Mint deferred (offline), queued: \(error.localizedDescription)")
            }
        }
    }

    /// Upload writing text to Arweave via Irys for permanent storage. Fire-and-forget.
    static func archiveToArweave(sessionId: String, text: String) {
        Task {
            do {
                let txId = try await ArweaveStore.upload(sessionId: sessionId, text: text)
                print("[Arweave] Archived \(sessionId) → tx: \(txId)")
            } catch {
                ArweaveStore.enqueue(sessionId: sessionId, text: text)
                print("[Arweave] Upload deferred, queued: \(error.localizedDescription)")
            }
        }
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

// All view code has been moved to ContentView.swift
