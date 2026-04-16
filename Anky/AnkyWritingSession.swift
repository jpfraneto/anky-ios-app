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

    static let totalLives = 1

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

    private let sessionGoal = AnkyContract.Qualification.minimumDurationSeconds
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

    // .anky session format tracking
    private var ankyKeystrokes: [AnkyKeystrokeRecord] = []
    private var ankyPreviousTextCount: Int = 0
    private var firstKeystrokeEpochMs: Int64?
    private(set) var ankySessionString: String?

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

        // Capture new characters for .anky format (forward-only, so diff is the tail)
        if sanitized.count > ankyPreviousTextCount {
            let startIdx = sanitized.index(sanitized.startIndex, offsetBy: ankyPreviousTextCount)
            for char in sanitized[startIdx...] {
                if ankyKeystrokes.isEmpty {
                    firstKeystrokeEpochMs = Int64(now.timeIntervalSince1970 * 1000)
                }
                let canonical = AnkySessionFileStore.canonicalPayload(for: char)
                ankyKeystrokes.append(AnkyKeystrokeRecord(payload: canonical, timestamp: now))
            }
        }
        ankyPreviousTextCount = sanitized.count

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
        ankyKeystrokes = []
        ankyPreviousTextCount = 0
        firstKeystrokeEpochMs = nil
        ankySessionString = nil
        WritingSessionStore.clearDraft()
    }

    func submitFinishedCapture(appState: AppState) async {
        guard let capture = pendingCapture else { return }
        defer { pendingCapture = nil }

        isSubmitting = true
        defer { isSubmitting = false }

        // Relay .anky session to enclave (fire-and-forget)
        if let sessionString = capture.ankySessionString, let sessionHash = capture.sessionHash {
            Self.relayAnkySession(sessionString: sessionString, sessionHash: sessionHash)
        }

        // Check authentication first
        guard await appState.ensureAuthenticatedForWrite() else {
            if capture.qualifiesForAnky {
                await appState.queueWrite(capture)
                appState.recordWriting(capture, response: nil, syncState: .pending)
                outcome = WritingOutcome(capture: capture, delivery: .queued)
            } else {
                appState.recordWriting(capture, response: nil, syncState: .localOnly)
            }
            return
        }

        // Legacy non-canonical submit path kept alive until the contract cutover.
        // The locked core contract is the session-bundle `/api/anky/submit` path.
        do {
            // Fetch enclave public key dynamically (fire-and-forget cache for future calls)
            await Self.refreshEnclavePublicKeyIfNeeded()

            let sealedRequest = try AnkyProtocol.sealForWrite(
                content: capture.text,
                sessionId: capture.sessionId,
                duration: capture.duration,
                wordCount: capture.wordCount
            )

            let response = try await AnkyAPI.shared.submitSealedWrite(sealedRequest)

            if response.isAnky == true {
                // Build a MobileWriteResponse-compatible record for local bookkeeping
                let writeResponse = MobileWriteResponse(
                    ok: response.ok,
                    sessionId: response.sessionId ?? capture.sessionId,
                    outcome: "anky",
                    wordCount: capture.wordCount,
                    durationSeconds: capture.duration,
                    flowScore: capture.estimatedFlowScore,
                    persisted: true,
                    spawned: SpawnedArtifacts(
                        ankyId: response.ankyId,
                        feedback: nil,
                        meditation: nil,
                        breathwork: nil,
                        cuentacuentos: nil
                    ),
                    walletAddress: nil,
                    statusUrl: nil,
                    ankyResponse: nil,
                    nextPrompt: nil,
                    mood: nil,
                    error: nil
                )
                await appState.applyPersistedAnkySuccess(capture: capture, response: writeResponse)
                Self.autoMintCNFT(sessionId: capture.sessionId, appState: appState)
                Self.archiveToArweave(sessionId: capture.sessionId, text: capture.text)
                outcome = Self.remoteOutcome(capture: capture)
            } else {
                appState.recordWriting(capture, response: nil, syncState: .synced)
                outcome = WritingOutcome(capture: capture, delivery: .synced)
            }
        } catch {
            print("[SealedWrite] Primary sealed path failed: \(error.localizedDescription)")

            // Fallback: try the legacy plaintext path so the user still gets a reflection
            do {
                let response = try await AnkyAPI.shared.submitWriting(capture.request)

                if response.isAnky && response.persisted == true {
                    await appState.applyPersistedAnkySuccess(capture: capture, response: response)
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
            } catch let fallbackError as AnkyError {
                if fallbackError.isConnectivityIssue || fallbackError == .missingSession || fallbackError == .unauthorized {
                    if capture.qualifiesForAnky {
                        await appState.queueWrite(capture)
                        appState.recordWriting(capture, response: nil, syncState: .pending)
                        outcome = WritingOutcome(capture: capture, delivery: .queued)
                    } else {
                        appState.recordWriting(capture, response: nil, syncState: .localOnly)
                    }
                } else {
                    appState.recordWriting(capture, response: nil, syncState: .localOnly)
                    outcome = WritingOutcome(
                        capture: capture,
                        delivery: .failed(fallbackError.errorDescription ?? "saved locally")
                    )
                }
            } catch {
                appState.recordWriting(capture, response: nil, syncState: .localOnly)
                outcome = WritingOutcome(
                    capture: capture,
                    delivery: .failed(error.localizedDescription)
                )
            }
        }
    }

    /// Fetches the enclave public key from the server and caches it for encryption.
    /// Silent failure — falls back to hardcoded key in AnkyProtocol.
    private static func refreshEnclavePublicKeyIfNeeded() async {
        do {
            let key = try await AnkyAPI.shared.fetchEnclavePublicKey()
            AnkyProtocol.setEnclavePublicKey(key)
        } catch {
            print("[SealedWrite] Could not fetch enclave public key, using cached/hardcoded: \(error.localizedDescription)")
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

        // Build and persist the canonical .anky session artifact before any submit path uses it.
        ankySessionString = buildAnkySessionString()
        let sessionArtifact: AnkyStoredSessionArtifact? = ankySessionString.flatMap { string in
            guard let firstKeystrokeEpochMs else {
                print("[AnkyFile] Missing first keystroke timestamp for legacy session \(sessionID)")
                assertionFailure("Missing first keystroke timestamp for canonical .anky file")
                return nil
            }

            do {
                let artifact = try AnkySessionFileStore.sealPartialSession(
                    sessionString: string,
                    sessionId: sessionID,
                    firstKeystrokeEpochMs: firstKeystrokeEpochMs
                )
                if !AnkySessionFileStore.verify(filepath: artifact.fileURL.path) {
                    print("[AnkyFile] Verification failed immediately after write at \(artifact.fileURL.path)")
                    assertionFailure("Canonical .anky file verification failed")
                }
                return artifact
            } catch {
                print("[AnkyFile] Failed to persist canonical session file: \(error.localizedDescription)")
                assertionFailure("Failed to persist canonical .anky file")
                return nil
            }
        }

        let capture = LocalWritingCapture(
            sessionId: sessionID,
            prompt: prompt,
            text: text,
            duration: sessionElapsed,
            wordCount: wordCount,
            keystrokeDeltas: keystrokeDeltas,
            finishedAt: .now,
            estimatedFlowScore: Self.estimateFlowScore(deltasInMilliseconds: keystrokeDeltas, duration: sessionElapsed),
            ankySessionString: sessionArtifact?.sessionString ?? ankySessionString,
            ankyFilePath: sessionArtifact?.fileURL.path,
            sessionHash: sessionArtifact?.sessionHash
        )

        composerFocused = false
        phase = .complete
        outcome = nil
        completedCapture = capture
        pendingCapture = capture
        WritingSessionStore.clearDraft()
    }

    /// Builds the canonical .anky session string with the first keystroke epoch on line 1.
    private func buildAnkySessionString() -> String? {
        AnkySessionFileStore.buildSessionString(
            keystrokes: ankyKeystrokes,
            firstKeystrokeEpochMs: firstKeystrokeEpochMs
        )
    }

    func resumeWriting() {
        guard phase == .paused else { return }
        resumeFromPauseFromTyping(at: Date())
    }

    private func resumeFromPauseFromTyping(at now: Date) {
        phase = .writing
        composerFocused = true
        idleElapsed = 0
        lastInputAt = nil
        lastTick = now
    }

    /// Legacy satellite surface, not part of the locked canonical Anky loop.
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

    /// Legacy proof/archive helper, not the canonical proof model.
    static func relayAnkySession(sessionString: String, sessionHash: String) {
        Task {
            do {
                let encrypted = try AnkyProtocol.relayEncrypt(plaintext: sessionString)
                let writerPubkey = try SeedIdentityManager.shared.walletAddress()

                let request = RelayRequest(
                    encrypted: RelayEncryptedPayload(
                        ephemeralPublicKey: encrypted.ephemeralPublicKey.base64EncodedString(),
                        nonce: encrypted.nonce.base64EncodedString(),
                        tag: encrypted.tag.base64EncodedString(),
                        ciphertext: encrypted.ciphertext.base64EncodedString(),
                        sessionHash: sessionHash
                    ),
                    writerPubkey: writerPubkey
                )

                let response = try await AnkyAPI.shared.relaySession(request)
                print("[AnkyRelay] Relayed → hash: \(response.hash ?? sessionHash), arweave: \(response.arweaveTx ?? "pending"), solana: \(response.solanaTx ?? "pending")")
            } catch {
                print("[AnkyRelay] Relay failed: \(error.localizedDescription)")
            }
        }
    }

    /// Legacy non-canonical plaintext archive helper kept until archive cutover.
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
        // v2: newlines and tabs are banned, not converted — strip them
        text.filter { !$0.isNewline && $0 != "\t" }
    }

    private static func displayGlyph(for character: Character) -> String {
        character.isWhitespace ? "·" : String(character)
    }
}

// All view code has been moved to ContentView.swift
