//
//  AnkyChatView.swift
//  Anky
//
//  Chat-centric root view. The conversation with Anky IS the app.
//  Writing sessions launch as fullscreen cover — centered text,
//  last letter red, everything flows left and up from center.
//  8 seconds idle pauses the session and surfaces an explicit
//  send / keep-writing choice.
//

import AVFoundation
import Combine
import Speech
import SwiftUI
import UIKit

// MARK: - Haptics

struct AnkyHaptics {
    static func sessionComplete() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func ankyMessage() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
    }
    static func messageSent() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func copyConfirmed() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func keyTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
    }
    static func timerStarted() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    static func writingOpened() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func idleWarningEnding() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func thresholdReached() {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        let medium = UIImpactFeedbackGenerator(style: .medium)
        heavy.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            medium.impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            medium.impactOccurred()
        }
    }
}

// MARK: - Speech Session Manager

@MainActor
class SpeechSessionManager: ObservableObject {
    @Published var isListening = false
    @Published var audioLevel: Float = 0
    @Published var audioLevelHistory: [Float] = []

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    @Published var selectedLocale: Locale = Locale(identifier: "en-US")
    private var speechRecognizer: SFSpeechRecognizer?

    static let supportedLocales: [Locale] = {
        SFSpeechRecognizer.supportedLocales()
            .sorted { $0.identifier < $1.identifier }
            .map { $0 }
    }()

    private let maxHistoryCount = 60

    var onTranscription: ((String) -> Void)?

    func requestPermissions() async -> Bool {
        let speechAuth = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let audioAuth: Bool
        if #available(iOS 17, *) {
            audioAuth = await AVAudioApplication.requestRecordPermission()
        } else {
            audioAuth = await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        return speechAuth && audioAuth
    }

    func changeLocale(_ locale: Locale) {
        selectedLocale = locale
        if isListening {
            stopListening()
            startListening()
        }
    }

    func startListening() {
        speechRecognizer = SFSpeechRecognizer(locale: selectedLocale)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.onTranscription?(result.bestTranscription.formattedString)
                }
            }
            if error != nil || (result?.isFinal == true) {
                Task { @MainActor in
                    self.stopListening()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var rms: Float = 0
            for i in 0..<frameLength {
                rms += channelData[i] * channelData[i]
            }
            rms = sqrtf(rms / Float(max(frameLength, 1)))
            let level = max(0, min(1, rms * 8))
            Task { @MainActor [weak self] in
                self?.audioLevel = level
                self?.audioLevelHistory.append(level)
                if (self?.audioLevelHistory.count ?? 0) > (self?.maxHistoryCount ?? 60) {
                    self?.audioLevelHistory.removeFirst()
                }
            }
        }

        audioEngine.prepare()
        try? audioEngine.start()
        isListening = true
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        isListening = false
        audioLevel = 0
    }
}

// MARK: - Chat Models

enum MessageKind: Equatable {
    case anky(text: String)
    case user(text: String)
    case ankyImage(url: String)
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let kind: MessageKind
    let timestamp: Date
    let isCurrentSession: Bool
    let duration: TimeInterval?

    init(id: UUID, kind: MessageKind, timestamp: Date, isCurrentSession: Bool, duration: TimeInterval? = nil) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.isCurrentSession = isCurrentSession
        self.duration = duration
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ChatViewModel

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isAnkyTyping = false
    @Published var isConversationMode = false

    // Session state
    @Published var isInSession = false
    @Published var isVoiceSession = false
    @Published var isSessionPaused = false
    @Published var isSealEngaged = false
    @Published var isExternalPresentationActive = false
    @Published var sessionText = ""
    @Published var sessionElapsed: TimeInterval = 0
    @Published var idleElapsed: TimeInterval = 0
    @Published var isMilestoneCelebrating = false
    @Published var milestoneSequenceID = 0
    @Published var sealingReflection = ""
    @Published var sealingAnkyId: String?
    @Published var isSealingComplete = false
    @Published var isAwaitingSealingDecision = false

    /// After 8 seconds of continuous chat typing, the one composer expands into full Anky mode.
    static let ankyModeThreshold: TimeInterval = 8
    @Published var isAnkyModeActive = false

    var lastSessionText: String?
    var keystrokeDeltas: [Double] = []
    var pendingCapture: LocalWritingCapture?
    var activeNowSlug: String?

    // .anky session capture
    private var ankyKeystrokes: [AnkyKeystrokeRecord] = []
    private var ankyPreviousTextCount: Int = 0
    private var firstKeystrokeEpochMs: Int64?

    private let sessionGoal: TimeInterval = AnkyContract.Qualification.minimumDurationSeconds
    private let idleWarningStart: TimeInterval = 3
    private let idleLimit: TimeInterval = 8
    private(set) var sessionStartedAt: Date?
    private var lastInputAt: Date?
    private var lastTick = Date()
    private var sessionID = UUID().uuidString
    private var pendingReplyText: String?
    private var currentConversationDayKey = ChatStore.currentUTCKey()
    private var didTriggerMilestone = false
    private var didTriggerIdleWarningEndingHaptic = false
    private var isFinishingSession = false
    private var deliveredImageURLs = Set<String>()
    private var lastWritingThreadID: String?

    static let ankyverseColors: [Color] = [
        Color(hex: "ff0000"), Color(hex: "ff6600"), Color(hex: "ffcc00"),
        Color(hex: "33cc33"), Color(hex: "3399ff"), Color(hex: "6633cc"),
        Color(hex: "9933ff"), Color(hex: "ffffff"),
    ]

    var sessionProgress: Double {
        min(max(sessionElapsed / sessionGoal, 0), 1)
    }

    var hasReachedSessionGoal: Bool {
        sessionElapsed >= sessionGoal
    }

    var idleRemainingProgress: Double {
        guard isWritingSession, !isMilestoneCelebrating else { return 1 }
        guard idleElapsed > idleWarningStart else { return 1 }
        let warningSpan = max(idleLimit - idleWarningStart, 0.01)
        let drain = min(max((idleElapsed - idleWarningStart) / warningSpan, 0), 1)
        return max(1 - drain, 0)
    }

    var idleBarVisible: Bool {
        isWritingSession && isInSession && (isSessionPaused || idleElapsed >= idleWarningStart)
    }

    var qualifiesForAnky: Bool {
        LocalWritingCapture.qualifiesForAnky(text: sessionText, duration: sessionElapsed)
    }

    var wordCount: Int {
        LocalWritingCapture.wordCount(in: sessionText)
    }

    var canSealSubmission: Bool {
        !sessionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var pendingCaptureTaskToken: String {
        "\(pendingCapture?.sessionId ?? "none")-\(isAwaitingSealingDecision ? "hold" : "ready")"
    }

    var conversationMessages: [ChatMessage] {
        let currentSessionMessages = messages.filter(\.isCurrentSession)
        guard let writingIndex = currentSessionMessages.lastIndex(where: { message in
            guard case .user = message.kind else { return false }
            return message.duration != nil
        }) else {
            return []
        }

        return Array(currentSessionMessages.dropFirst(writingIndex))
    }

    var hasActiveWritingContext: Bool {
        isInSession
            || isConversationMode
            || isAnkyTyping
            || !sessionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || shouldShowReplyComposer
    }

    var shouldShowConversationSurface: Bool {
        guard !conversationMessages.isEmpty else { return false }
        return isConversationMode || isAnkyTyping || shouldShowReplyComposer || conversationMessages.count > 1
    }

    var elapsedLabel: String {
        let total = max(Int(sessionElapsed), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var countdownLabel: String {
        let remaining = sessionGoal - sessionElapsed
        if remaining > 0 {
            let total = Int(remaining)
            return String(format: "%d:%02d", total / 60, total % 60)
        } else {
            let past = Int(-remaining)
            return String(format: "+%d:%02d", past / 60, past % 60)
        }
    }

    var progressBarColor: Color {
        let step = min(Int(sessionProgress * 8), 7)
        return Self.ankyverseColors[step]
    }

    private let currentSessionTag = ChatStore.currentSessionTag

    init() {
        loadConversationForCurrentDay()
    }

    /// Opening inquiry — Anky asks first, based on the day's kingdom energy
    static func openingInquiry(for kingdom: Kingdom) -> String {
        switch kingdom {
        case .primordia:  return "what are you afraid to look at today?"
        case .emblazion:  return "what desire have you been suppressing?"
        case .chryseos:   return "where in your life are you giving your power away?"
        case .eleutheria: return "who do you need to forgive — including yourself?"
        case .voxlumis:   return "what truth have you been avoiding saying out loud?"
        case .insightia:  return "what pattern keeps repeating in your life?"
        case .claridium:  return "what would you do if you weren't performing for anyone?"
        case .poiesis:    return "what wants to be created through you right now?"
        }
    }

    /// Return inquiry — for users coming back
    static func returnInquiry(for kingdom: Kingdom) -> String {
        switch kingdom {
        case .primordia:  return "you came back.\nwhat's pulling at the roots today?"
        case .emblazion:  return "you came back.\nwhat's burning in you right now?"
        case .chryseos:   return "you came back.\nwhere are you holding tension?"
        case .eleutheria: return "you came back.\nwhat does your heart need to say?"
        case .voxlumis:   return "you came back.\nwhat are you ready to voice?"
        case .insightia:  return "you came back.\nwhat do you see that you didn't before?"
        case .claridium:  return "you came back.\nwhat's dissolving?"
        case .poiesis:    return "you came back.\nwhat's trying to emerge?"
        }
    }

    func appendMessage(_ msg: ChatMessage) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            messages.append(msg)
        }
    }

    private func persist(_ msg: ChatMessage, kind: PersistedMessageKind, duration: TimeInterval? = nil) {
        ChatStore.shared.append(PersistedMessage(
            id: msg.id.uuidString,
            kind: kind,
            timestamp: msg.timestamp,
            sessionTag: currentSessionTag,
            duration: duration
        ))
    }

    // MARK: - Session

    func beginSession(voice: Bool = false) {
        prepareNewSession(voice: voice)
    }

    /// Start tracking a session silently from the chat input.
    /// Called on first keystroke in the unified input field.
    func beginSilentSession() {
        guard !isInSession else { return }
        prepareNewSession(voice: false)
    }

    /// Discard the current session without sending anything.
    func discardSession() {
        let sid = sessionID
        resetSessionState()
        WritingSessionStore.clearLiveSession(sessionId: sid)
    }

    var isWritingSession: Bool {
        isAnkyModeActive || sessionElapsed >= Self.ankyModeThreshold
    }

    func handleKeyPress(_ character: String) {
        guard !isSessionPaused, !isMilestoneCelebrating else { return }

        let now = Date()
        sessionText += character

        if sessionStartedAt == nil {
            sessionStartedAt = now
            sessionElapsed = 0
        } else if let lastInput = lastInputAt {
            let delta = now.timeIntervalSince(lastInput) * 1000
            if delta.isFinite && delta > 0 {
                keystrokeDeltas.append(delta.rounded())
            }
        }

        lastInputAt = now
        lastTick = now
        idleElapsed = 0
        didTriggerIdleWarningEndingHaptic = false

        scheduleLiveSnapshot(updatedAt: now)
    }

    /// Lightweight keystroke tracking — text is already set by the caller.
    func recordKeystroke() {
        guard !isSessionPaused, !isMilestoneCelebrating else { return }

        let now = Date()

        // Capture new characters for .anky v2 format
        if sessionText.count > ankyPreviousTextCount {
            let startIdx = sessionText.index(sessionText.startIndex, offsetBy: ankyPreviousTextCount)
            for char in sessionText[startIdx...] {
                if ankyKeystrokes.isEmpty {
                    firstKeystrokeEpochMs = Int64(now.timeIntervalSince1970 * 1000)
                }
                let canonical = AnkySessionFileStore.canonicalPayload(for: char)
                ankyKeystrokes.append(AnkyKeystrokeRecord(payload: canonical, timestamp: now))
            }
        }
        ankyPreviousTextCount = sessionText.count

        if sessionStartedAt == nil {
            sessionStartedAt = now
            sessionElapsed = 0
        } else if let lastInput = lastInputAt {
            let delta = now.timeIntervalSince(lastInput) * 1000
            if delta.isFinite && delta > 0 {
                keystrokeDeltas.append(delta.rounded())
            }
        }

        lastInputAt = now
        lastTick = now
        idleElapsed = 0
        didTriggerIdleWarningEndingHaptic = false

        scheduleLiveSnapshot(updatedAt: now)
    }

    func handleVoiceTranscription(_ text: String) {
        guard !isSessionPaused, !isMilestoneCelebrating else { return }

        let now = Date()
        sessionText = text

        if sessionStartedAt == nil {
            sessionStartedAt = now
        }
        lastInputAt = now
        lastTick = now
        idleElapsed = 0
        didTriggerIdleWarningEndingHaptic = false
        scheduleLiveSnapshot(updatedAt: now)
    }

    func sessionTick(at now: Date) {
        guard isInSession else { return }

        if isExternalPresentationActive {
            lastTick = now
            idleElapsed = 0
            return
        }

        if isSessionPaused {
            lastTick = now
            return
        }

        if isMilestoneCelebrating {
            lastTick = now
            idleElapsed = 0
            return
        }

        guard sessionStartedAt != nil else { return }

        let delta = min(max(now.timeIntervalSince(lastTick), 0), 0.25)
        lastTick = now

        if isSealEngaged {
            sessionElapsed += delta
            idleElapsed = 0
            return
        }

        idleElapsed = lastInputAt.map { now.timeIntervalSince($0) } ?? 0

        if isWritingSession, idleElapsed >= idleLimit - 1, !didTriggerIdleWarningEndingHaptic {
            didTriggerIdleWarningEndingHaptic = true
            AnkyHaptics.idleWarningEnding()
        }

        if isWritingSession && idleElapsed >= idleLimit {
            idleElapsed = idleLimit
            if isVoiceSession, !sessionText.isEmpty {
                isSessionPaused = true
            } else if !sessionText.isEmpty, !isFinishingSession {
                sendToAnky()
            }
            return
        }

        sessionElapsed += delta

        if !isAnkyModeActive && sessionElapsed >= Self.ankyModeThreshold {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isAnkyModeActive = true
            }
        }

        if !didTriggerMilestone && sessionElapsed >= sessionGoal {
            sessionElapsed = sessionGoal
            idleElapsed = 0
            didTriggerMilestone = true
            isMilestoneCelebrating = true
            milestoneSequenceID += 1
        }
    }

    func resumeSession() {
        guard isInSession, isSessionPaused else { return }

        let now = Date()
        isSessionPaused = false
        idleElapsed = 0
        lastInputAt = now
        lastTick = now
        didTriggerIdleWarningEndingHaptic = false
    }

    /// Send current text as a chat message before the composer expands into a full writing session.
    /// If chat is locked (no anky written today), this is a no-op — writing continues toward anky mode.
    func sendAsChatMessage() {
        let text = sessionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard chatUnlocked else { return }

        let msg = ChatMessage(
            id: UUID(),
            kind: .user(text: text),
            timestamp: .now,
            isCurrentSession: true
        )

        // Reset session state
        let capturedText = text
        WritingSessionStore.clearLiveSession(sessionId: sessionID)
        resetSessionState()

        appendMessage(msg)
        persist(msg, kind: .user(text: capturedText))
        AnkyHaptics.messageSent()

        // Anky replies to the chat message
        isAnkyTyping = true
        Task {
            do {
                let response = try await AnkyAPI.shared.chatQuick(
                    writing: lastSessionText ?? "",
                    message: capturedText,
                    history: buildChatHistory()
                )
                let normalizedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
                deliverAnkyResponse(
                    normalizedResponse.isEmpty
                        ? "i'm here. say more."
                        : normalizedResponse
                )
            } catch {
                deliverAnkyResponse("i'm here. say more.")
            }
        }
    }

    func sendToAnky() {
        guard isInSession, !sessionText.isEmpty, !isFinishingSession else { return }
        isFinishingSession = true

        let duration = sessionElapsed
        let capturedSessionText = sessionText

        // Build and persist the canonical .anky protocol artifact before the capture leaves writing mode.
        let sessionString = buildAnkySessionString()
        let sessionArtifact: AnkyStoredSessionArtifact? = sessionString.flatMap { string in
            guard let firstKeystrokeEpochMs else {
                print("[AnkyFile] Missing first keystroke timestamp for session \(sessionID)")
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
            prompt: "",
            text: capturedSessionText,
            duration: duration,
            wordCount: wordCount,
            keystrokeDeltas: keystrokeDeltas,
            finishedAt: .now,
            estimatedFlowScore: estimateFlowScore(),
            nowSlug: activeNowSlug,
            ankySessionString: sessionArtifact?.sessionString ?? sessionString,
            ankyFilePath: sessionArtifact?.fileURL.path,
            sessionHash: sessionArtifact?.sessionHash
        )

        let msg = ChatMessage(
            id: UUID(),
            kind: .user(text: capturedSessionText),
            timestamp: .now,
            isCurrentSession: true,
            duration: duration
        )

        lastSessionText = capturedSessionText
        lastWritingThreadID = capture.sessionId
        WritingSessionStore.clearLiveSession(sessionId: sessionID)
        resetSessionState(preserveConversationMode: true)
        isConversationMode = true

        appendMessage(msg)
        persist(msg, kind: .user(text: capturedSessionText), duration: duration)
        AnkyHaptics.messageSent()

        resetSealingState()
        pendingCapture = capture
        isAwaitingSealingDecision = capture.qualifiesForAnky
        activeNowSlug = nil
        isAnkyTyping = true
    }

    func setSealInteraction(_ isActive: Bool) {
        guard isSealEngaged != isActive else { return }
        isSealEngaged = isActive
        let now = Date()
        lastTick = now
        lastInputAt = now
        idleElapsed = 0
    }

    func setExternalPresentationActive(_ isActive: Bool) {
        guard isExternalPresentationActive != isActive else { return }
        isExternalPresentationActive = isActive
        let now = Date()
        lastTick = now
        lastInputAt = now
        idleElapsed = 0
    }

    func buildChatHistory() -> [ChatHistoryItem] {
        var history = conversationalMessagesForLatestWriting().compactMap { message -> ChatHistoryItem? in
            switch message.kind {
            case .user(let text):
                guard message.duration == nil else { return nil }
                return ChatHistoryItem(role: "user", content: text)
            case .anky(let text):
                return ChatHistoryItem(role: "assistant", content: text)
            case .ankyImage:
                return nil
            }
        }

        if let pendingReplyText,
           isAnkyTyping,
           history.last == ChatHistoryItem(role: "user", content: pendingReplyText) {
            history.removeLast()
        }

        return history
    }

    func sendReply(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isAnkyTyping else { return }

        let reply = ChatMessage(
            id: UUID(),
            kind: .user(text: trimmed),
            timestamp: .now,
            isCurrentSession: true
        )

        appendMessage(reply)
        persist(reply, kind: .user(text: trimmed))
        persistThreadMessage(role: "user", text: trimmed)
        AnkyHaptics.messageSent()
        isAnkyTyping = true
        pendingReplyText = trimmed

        Task {
            do {
                let response = try await AnkyAPI.shared.chatQuick(
                    writing: lastSessionText ?? "",
                    message: trimmed,
                    history: buildChatHistory()
                )
                pendingReplyText = nil
                let normalizedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
                let ankyResponse = normalizedResponse.isEmpty
                    ? "i'm still here. something slipped on my side. say that again."
                    : normalizedResponse
                persistThreadMessage(role: "anky", text: ankyResponse)
                deliverAnkyResponse(ankyResponse)
            } catch {
                pendingReplyText = nil
                let fallback = "i'm still here. something slipped on my side. say that again."
                persistThreadMessage(role: "anky", text: fallback)
                deliverAnkyResponse(fallback)
            }
        }
    }

    /// Whether chat is unlocked (user has written an anky today)
    var chatUnlocked = false

    var shouldShowReplyComposer: Bool {
        guard chatUnlocked else { return false }
        guard !isAnkyTyping else { return false }
        return conversationalMessagesForLatestWriting().contains {
            if case .anky = $0.kind { return true }
            return false
        }
    }

    func deliverAnkyResponse(_ text: String) {
        deliverAnkyResponse(text, keepTyping: false)
    }

    func deliverWritingOutcome(reflection: String, imageURL: String?) async {
        let normalizedReflection = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedImageURL = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines)

        if !normalizedReflection.isEmpty {
            try? await Task.sleep(nanoseconds: 900_000_000)
            deliverAnkyResponse(normalizedReflection, keepTyping: normalizedImageURL?.isEmpty == false)
        }

        guard let normalizedImageURL, !normalizedImageURL.isEmpty else {
            isAnkyTyping = false
            return
        }

        try? await Task.sleep(nanoseconds: 1_050_000_000)
        deliverAnkyImage(normalizedImageURL)
    }

    func finishMilestoneCelebrationAndSend() {
        guard isMilestoneCelebrating else { return }
        isMilestoneCelebrating = false
        sendToAnky()
    }

    func resetSealingState() {
        sealingReflection = ""
        sealingAnkyId = nil
        isSealingComplete = false
    }

    func appendSealingReflectionChunk(_ chunk: String) {
        sealingReflection += chunk
    }

    func replaceSealingReflection(_ reflection: String) {
        sealingReflection = reflection
    }

    func markSealingAccepted(ankyId: String) {
        sealingAnkyId = ankyId
    }

    func markSealingDone(ankyId: String?) {
        if let ankyId {
            sealingAnkyId = ankyId
        }
        isSealingComplete = true
    }

    func releasePendingCaptureForBackgroundSubmission() {
        isAwaitingSealingDecision = false
    }

    func consumePendingCaptureAfterSealing() {
        pendingCapture = nil
        isAwaitingSealingDecision = false
    }

    func refreshConversationDayIfNeeded() {
        let currentDayKey = ChatStore.currentUTCKey()
        guard currentDayKey != currentConversationDayKey else { return }
        loadConversationForCurrentDay()
    }

    @discardableResult
    func restoreLiveSessionIfNeeded() -> Bool {
        guard !isInSession,
              let snapshot = WritingSessionStore.loadLiveSessionSnapshot() else {
            return false
        }

        let recoveredPartialSession: AnkyRecoveredSessionArtifact?
        if let partialAnkyFilePath = snapshot.partialAnkyFilePath,
           !partialAnkyFilePath.isEmpty {
            recoveredPartialSession = try? AnkySessionFileStore.loadRecoveredSession(filePath: partialAnkyFilePath)
        } else {
            recoveredPartialSession = nil
        }

        isInSession = true
        isVoiceSession = false
        isSessionPaused = false
        isSealEngaged = false
        isExternalPresentationActive = false
        isMilestoneCelebrating = false
        isAnkyModeActive = snapshot.sessionElapsed >= Self.ankyModeThreshold
        sessionText = recoveredPartialSession?.text ?? snapshot.text
        sessionElapsed = snapshot.sessionElapsed
        idleElapsed = 0
        keystrokeDeltas = snapshot.keystrokeDeltas
        sessionID = snapshot.sessionId
        ankyKeystrokes = recoveredPartialSession?.keystrokes ?? []
        ankyPreviousTextCount = recoveredPartialSession?.keystrokes.count ?? snapshot.text.count
        firstKeystrokeEpochMs = recoveredPartialSession?.firstKeystrokeEpochMs ?? snapshot.firstKeystrokeEpochMs
        sessionStartedAt = Date().addingTimeInterval(-snapshot.sessionElapsed)
        lastInputAt = .now
        lastTick = .now
        didTriggerMilestone = snapshot.sessionElapsed >= sessionGoal
        isFinishingSession = false
        ChatStore.shared.recordSessionStart(at: snapshot.updatedAt)
        return true
    }

    func leaveWritingSurface() {
        resetSessionState()
    }

    private func deliverAnkyResponse(_ text: String, keepTyping: Bool) {
        let ankyMsg = ChatMessage(id: UUID(), kind: .anky(text: text), timestamp: .now, isCurrentSession: true)
        appendMessage(ankyMsg)
        persist(ankyMsg, kind: .anky(text: text))
        AnkyHaptics.ankyMessage()
        isAnkyTyping = keepTyping
    }

    private func deliverAnkyImage(_ url: String) {
        guard deliveredImageURLs.insert(url).inserted else {
            isAnkyTyping = false
            return
        }

        let imageMessage = ChatMessage(
            id: UUID(),
            kind: .ankyImage(url: url),
            timestamp: .now,
            isCurrentSession: true
        )
        appendMessage(imageMessage)
        persist(imageMessage, kind: .ankyImage(url: url))
        isAnkyTyping = false
    }

    private func persistThreadMessage(role: String, text: String) {
        guard let threadID = lastWritingThreadID else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        AnkyThreadChatStore.shared.append(
            ankyId: threadID,
            message: AnkyThreadMessage(
                id: UUID().uuidString,
                role: role,
                text: trimmed,
                timestamp: .now
            )
        )
    }

    private func prepareNewSession(voice: Bool) {
        isConversationMode = false
        isInSession = true
        isVoiceSession = voice
        isSessionPaused = false
        isSealEngaged = false
        isExternalPresentationActive = false
        isAnkyModeActive = false
        isMilestoneCelebrating = false
        sessionText = ""
        sessionElapsed = 0
        idleElapsed = 0
        pendingReplyText = nil
        keystrokeDeltas = []
        ankyKeystrokes = []
        ankyPreviousTextCount = 0
        firstKeystrokeEpochMs = nil
        didTriggerMilestone = false
        didTriggerIdleWarningEndingHaptic = false
        isFinishingSession = false
        isAwaitingSealingDecision = false
        sessionID = UUID().uuidString
        sessionStartedAt = nil
        lastInputAt = nil
        lastTick = Date()
        resetSealingState()
        ChatStore.shared.recordSessionStart()
    }

    private func resetSessionState(preserveConversationMode: Bool = false) {
        if !preserveConversationMode {
            isConversationMode = false
        }
        isInSession = false
        isVoiceSession = false
        isSessionPaused = false
        isSealEngaged = false
        isExternalPresentationActive = false
        isAnkyModeActive = false
        isMilestoneCelebrating = false
        sessionText = ""
        sessionElapsed = 0
        idleElapsed = 0
        pendingReplyText = nil
        keystrokeDeltas = []
        ankyKeystrokes = []
        ankyPreviousTextCount = 0
        firstKeystrokeEpochMs = nil
        didTriggerMilestone = false
        didTriggerIdleWarningEndingHaptic = false
        isFinishingSession = false
        sessionStartedAt = nil
        lastInputAt = nil
        lastTick = Date()
    }

    private func scheduleLiveSnapshot(updatedAt: Date) {
        guard !sessionText.isEmpty else { return }
        WritingSessionStore.scheduleLiveSave(
            LiveWritingSessionSnapshot(
                sessionId: sessionID,
                text: sessionText,
                sessionElapsed: sessionElapsed,
                keystrokeDeltas: keystrokeDeltas,
                updatedAt: updatedAt,
                firstKeystrokeEpochMs: firstKeystrokeEpochMs,
                partialAnkyFilePath: nil
            ),
            partialSessionString: buildAnkySessionString()
        )
    }

    /// Builds the canonical .anky session string with the first keystroke epoch on line 1.
    private func buildAnkySessionString() -> String? {
        AnkySessionFileStore.buildSessionString(
            keystrokes: ankyKeystrokes,
            firstKeystrokeEpochMs: firstKeystrokeEpochMs
        )
    }

    private func estimateFlowScore() -> Double {
        guard !keystrokeDeltas.isEmpty else { return 0.42 }
        let deltas = keystrokeDeltas.map { max($0 / 1000, 0.02) }
        let mean = deltas.reduce(0, +) / Double(deltas.count)
        let variance = deltas.reduce(0) { $0 + pow($1 - mean, 2) } / Double(deltas.count)
        let coefficient = sqrt(variance) / max(mean, 0.001)
        let stability = max(0, 1 - min(coefficient, 1))
        let continuity = max(0, 1 - min(deltas.filter { $0 > 2.2 }.reduce(0, +) / max(sessionElapsed, 1), 1))
        let density = min(Double(deltas.count) / 700, 1)
        let score = 0.45 * stability + 0.30 * continuity + 0.25 * density
        return min(max((score * 100).rounded() / 100, 0), 1)
    }

    private func conversationalMessagesForLatestWriting() -> [ChatMessage] {
        let currentSessionMessages = messages.filter { $0.isCurrentSession }
        guard let writingIndex = currentSessionMessages.lastIndex(where: { message in
            guard case .user = message.kind else { return false }
            return message.duration != nil
        }) else {
            return []
        }

        let afterWriting = Array(currentSessionMessages.dropFirst(writingIndex + 1))
        guard let reflectionIndex = afterWriting.firstIndex(where: { message in
            if case .anky = message.kind { return true }
            return false
        }) else {
            return []
        }

        return Array(afterWriting.dropFirst(reflectionIndex))
    }

    private func loadConversationForCurrentDay() {
        currentConversationDayKey = ChatStore.currentUTCKey()
        let persistedMessages = ChatStore.shared.messages(forDayKey: currentConversationDayKey)
        messages = persistedMessages.map { chatMessage(from: $0) }

        guard persistedMessages.isEmpty else { return }

        let hasHistory = ChatStore.shared.hasAnyHistory()
        let dayKingdom = Kingdom.ankyverseDay()

        if !hasHistory {
            // First ever launch: "hey. i'm anky."
            let greeting = ChatMessage(
                id: UUID(),
                kind: .anky(text: "hey. i'm anky."),
                timestamp: .now,
                isCurrentSession: true
            )
            let promptText = Self.openingInquiry(for: dayKingdom)
            let followUp = ChatMessage(
                id: UUID(),
                kind: .anky(text: "_\(promptText)_"),
                timestamp: .now,
                isCurrentSession: true
            )
            messages = [greeting, followUp]
            persist(greeting, kind: .anky(text: "hey. i'm anky."))
            persist(followUp, kind: .anky(text: "_\(promptText)_"))
        } else {
            // Returning user
            let promptText = Self.returnInquiry(for: dayKingdom)
            let prompt = ChatMessage(
                id: UUID(),
                kind: .anky(text: promptText),
                timestamp: .now,
                isCurrentSession: true
            )
            messages = [prompt]
            persist(prompt, kind: .anky(text: promptText))
        }
    }

    private func chatMessage(from persisted: PersistedMessage) -> ChatMessage {
        let isCurrent = persisted.sessionTag == currentSessionTag
        let kind: MessageKind
        var msgDuration = persisted.duration

        switch persisted.kind {
        case .anky(let text):
            kind = .anky(text: text)
        case .user(let text):
            kind = .user(text: text)
        case .ankyImage(let url):
            kind = .ankyImage(url: url)
        case .writingSession(let preview, _, _, let duration):
            kind = .user(text: preview)
            if msgDuration == nil {
                msgDuration = duration
            }
        }

        return ChatMessage(
            id: UUID(uuidString: persisted.id) ?? UUID(),
            kind: kind,
            timestamp: persisted.timestamp,
            isCurrentSession: isCurrent,
            duration: msgDuration
        )
    }
}

// MARK: - AnkyChatView (Root)

struct AnkyChatView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var speechManager = SpeechSessionManager()
    @StateObject private var keyboard = KeyboardObserver()
    @State private var showWritingMode = false
    @State private var showSealingView = false
    @State private var hasResolvedInitialPresentation = false
    @State private var showProfile = false
    @State private var showMeditationTimer = false
    @State private var showNowRoom = false
    @State private var chatText = ""
    @State private var penGlowPhase: Double = 0
    @FocusState private var isChatFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ── Surface 2: Chat (always present beneath writing) ──
            VStack(spacing: 0) {
                chatTopBar

                MessageListView(
                    messages: viewModel.messages,
                    isTyping: viewModel.isAnkyTyping,
                    onCopyWriting: handleWritingCopy,
                    bottomInset: messageListBottomInset
                )

                chatBottomBar
            }

            // ── Surface 1: Writing Mode (slides down to reveal chat) ──
            if showWritingMode {
                AnkyModeView(
                    viewModel: viewModel,
                    speechManager: speechManager,
                    onExitToMainApp: exitWritingSurface
                )
                    .environmentObject(appState)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
                    .zIndex(1)
            }

            if showSealingView, let capture = viewModel.pendingCapture {
                SealingView(
                    viewModel: viewModel,
                    capture: capture,
                    kingdom: Kingdom.ankyverseDay(),
                    onComplete: {
                        viewModel.consumePendingCaptureAfterSealing()
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showSealingView = false
                            showWritingMode = false
                        }
                    },
                    onSkip: {
                        viewModel.releasePendingCaptureForBackgroundSubmission()
                        withAnimation(.easeInOut(duration: 0.4)) {
                            showSealingView = false
                            showWritingMode = false
                        }
                    }
                )
                .environmentObject(appState)
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }

        }
        .onAppear {
            resolveInitialPresentationIfNeeded()
            viewModel.chatUnlocked = true
            syncExternalPresentationState()
            viewModel.refreshConversationDayIfNeeded()
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                penGlowPhase = 1
            }
        }
        .fullScreenCover(isPresented: $showMeditationTimer) {
            MeditationTimerView()
        }
        .fullScreenCover(item: $appState.qrSealChallenge) { challenge in
            QRSealAuthView(challenge: challenge)
                .environmentObject(appState)
        }
        .fullScreenCover(item: $appState.sharedAnkyLink) { sharedLink in
            SharedGeneratedAnkyView(ankyID: sharedLink.id)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showProfile) {
            AnkyProfileView { session in
                // "continue this conversation" callback
                // TODO: load per-anky conversation via GET /api/anky/{ankyId}
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $showNowRoom, onDismiss: {
            appState.pendingNowSlug = nil
        }) {
            NowRoomView(
                slug: appState.pendingNowSlug,
                onStartWriting: { activeSlug in
                    showNowRoom = false
                    appState.pendingNowSlug = nil
                    viewModel.activeNowSlug = activeSlug
                    viewModel.beginSession()
                    openWritingMode()
                }
            )
            .environmentObject(appState)
        }
        .onChange(of: appState.pendingNowSlug) { _, slug in
            guard slug != nil else { return }
            hideWritingMode()
            showNowRoom = true
        }
        .onChange(of: showNowRoom) { _, _ in
            syncExternalPresentationState()
        }
        .task(id: viewModel.pendingCaptureTaskToken) {
            guard let capture = viewModel.pendingCapture else { return }
            guard !viewModel.isAwaitingSealingDecision else { return }
            viewModel.pendingCapture = nil
            await submitPendingCaptureInBackground(capture)
        }
        .onChange(of: viewModel.isInSession) { _, inSession in
            if !inSession {
                if speechManager.isListening {
                    speechManager.stopListening()
                }
                if let capture = viewModel.pendingCapture, capture.qualifiesForAnky {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showSealingView = true
                    }
                } else {
                    hideWritingMode()
                }
            }
            syncExternalPresentationState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            viewModel.chatUnlocked = true
            viewModel.refreshConversationDayIfNeeded()
        }
        .onChange(of: appState.localArchiveRecords) { _, _ in
            viewModel.chatUnlocked = true
        }
        .onChange(of: appState.qrSealChallenge) { _, _ in
            if appState.qrSealChallenge != nil {
                hideWritingMode()
            }
            syncExternalPresentationState()
        }
        .onChange(of: appState.sharedAnkyLink) { _, _ in
            if appState.sharedAnkyLink != nil {
                hideWritingMode()
            }
            syncExternalPresentationState()
        }
        .onChange(of: appState.deepLinkPrompt) { _, prompt in
            guard let prompt, !prompt.isEmpty, !viewModel.isInSession else { return }
            appState.prompt = prompt
            appState.deepLinkPrompt = nil
            openWritingMode()
        }
        .task {
            if let pendingId = DailyPromptNotificationManager.pendingSessionId {
                DailyPromptNotificationManager.clearPendingSession()
                if let record = await appState.reconcileCanonicalArchiveRecord(
                    sessionId: pendingId,
                    pollUntilSettled: false
                ),
                   let reflection = record.sessionBundle.reflection?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !reflection.isEmpty {
                    viewModel.deliverAnkyResponse(reflection)
                }
            }
        }
    }

    // MARK: - Chat Top Bar

    private var chatTopBar: some View {
        HStack(spacing: 14) {
            Button {
                showProfile = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(
            Color.black.opacity(0.96)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)
                }
        )
    }

    // MARK: - Chat Bottom Bar

    private var chatBottomBar: some View {
        HStack(spacing: 12) {
            // Hourglass — open the standalone 8-minute timer
            Button {
                isChatFocused = false
                showMeditationTimer = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(hex: "1c1c1e"))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    Image(systemName: "hourglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .buttonStyle(.plain)

            // Text input
            HStack(spacing: 8) {
                TextField("write a message to anky", text: $chatText, axis: .vertical)
                    .font(.ankyBody(16))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1...4)
                    .focused($isChatFocused)
                    .submitLabel(.send)
                    .onSubmit { sendChatMessage() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(hex: "1c1c1e"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            // Pen when empty, send when composing
            Button(action: handlePrimaryAction) {
                Image(systemName: trimmedChatText.isEmpty ? "pencil.line" : "arrow.up")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(trimmedChatText.isEmpty ? Color.ankyGold : Color.black.opacity(0.82))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(trimmedChatText.isEmpty ? Color(hex: "1c1c1e") : Color(hex: "f0b35a"))
                            .overlay(
                                Circle().stroke(
                                    trimmedChatText.isEmpty ? Color.ankyGold.opacity(0.22) : Color.clear,
                                    lineWidth: 1
                                )
                            )
                    )
                    .shadow(
                        color: Color.ankyGold.opacity(trimmedChatText.isEmpty ? 0.16 + 0.14 * penGlowPhase : 0),
                        radius: trimmedChatText.isEmpty ? 10 + 8 * penGlowPhase : 0,
                        y: 0
                    )
                    .scaleEffect(trimmedChatText.isEmpty ? 1 + 0.015 * penGlowPhase : 1)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color.black.opacity(0.96)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)
                }
        )
    }

    // MARK: - Helpers

    private var trimmedChatText: String {
        chatText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var messageListBottomInset: CGFloat {
        keyboard.height > 0 ? 140 : 104
    }

    private var shouldAutoPresentWriting: Bool {
        appState.pendingNowSlug == nil
            && appState.qrSealChallenge == nil
            && appState.sharedAnkyLink == nil
    }

    private func resolveInitialPresentationIfNeeded() {
        guard !hasResolvedInitialPresentation else { return }
        hasResolvedInitialPresentation = true

        if viewModel.restoreLiveSessionIfNeeded() {
            showWritingMode = true
            return
        }

        showWritingMode = shouldAutoPresentWriting

        if appState.pendingNowSlug != nil {
            showNowRoom = true
        }
    }

    private func openWritingMode() {
        isChatFocused = false
        guard !showWritingMode else { return }
        AnkyHaptics.writingOpened()
        withAnimation(.easeInOut(duration: 0.4)) {
            showWritingMode = true
        }
    }

    private func hideWritingMode() {
        withAnimation(.easeInOut(duration: 0.4)) {
            showWritingMode = false
        }
    }

    private func exitWritingSurface() {
        let trimmedSessionText = viewModel.sessionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSessionText.isEmpty else {
            viewModel.discardSession()
            hideWritingMode()
            return
        }

        viewModel.sendToAnky()
    }

    private func handlePrimaryAction() {
        if trimmedChatText.isEmpty {
            openWritingMode()
        } else {
            sendChatMessage()
        }
    }

    private func sendChatMessage() {
        let text = trimmedChatText
        guard !text.isEmpty else { return }

        chatText = ""

        if viewModel.shouldShowReplyComposer {
            viewModel.sendReply(text)
            return
        }

        let msg = ChatMessage(
            id: UUID(),
            kind: .user(text: text),
            timestamp: .now,
            isCurrentSession: true
        )

        viewModel.appendMessage(msg)
        ChatStore.shared.append(PersistedMessage(
            id: msg.id.uuidString,
            kind: .user(text: text),
            timestamp: msg.timestamp,
            sessionTag: ChatStore.currentSessionTag,
            duration: nil
        ))
        AnkyHaptics.messageSent()

        viewModel.isAnkyTyping = true
        Task {
            do {
                let response = try await AnkyAPI.shared.chatQuick(
                    writing: viewModel.lastSessionText ?? "",
                    message: text,
                    history: viewModel.buildChatHistory()
                )
                let normalizedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
                viewModel.deliverAnkyResponse(
                    normalizedResponse.isEmpty
                        ? "i'm here. say more."
                        : normalizedResponse
                )
            } catch {
                viewModel.deliverAnkyResponse("i'm here. say more.")
            }
        }
    }

    private func syncExternalPresentationState() {
        viewModel.setExternalPresentationActive(
            appState.qrSealChallenge != nil
                || appState.sharedAnkyLink != nil
                || showNowRoom
        )
    }

    private func handleWritingCopy(_ text: String) {
        UIPasteboard.general.string = text
        AnkyHaptics.copyConfirmed()
    }

    @MainActor
    private func submitPendingCaptureInBackground(_ capture: LocalWritingCapture) async {
        guard capture.qualifiesForAnky else {
            appState.recordWriting(capture, response: nil, syncState: .localOnly)
            await viewModel.deliverWritingOutcome(
                reflection: "i heard you. the words are safe here. come back when the full anky wants to arrive.",
                imageURL: nil
            )
            return
        }

        appState.recordWriting(capture, response: nil, syncState: .pending)

        var acceptedAnkyId: String?
        var titleText: String?
        var fullReflection = ""
        var streamedImageURL: String?
        var didPersistStoredSubmission = false
        var didDeliverReflectionToChat = false
        var didDeliverImageToChat = false

        func normalized(_ text: String?) -> String? {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }

        func persistArtifacts() {
            appState.storeGeneratedArtifacts(
                for: capture.sessionId,
                reflection: normalized(fullReflection),
                ankyTitle: normalized(titleText),
                ankyImagePath: normalized(streamedImageURL)
            )

            if let reflection = normalized(fullReflection) {
                AnkyNameStore.updateFromReflection(reflection)
            }
        }

        func absorbArchiveRecord(
            _ record: LocalArchiveRecord,
            markComplete: Bool
        ) async {
            if let title = normalized(record.sessionBundle.title3Words) {
                titleText = title
            }
            if let reflection = normalized(record.sessionBundle.reflection) {
                fullReflection = reflection
                viewModel.replaceSealingReflection(reflection)
            }
            if let imageLocator = normalized(record.sessionBundle.image?.canonicalLocator) {
                streamedImageURL = imageLocator
            }

            persistArtifacts()
            await deliverStreamedOutcomeIfPossible(markComplete: markComplete)
        }

        func deliverStreamedOutcomeIfPossible(markComplete: Bool) async {
            let reflection = normalized(fullReflection)
            let imageURL = normalized(streamedImageURL)

            if !didDeliverReflectionToChat, let reflection, let imageURL {
                didDeliverReflectionToChat = true
                didDeliverImageToChat = true
                await viewModel.deliverWritingOutcome(reflection: reflection, imageURL: imageURL)
                return
            }

            if !didDeliverReflectionToChat, let reflection {
                didDeliverReflectionToChat = true
                await viewModel.deliverWritingOutcome(reflection: reflection, imageURL: nil)
            }

            if didDeliverReflectionToChat,
               !didDeliverImageToChat,
               let imageURL,
               (markComplete || reflection != nil) {
                didDeliverImageToChat = true
                viewModel.isAnkyTyping = true
                await viewModel.deliverWritingOutcome(reflection: "", imageURL: imageURL)
            }
        }

        func persistStoredSubmissionIfNeeded(ankyId: String) async {
            guard !didPersistStoredSubmission else { return }
            didPersistStoredSubmission = true

            await appState.storeCanonicalAcceptedSubmission(
                for: capture.sessionId,
                backendAnkyId: ankyId
            )
            await DailyPromptNotificationManager.scheduleWithPrompt(appState.prompt)
            DailyPromptNotificationManager.clearPendingSession()
            WritingFlowModel.autoMintCNFT(sessionId: capture.sessionId, appState: appState)
            WritingFlowModel.archiveToArweave(sessionId: capture.sessionId, text: capture.text)
        }

        func reconcileCanonicalArchive(
            pollUntilSettled: Bool,
            markComplete: Bool
        ) async {
            guard let updated = await appState.reconcileCanonicalArchiveRecord(
                sessionId: capture.sessionId,
                pollUntilSettled: pollUntilSettled
            ) else {
                return
            }

            await absorbArchiveRecord(updated, markComplete: markComplete)
        }

        func finalizeSuccessfulSubmission(with ankyId: String) async {
            acceptedAnkyId = ankyId
            await persistStoredSubmissionIfNeeded(ankyId: ankyId)
            await reconcileCanonicalArchive(pollUntilSettled: true, markComplete: true)
        }

        do {
            for try await event in AnkyAPI.shared.streamAnkySubmit(capture: capture, kingdom: Kingdom.ankyverseDay()) {
                switch event {
                case .accepted(let ankyId):
                    acceptedAnkyId = ankyId
                    viewModel.markSealingAccepted(ankyId: ankyId)
                    await persistStoredSubmissionIfNeeded(ankyId: ankyId)

                case .title(let title):
                    titleText = title
                    persistArtifacts()

                case .reflectionChunk(let chunk):
                    fullReflection += chunk
                    viewModel.appendSealingReflectionChunk(chunk)

                case .reflectionComplete(let reflection):
                    fullReflection = reflection
                    viewModel.replaceSealingReflection(reflection)
                    persistArtifacts()
                    await deliverStreamedOutcomeIfPossible(markComplete: false)

                case .imageURL(let imageURL):
                    streamedImageURL = imageURL
                    persistArtifacts()
                    await deliverStreamedOutcomeIfPossible(markComplete: false)

                case .solana:
                    break

                case .done(let ankyId):
                    viewModel.markSealingDone(ankyId: ankyId)
                    await finalizeSuccessfulSubmission(with: ankyId)
                    return

                case .error(let stage, _):
                    if (stage == "solana" || stage == "image"),
                       let ankyId = acceptedAnkyId ?? viewModel.sealingAnkyId {
                        viewModel.markSealingDone(ankyId: ankyId)
                        await finalizeSuccessfulSubmission(with: ankyId)
                        return
                    }

                    throw AnkySubmitStreamFailure(stage: stage, retryable: false)
                }
            }

            if let ankyId = acceptedAnkyId ?? viewModel.sealingAnkyId {
                await finalizeSuccessfulSubmission(with: ankyId)
                return
            }

            throw AnkySubmitStreamFailure(stage: "persist", retryable: false)
        } catch is CancellationError {
            return
        } catch let streamFailure as AnkySubmitStreamFailure {
            if streamFailure.stage != "claude",
               streamFailure.stage != "persist",
               let ankyId = acceptedAnkyId ?? viewModel.sealingAnkyId {
                await finalizeSuccessfulSubmission(with: ankyId)
                return
            }

            await reconcileCanonicalArchive(pollUntilSettled: false, markComplete: true)
            await deliverStreamedOutcomeIfPossible(markComplete: true)
        } catch {
            if let ankyId = acceptedAnkyId ?? viewModel.sealingAnkyId {
                await finalizeSuccessfulSubmission(with: ankyId)
                return
            }

            await reconcileCanonicalArchive(pollUntilSettled: false, markComplete: true)
            await deliverStreamedOutcomeIfPossible(markComplete: true)
        }
    }

}

private struct SharedGeneratedAnkyView: View {
    @EnvironmentObject private var appState: AppState

    let ankyID: String

    @State private var anky: GeneratedAnky?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }

                if let anky {
                    if let remoteImageURL = anky.remoteImageURL {
                        AsyncImage(url: remoteImageURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Rectangle()
                                    .fill(Color.white.opacity(0.05))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(anky.displayTitle)
                            .font(.anky(24))
                            .foregroundStyle(Color.white.opacity(0.94))

                        HStack(spacing: 8) {
                            Text(anky.origin ?? "shared")
                            Text("•")
                            Text(anky.createdAtLabel)
                        }
                        .font(.ankyBody(12))
                        .foregroundStyle(Color.white.opacity(0.42))
                    }

                    if let prompt = anky.displayPrompt {
                        sharedDetailBlock(title: "Prompt", body: prompt)
                    }

                    if let reflection = anky.reflection?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !reflection.isEmpty {
                        sharedDetailBlock(title: "Reflection", body: reflection)
                    }
                } else if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color.ankyGold)
                        Text("loading shared anky...")
                            .font(.ankyBody(14))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 80)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("This anky could not be opened.")
                            .font(.anky(20))
                            .foregroundStyle(Color.white.opacity(0.9))

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.ankyBody(14))
                                .foregroundStyle(Color.white.opacity(0.52))
                        }
                    }
                    .padding(.top, 80)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Color.ankyVoid.ignoresSafeArea())
        .task {
            await loadSharedAnky()
        }
    }

    private func sharedDetailBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.ankyBody(12))
                .foregroundStyle(Color.ankyGold)

            Text(body)
                .font(.ankyBody(16))
                .lineSpacing(6)
                .foregroundStyle(Color.white.opacity(0.88))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func loadSharedAnky() async {
        isLoading = true
        defer { isLoading = false }

        do {
            anky = try await AnkyAPI.shared.getGeneratedAnky(id: ankyID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func close() {
        appState.dismissSharedAnky()
    }
}

// MARK: - Drawer Overlay

struct DrawerOverlay: View {
    @Binding var isPresented: Bool
    let appState: AppState
    @State private var selectedAnky: CachedWritingEntry?
    @State private var drawerOffset: CGFloat = -300

    private var displayName: String {
        AnkyNameStore.name ?? appState.user?.displayName ?? appState.user?.username ?? "anky"
    }

    private var ankySessions: [CachedWritingEntry] {
        appState.canonicalArchiveAnkys
            .sorted { $0.createdAt > $1.createdAt }
            .map(\.legacyCachedWritingEntry)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Dim background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    closeDrawer()
                }

            // Drawer panel
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // User header
                    HStack(spacing: 12) {
                        HeaderUserAvatarView(user: appState.user, accent: Kingdom.ankyverseDay().color)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.92))

                            Text("\(appState.user?.totalAnkys ?? ankySessions.count) ankys")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.42))
                        }

                        Spacer()

                        Button {
                            closeDrawer()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 20)

                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)

                    // Anky sessions list
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(ankySessions) { entry in
                                Button {
                                    selectedAnky = entry
                                } label: {
                                    drawerAnkyRow(entry)
                                }
                                .buttonStyle(.plain)
                            }

                            if ankySessions.isEmpty {
                                Text("your ankys will appear here")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.white.opacity(0.3))
                                    .padding(.horizontal, 20)
                                    .padding(.top, 24)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    Spacer(minLength: 0)
                }
                .frame(width: 300)
                .background(Color(hex: "0a0a0f").ignoresSafeArea())
                .offset(x: drawerOffset)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
                drawerOffset = 0
            }
        }
        .sheet(item: $selectedAnky) { anky in
            AnkyThreadView(anky: anky)
                .environmentObject(appState)
                .sheetStyleBackground(Color.ankyVoid)
        }
    }

    private func closeDrawer() {
        withAnimation(.easeIn(duration: 0.2)) {
            drawerOffset = -300
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }

    private func drawerAnkyRow(_ entry: CachedWritingEntry) -> some View {
        HStack(spacing: 12) {
            if let url = entry.remoteImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Circle().fill(Color.white.opacity(0.08))
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 36, height: 36)
                    .overlay(
                        AnkyMark(size: 14)
                            .opacity(0.4)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.ankyTitle ?? "anky")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)

                Text(entry.createdAtLabel)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.35))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Anky Mode (Full-Screen Writing)

struct AnkyModeView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var speechManager: SpeechSessionManager
    let onExitToMainApp: () -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWritingFocused = false
    @State private var showMilestoneOverlay = false
    @State private var milestoneTask: Task<Void, Never>?
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private let sessionGoal: TimeInterval = AnkyContract.Qualification.minimumDurationSeconds

    private var hasStartedWriting: Bool {
        viewModel.sessionStartedAt != nil || !viewModel.sessionText.isEmpty
    }

    private var writingPlaceholder: String {
        let trimmed = appState.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "write." : trimmed
    }

    private var topIdleBarProgress: Double {
        hasStartedWriting ? viewModel.idleRemainingProgress : 1
    }

    private var shouldShowTopIdleBar: Bool {
        !hasStartedWriting || viewModel.idleBarVisible
    }

    private var cosmicIntensity: Double {
        if viewModel.isMilestoneCelebrating { return 1 }
        guard viewModel.isAnkyModeActive else { return 0 }
        let elapsed = viewModel.sessionElapsed - ChatViewModel.ankyModeThreshold
        return min(max(elapsed / 8.0, 0), 1)
    }

    private var currentCaretColor: UIColor {
        guard hasStartedWriting else { return UIColor(Color.ankyGold) }
        let idle = viewModel.idleElapsed
        guard idle > 3 else { return UIColor(Color.ankyGold) }
        let t = min((idle - 3) / 5, 1)
        let start = UIColor(Color.ankyGold)
        let end = UIColor(Color(hex: "FF3B30"))

        var startRed: CGFloat = 0
        var startGreen: CGFloat = 0
        var startBlue: CGFloat = 0
        var startAlpha: CGFloat = 0
        var endRed: CGFloat = 0
        var endGreen: CGFloat = 0
        var endBlue: CGFloat = 0
        var endAlpha: CGFloat = 0

        start.getRed(&startRed, green: &startGreen, blue: &startBlue, alpha: &startAlpha)
        end.getRed(&endRed, green: &endGreen, blue: &endBlue, alpha: &endAlpha)

        return UIColor(
            red: startRed + (endRed - startRed) * t,
            green: startGreen + (endGreen - startGreen) * t,
            blue: startBlue + (endBlue - startBlue) * t,
            alpha: 1
        )
    }

    private var timerText: String {
        let elapsed = viewModel.sessionElapsed
        let remaining = sessionGoal - elapsed
        if remaining > 0 {
            let total = max(Int(remaining), 0)
            return String(format: "%d:%02d", total / 60, total % 60)
        }

        let overtime = max(Int(-remaining), 0)
        return "+\(String(format: "%d:%02d", overtime / 60, overtime % 60))"
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color(hex: "0a0a0a").ignoresSafeArea()

                if viewModel.isAnkyModeActive || viewModel.isMilestoneCelebrating {
                    CosmicBackgroundView(
                        intensity: cosmicIntensity,
                        sessionProgress: viewModel.sessionProgress,
                        keystrokeCount: viewModel.sessionText.count
                    )
                    .ignoresSafeArea()
                    .transition(.opacity)
                }

                VStack(spacing: 0) {
                    IdleProgressBar(
                        progress: topIdleBarProgress,
                        isPaused: viewModel.isSessionPaused,
                        isVisible: shouldShowTopIdleBar
                    )

                    AnkyComposerTextView(
                        text: writingBinding,
                        isFocused: focusBinding,
                        isVisuallyHidden: false,
                        forwardOnly: true,
                        placeholder: writingPlaceholder,
                        font: UIFont(name: "Righteous-Regular", size: 22) ?? .systemFont(ofSize: 22, weight: .regular),
                        textInsets: UIEdgeInsets(top: 22, left: 0, bottom: writingBottomInset, right: 0),
                        isScrollable: true,
                        caretColor: currentCaretColor,
                        placeholderOpacity: 0.34,
                        onUserInput: { _ in }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 20)

                    ChakraProgressBar(progress: hasStartedWriting ? viewModel.sessionProgress : 0)
                        .frame(height: 3)

                    if shouldShowFooterRow {
                        HStack(alignment: .center) {
                            if shouldShowTimer {
                                Text(hasStartedWriting ? timerText : "8:00")
                                    .font(.anky(18))
                                    .foregroundStyle(
                                        hasStartedWriting
                                            ? Color.white.opacity(0.72)
                                            : Color.white.opacity(0.36)
                                    )
                            }

                            Spacer()

                            if shouldShowCloseButton {
                                Button(action: handleCloseButton) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(Color.white.opacity(0.92))
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Circle()
                                                .fill(Color(hex: "FF3B30").opacity(0.88))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                    }
                }

                if viewModel.isSessionPaused {
                    SessionPauseChoiceView(
                        elapsedLabel: viewModel.elapsedLabel,
                        hasReachedMilestone: viewModel.hasReachedSessionGoal,
                        isWritingSession: viewModel.isWritingSession,
                        canSeal: viewModel.canSealSubmission,
                        onSeal: { viewModel.sendToAnky() },
                        onKeepWriting: { viewModel.resumeSession() },
                        onDiscard: {
                            viewModel.discardSession()
                            onExitToMainApp()
                        },
                        onSealInteractionChanged: { isActive in
                            viewModel.setSealInteraction(isActive)
                        }
                    )
                }

                if showMilestoneOverlay {
                    MilestoneCelebrationOverlay(reduceMotion: reduceMotion)
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            isWritingFocused = true
        }
        .onReceive(tick) { now in
            viewModel.sessionTick(at: now)
        }
        .onChange(of: viewModel.milestoneSequenceID) { _, _ in
            milestoneTask?.cancel()
            showMilestoneOverlay = true
            AnkyHaptics.thresholdReached()
            milestoneTask = Task {
                let duration: UInt64 = reduceMotion ? 1_000_000_000 : 2_000_000_000
                try? await Task.sleep(nanoseconds: duration)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showMilestoneOverlay = false
                    }
                    viewModel.finishMilestoneCelebrationAndSend()
                }
            }
        }
        .onDisappear {
            milestoneTask?.cancel()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.isAnkyModeActive)
    }

    private func handleCloseButton() {
        dismissWritingKeyboard()

        let trimmed = viewModel.sessionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            DispatchQueue.main.async {
                onExitToMainApp()
            }
            return
        }

        guard viewModel.isInSession else {
            DispatchQueue.main.async {
                onExitToMainApp()
            }
            return
        }

        DispatchQueue.main.async {
            viewModel.sendToAnky()
        }
    }

    private func dismissWritingKeyboard() {
        isWritingFocused = false
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        keyWindow?.endEditing(true)
    }

    private var writingBinding: Binding<String> {
        Binding(
            get: { viewModel.sessionText },
            set: { newValue in
                if !viewModel.isInSession && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    viewModel.beginSilentSession()
                }
                let grew = newValue.count > viewModel.sessionText.count
                viewModel.sessionText = newValue
                if grew {
                    viewModel.recordKeystroke()
                }
            }
        )
    }

    private var focusBinding: Binding<Bool> {
        Binding(
            get: { isWritingFocused },
            set: { isWritingFocused = $0 }
        )
    }

    private var shouldShowTimer: Bool {
        !hasStartedWriting || viewModel.sessionElapsed < 20
    }

    private var shouldShowCloseButton: Bool {
        !hasStartedWriting
    }

    private var shouldShowFooterRow: Bool {
        shouldShowTimer || shouldShowCloseButton
    }

    private var writingBottomInset: CGFloat {
        shouldShowFooterRow ? 112 : 86
    }
}

// MARK: - Unified Input View
// One UITextView-backed composer that grows from the chat dock into the full writing screen.

struct UnifiedInputView: View {
    @ObservedObject var viewModel: ChatViewModel
    let isExpanded: Bool
    let keyboardHeight: CGFloat
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    var isFocused: FocusState<Bool>.Binding
    var onStartVoice: () -> Void
    var onBellTap: () -> Void

    private var sessionBinding: Binding<String> {
        Binding(
            get: { viewModel.sessionText },
            set: { newValue in
                // Start tracking silently on first character
                if !viewModel.isInSession && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    viewModel.beginSilentSession()
                }

                let grew = newValue.count > viewModel.sessionText.count
                // Set text once to avoid per-character re-renders
                viewModel.sessionText = newValue

                if grew {
                    // Record a single keystroke event for the batch
                    viewModel.recordKeystroke()
                }
            }
        )
    }

    private var hasText: Bool {
        !viewModel.sessionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var focusBinding: Binding<Bool> {
        Binding(
            get: { isFocused.wrappedValue },
            set: { isFocused.wrappedValue = $0 }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let keyboardOverlap = max(keyboardHeight - safeAreaBottom, 0)
            let collapsedBottomInset = keyboardOverlap > 0
                ? keyboardOverlap + 10
                : max(safeAreaBottom, 10)
            let expandedBottomInset = keyboardOverlap > 0
                ? keyboardOverlap
                : safeAreaBottom
            let expandedHeight = max(proxy.size.height - expandedBottomInset, 0)

            ZStack(alignment: .bottom) {
                if isExpanded {
                    Color.black.opacity(0.96)
                        .ignoresSafeArea()
                }

                if isExpanded {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: safeAreaTop)

                        IdleProgressBar(
                            progress: viewModel.idleRemainingProgress,
                            isPaused: viewModel.isSessionPaused,
                            isVisible: true
                        )

                        composerSurface
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: .infinity, alignment: .topLeading)

                        ChakraProgressBar(progress: viewModel.sessionProgress)
                            .frame(height: 4)

                        Text(viewModel.countdownLabel)
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .padding(.top, 10)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(
                        width: proxy.size.width,
                        height: expandedHeight,
                        alignment: .top
                    )
                    .padding(.bottom, expandedBottomInset)
                } else {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        composerSurface
                            .padding(.horizontal, 14)
                            .padding(.bottom, collapsedBottomInset)
                    }
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .bottom
                    )
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isExpanded)
        }
    }

    private var composerSurface: some View {
        Group {
            if isExpanded {
                expandedComposerSurface
            } else {
                collapsedComposerSurface
            }
        }
        .frame(maxHeight: isExpanded ? .infinity : nil, alignment: .topLeading)
    }

    private var expandedComposerSurface: some View {
        ZStack(alignment: .topLeading) {
            if !hasText && !viewModel.isInSession {
                Text("Message")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .padding(.leading, 20)
                    .padding(.top, 18)
            }

            AnkyComposerTextView(
                text: sessionBinding,
                isFocused: focusBinding,
                isVisuallyHidden: false,
                forwardOnly: true,
                font: UIFont(name: "Palatino-Roman", size: 22) ?? .systemFont(ofSize: 22, weight: .regular),
                textInsets: UIEdgeInsets(top: 16, left: 0, bottom: 20, right: 0),
                isScrollable: true,
                onUserInput: { _ in }
            )
            .frame(maxWidth: .infinity)
            .frame(
                minHeight: 160,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .padding(.horizontal, 20)
        }
    }

    private var collapsedComposerSurface: some View {
        HStack(alignment: .center, spacing: 8) {
            // Bell — meditation timer
            Button(action: onBellTap) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            TextField("Message", text: sessionBinding, axis: .vertical)
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1...5)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit {
                    if hasText && viewModel.chatUnlocked { viewModel.sendAsChatMessage() }
                }

            // Mic when empty, send when text (send only if chat unlocked)
            if hasText && viewModel.chatUnlocked {
                Button(action: {
                    viewModel.sendAsChatMessage()
                }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.82))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(hex: "f0b35a")))
                }
                .buttonStyle(.plain)
            } else if hasText && !viewModel.chatUnlocked {
                // Pen icon — writing in progress, chat locked until anky is written
                Image(systemName: "pencil.line")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .frame(width: 36, height: 36)
            } else {
                Button(action: onStartVoice) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isInSession)
                .opacity(viewModel.isInSession ? 0.38 : 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "1c1c1e"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Cosmic Background (letter flickers + starfield)

struct CosmicBackgroundView: View {
    let intensity: Double
    let sessionProgress: Double
    let keystrokeCount: Int

    /// Current ankyverse color
    private var currentColor: Color {
        let step = min(Int(sessionProgress * 8), 7)
        return ChatViewModel.ankyverseColors[step]
    }

    var body: some View {
        ZStack {
            // Deep void
            Color.black.opacity(intensity)

            // Radial glow that pulses with writing
            RadialGradient(
                colors: [
                    currentColor.opacity(0.15 * intensity),
                    currentColor.opacity(0.05 * intensity),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .scaleEffect(1.0 + sin(Double(keystrokeCount) * 0.1) * 0.08)
            .animation(.easeOut(duration: 0.15), value: keystrokeCount)

            // Scattered flicker particles
            ForEach(0..<12, id: \.self) { i in
                CosmicFlickerParticle(
                    index: i,
                    keystrokeCount: keystrokeCount,
                    color: currentColor,
                    intensity: intensity
                )
            }

            // Edge vignette
            RadialGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.6 * intensity)
                ],
                center: .center,
                startRadius: 150,
                endRadius: 500
            )
        }
    }
}

struct CosmicFlickerParticle: View {
    let index: Int
    let keystrokeCount: Int
    let color: Color
    let intensity: Double

    private var position: CGPoint {
        let seed = Double(index) * 2.39996
        let x = 0.15 + 0.7 * abs(sin(seed * 3.1))
        let y = 0.1 + 0.8 * abs(cos(seed * 2.7))
        return CGPoint(x: x, y: y)
    }

    private var isActive: Bool {
        (keystrokeCount + index) % 5 == 0
    }

    var body: some View {
        GeometryReader { geo in
            Circle()
                .fill(color.opacity(isActive ? 0.6 * intensity : 0.08 * intensity))
                .frame(width: isActive ? 6 : 3, height: isActive ? 6 : 3)
                .blur(radius: isActive ? 4 : 1)
                .position(
                    x: geo.size.width * position.x,
                    y: geo.size.height * position.y
                )
                .animation(.easeOut(duration: 0.2), value: keystrokeCount)
        }
    }
}


// MARK: - Full Screen Writing View (legacy — kept for onboarding reference only)
// The writing experience now lives inline in AnkyChatView with organic cosmic transition.

// MARK: - Portal Canvas (shared between main app and onboarding)

struct PortalCanvasView: View {
    let text: String
    let sessionProgress: Double
    let wordCount: Int

    /// Current ankyverse color based on session progress
    private var currentColor: Color {
        let step = min(Int(sessionProgress * 8), 7)
        return ChatViewModel.ankyverseColors[step]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Portal glow on the left edge
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                currentColor.opacity(0.12),
                                currentColor.opacity(0.03),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 60)
                    .frame(maxHeight: .infinity)
                    .position(x: 30, y: geo.size.height / 2)
                    .blur(radius: 4)

                // Portal line
                Rectangle()
                    .fill(currentColor.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .position(x: 8, y: geo.size.height / 2)

                // Text flowing right-to-left, last character large and colored
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .center, spacing: 0) {
                            // Padding so text starts from center
                            Spacer()
                                .frame(width: geo.size.width * 0.5)

                            // All characters as flowing text
                            if !text.isEmpty {
                                let chars = Array(text)
                                let count = chars.count
                                ForEach(Array(chars.enumerated()), id: \.offset) { index, char in
                                    let isLast = index == count - 1
                                    let distanceFromEnd = count - 1 - index
                                    let fade = min(Double(distanceFromEnd) / 20.0, 1.0)

                                    Text(String(char))
                                        .font(.custom("Georgia", size: isLast ? 72 : max(28 - fade * 14, 14)))
                                        .foregroundStyle(
                                            isLast
                                            ? currentColor
                                            : Color.white.opacity(max(0.7 - fade * 0.6, 0.1))
                                        )
                                        .shadow(color: isLast ? currentColor.opacity(0.3) : .clear, radius: isLast ? 12 : 0)
                                        .id(index)
                                }
                            }

                            // Padding after last char
                            Spacer()
                                .frame(width: geo.size.width * 0.4)
                                .id("end")
                        }
                    }
                    .onChange(of: text.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo("end", anchor: .trailing)
                        }
                    }
                    .onAppear {
                        proxy.scrollTo("end", anchor: .trailing)
                    }
                }

                // Word count — subtle bottom right
                if !text.isEmpty {
                    Text("\(wordCount)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.12))
                        .position(x: geo.size.width - 24, y: geo.size.height - 12)
                }
            }
        }
    }
}

// MARK: - Voice Session View

struct VoiceSessionView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var speechManager: SpeechSessionManager
    @Environment(\.dismiss) var dismiss

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                IdleProgressBar(progress: viewModel.idleRemainingProgress, isPaused: viewModel.isSessionPaused, isVisible: viewModel.idleBarVisible)
                    .padding(.top, 8)

                GeometryReader { geo in
                    let halfW = geo.size.width / 2
                    let halfH = geo.size.height / 2

                    VStack(alignment: .trailing, spacing: 0) {
                        Spacer(minLength: 0)
                        Text(viewModel.sessionText.isEmpty ? "" : viewModel.sessionText)
                            .font(.custom("Georgia", size: 20))
                            .lineSpacing(8)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.trailing)
                            .frame(width: halfW - 24, alignment: .trailing)
                    }
                    .frame(width: halfW, height: halfH, alignment: .bottomTrailing)
                    .clipped()
                    .position(x: halfW / 2, y: halfH / 2)
                }

                if viewModel.isSessionPaused {
                    SessionPauseChoiceView(
                        elapsedLabel: viewModel.elapsedLabel,
                        hasReachedMilestone: viewModel.hasReachedSessionGoal,
                        isWritingSession: viewModel.isWritingSession,
                        canSeal: viewModel.canSealSubmission,
                        onSeal: {
                            viewModel.sendToAnky()
                        },
                        onKeepWriting: {
                            viewModel.resumeSession()
                        },
                        onDiscard: { viewModel.discardSession() },
                        onSealInteractionChanged: { isActive in
                            viewModel.setSealInteraction(isActive)
                        }
                    )
                } else {
                    VoiceWaveformView(
                        audioLevelHistory: speechManager.audioLevelHistory,
                        currentLevel: speechManager.audioLevel,
                        isListening: speechManager.isListening,
                        speechManager: speechManager
                    )
                    .frame(height: 200)

                    SealView(label: "seal to send", isEnabled: viewModel.canSealSubmission) {
                        viewModel.sendToAnky()
                    } onInteractionChanged: { isActive in
                        viewModel.setSealInteraction(isActive)
                        if isActive {
                            if speechManager.isListening {
                                speechManager.stopListening()
                            }
                        } else if viewModel.isInSession && !viewModel.isSessionPaused && !speechManager.isListening {
                            speechManager.startListening()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34)
                }
            }
        }
        .onReceive(tick) { now in
            viewModel.sessionTick(at: now)
        }
        .onChange(of: viewModel.isInSession) { _, inSession in
            if !inSession { dismiss() }
        }
        .onChange(of: viewModel.isSessionPaused) { _, isPaused in
            if isPaused {
                if speechManager.isListening {
                    speechManager.stopListening()
                }
            } else if viewModel.isInSession && !speechManager.isListening {
                speechManager.startListening()
            }
        }
    }
}

// MARK: - Idle Progress Bar (8-second countdown)

struct IdleProgressBar: View {
    let progress: Double
    let isPaused: Bool
    var isVisible: Bool = true

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                Rectangle()
                    .fill(barColor)
                    .frame(width: geo.size.width * progress)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .frame(height: 4)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeIn(duration: 0.3), value: isVisible)
    }

    private var barColor: Color {
        if isPaused {
            return Color(hex: "8a2e1d")
        }
        if progress > 0.66 {
            return Color(hex: "f0b35a")
        }
        if progress > 0.33 {
            return Color(hex: "ff8800")
        }
        return Color(hex: "ff5a36")
    }
}

struct MilestoneCelebrationOverlay: View {
    let reduceMotion: Bool
    @State private var animate = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(hex: "f4c15d").opacity(animate ? 0.32 : 0.06),
                    Color(hex: "f4c15d").opacity(animate ? 0.08 : 0.02),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: animate ? 380 : 120
            )
            .ignoresSafeArea()

            if !reduceMotion {
                GeometryReader { geo in
                    ForEach(0..<18, id: \.self) { index in
                        Circle()
                            .fill(Color(hex: "f4c15d").opacity(0.9))
                            .frame(width: 8, height: 8)
                            .scaleEffect(animate ? 0.2 : 1.0)
                            .position(
                                x: geo.size.width / 2 + cos(Double(index) / 18 * .pi * 2) * (animate ? 180 : 18),
                                y: geo.size.height / 2 + sin(Double(index) / 18 * .pi * 2) * (animate ? 180 : 18)
                            )
                            .opacity(animate ? 0 : 1)
                    }
                }
                .ignoresSafeArea()
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(animate ? 0.12 : 0.02),
                            Color(hex: "f4c15d").opacity(animate ? 0.08 : 0.02),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .ignoresSafeArea()
                .opacity(animate ? 1 : 0)

            Text("Anky is ready.")
                .font(.custom("Georgia", size: 28))
                .foregroundStyle(Color.white.opacity(0.96))
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.38))
                        .overlay(
                            Capsule()
                                .stroke(Color(hex: "f4c15d").opacity(0.42), lineWidth: 1)
                        )
                )
                .opacity(animate ? 1 : 0)
                .scaleEffect(reduceMotion ? 1 : (animate ? 1 : 0.92))
        }
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.3 : 1.4)) {
                animate = true
            }
        }
    }
}

// MARK: - Session Pause Choice

struct SessionPauseChoiceView: View {
    let elapsedLabel: String
    let hasReachedMilestone: Bool
    let isWritingSession: Bool
    let canSeal: Bool
    let onSeal: () -> Void
    let onKeepWriting: () -> Void
    var onDiscard: (() -> Void)? = nil
    var onSendAsMessage: (() -> Void)? = nil
    var onSealInteractionChanged: ((Bool) -> Void)? = nil

    private let milestoneColor = Color(hex: "f0b35a")

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Text(elapsedLabel)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(hasReachedMilestone ? milestoneColor : Color.white.opacity(0.45))
                    .shadow(color: hasReachedMilestone ? milestoneColor.opacity(0.18) : .clear, radius: 10)

                Text("the thread is still here.")
                    .font(.custom("Georgia", size: 19))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .padding(.top, 14)

            if isWritingSession {
                // 33s+ — this is a real writing session, seal it
                SealView(label: "seal to send", isEnabled: canSeal) {
                    onSeal()
                } onInteractionChanged: { isActive in
                    onSealInteractionChanged?(isActive)
                }
                .padding(.horizontal, 28)
            } else if let onSendAsMessage {
                // Under 33s — just send as a chat message
                Button(action: onSendAsMessage) {
                    Text("send as message")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color(hex: "3478F6"))
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
            }

            Button(action: onKeepWriting) {
                Text("keep writing")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(milestoneColor)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)

            if let onDiscard {
                Button(action: onDiscard) {
                    Text("discard")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "0a0a12"))
    }
}

// WritingKeyboardView removed — system keyboard is used instead

// MARK: - Message List

struct MessageListView: View {
    let messages: [ChatMessage]
    let isTyping: Bool
    var onCopyWriting: (String) -> Void
    var bottomInset: CGFloat = 108

    private let bottomAnchorID = "message-list-bottom-anchor"
    private var lastMessageID: UUID? { messages.last?.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(messages) { message in
                        MessageRow(message: message, onCopyWriting: onCopyWriting)
                            .opacity(message.isCurrentSession ? 1 : 0.35)
                            .id(message.id)
                    }

                    if isTyping {
                        TypingIndicatorView()
                            .id("typing")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, bottomInset)
            }
            .defaultScrollAnchor(.bottom)
            .onAppear {
                syncBottom(proxy: proxy)
            }
            .onChange(of: lastMessageID) { _, _ in
                syncBottom(proxy: proxy)
            }
            .onChange(of: isTyping) { _, _ in
                syncBottom(proxy: proxy)
            }
            .onChange(of: bottomInset) { _, _ in
                syncBottom(proxy: proxy)
            }
        }
    }

    private func syncBottom(proxy: ScrollViewProxy) {
        scrollToBottom(proxy: proxy)
        DispatchQueue.main.async {
            scrollToBottom(proxy: proxy)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = false) {
        let target: AnyHashable = bottomAnchorID
        if animated {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: ChatMessage
    var onCopyWriting: (String) -> Void

    var body: some View {
        switch message.kind {
        case .anky(let text):
            AnkyMessageView(text: text, timestamp: message.timestamp)
        case .user(let text):
            UserMessageView(
                text: text,
                timestamp: message.timestamp,
                duration: message.duration,
                onCopy: message.duration != nil ? { onCopyWriting(text) } : nil
            )
        case .ankyImage(let url):
            AnkyImageMessageView(urlString: url, timestamp: message.timestamp)
        }
    }
}

// MARK: - Anky Message (left-aligned, dark charcoal bubble)

struct AnkyMessageView: View {
    let text: String
    let timestamp: Date

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.ankyBody(16))
                    .lineSpacing(5)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(hex: "1c1c1e"))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text(timestamp.chatTimeLabel)
                    .font(.ankyBody(11))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .padding(.leading, 12)
            }
            .frame(maxWidth: 300, alignment: .leading)

            Spacer(minLength: 48)
        }
    }
}

// MARK: - User Message (right-aligned, warm rose bubble)

struct UserMessageView: View {
    let text: String
    let timestamp: Date
    var duration: TimeInterval?
    var onCopy: (() -> Void)? = nil
    @State private var didCopy = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 48)

            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .font(.ankyBody(16))
                    .lineSpacing(5)
                    .foregroundStyle(Color(hex: "1a1a1a"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(hex: "f5c6c2"))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if let onCopy {
                    Button {
                        onCopy()
                        withAnimation(.easeOut(duration: 0.18)) {
                            didCopy = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation(.easeIn(duration: 0.16)) {
                                didCopy = false
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                            Text(didCopy ? "copied" : "copy")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(didCopy ? Color.black.opacity(0.82) : Color(hex: "f5c6c2"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(didCopy ? Color(hex: "f5c6c2") : Color(hex: "1c1c1e"))
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 4) {
                    if let duration {
                        Text(durationLabel(duration))
                            .font(.ankyBody(11))
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                    Text(timestamp.chatTimeLabel)
                        .font(.ankyBody(11))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
                .padding(.trailing, 12)
            }
            .frame(maxWidth: 300, alignment: .trailing)
        }
    }

    private func durationLabel(_ d: TimeInterval) -> String {
        let mins = Int(d) / 60
        let secs = Int(d) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }
}

struct AnkyImageMessageView: View {
    let urlString: String
    let timestamp: Date

    private var imageURL: URL? {
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return URL(string: urlString)
        }
        let normalizedPath = urlString.hasPrefix("/") ? urlString : "/\(urlString)"
        return URL(string: "https://anky.app\(normalizedPath)")
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))

                    if let imageURL {
                        AsyncImage(url: imageURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Rectangle()
                                    .fill(Color.white.opacity(0.08))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 244)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text(timestamp.chatTimeLabel)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .padding(.leading, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 32)
        }
    }
}

// MARK: - Chat Header

struct ChatHeaderView: View {
    let user: UserProfile?
    var onGenerateTap: () -> Void
    var onUserTap: () -> Void

    private var dayKingdom: Kingdom { Kingdom.ankyverseDay() }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onGenerateTap) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color(hex: "171719"))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                Circle()
                    .fill(Color(hex: "171719"))
                Circle()
                    .stroke(dayKingdom.color.opacity(0.32), lineWidth: 1.2)
                AnkyMark(size: 18)
                    .opacity(0.82)
            }
            .frame(width: 36, height: 36)

            Button(action: onUserTap) {
                HeaderUserAvatarView(user: user, accent: dayKingdom.color)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            Color.black.opacity(0.96)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)
                }
        )
    }
}

struct HeaderUserAvatarView: View {
    let user: UserProfile?
    let accent: Color

    private var profileURL: URL? {
        guard let rawURL = user?.profileImageUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty else {
            return nil
        }
        if rawURL.hasPrefix("http://") || rawURL.hasPrefix("https://") {
            return URL(string: rawURL)
        }
        let normalizedPath = rawURL.hasPrefix("/") ? rawURL : "/\(rawURL)"
        return URL(string: "https://anky.app\(normalizedPath)")
    }

    private var fallbackInitial: String {
        let source = user?.displayName ?? user?.username ?? "u"
        return String(source.prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "171719"))

            if let profileURL {
                AsyncImage(url: profileURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackAvatar
                    }
                }
                .clipShape(Circle())
            } else {
                fallbackAvatar
            }
        }
        .frame(width: 40, height: 40)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var fallbackAvatar: some View {
        Text(fallbackInitial)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent)
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.4 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "1c1c1e"))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { phase = 0 }
    }
}

// MARK: - Skeleton Bar

struct SkeletonBar: View {
    @State private var opacity: Double = 0.4

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(opacity))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    opacity = 0.1
                }
            }
    }
}

// ChatInputBarView removed — replaced by UnifiedInputView

// MARK: - Voice Waveform

struct VoiceWaveformView: View {
    let audioLevelHistory: [Float]
    let currentLevel: Float
    let isListening: Bool
    @ObservedObject var speechManager: SpeechSessionManager

    private let barCount = 40

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let level = barLevel(at: i)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: level))
                        .frame(width: 4, height: max(4, CGFloat(level) * 80))
                        .animation(.easeOut(duration: 0.08), value: level)
                }
            }
            .frame(height: 80)

            HStack(spacing: 12) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(isListening ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isListening)

                Text("listening...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.4))

                Spacer()

                Menu {
                    ForEach(SpeechSessionManager.supportedLocales, id: \.identifier) { locale in
                        Button {
                            speechManager.changeLocale(locale)
                        } label: {
                            HStack {
                                Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                                if locale.identifier == speechManager.selectedLocale.identifier {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 11))
                        Text(speechManager.selectedLocale.language.languageCode?.identifier.uppercased() ?? "EN")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private func barLevel(at index: Int) -> Float {
        guard !audioLevelHistory.isEmpty else { return 0.05 }
        let historyCount = audioLevelHistory.count
        let mapped = Int(Float(index) / Float(barCount) * Float(historyCount))
        let safeIndex = min(max(mapped, 0), historyCount - 1)
        return audioLevelHistory[safeIndex]
    }

    private func barColor(for level: Float) -> Color {
        let step = min(Int(level * 8), 7)
        return ChatViewModel.ankyverseColors[max(step, 0)].opacity(Double(max(level, 0.15)))
    }
}

// MARK: - Stories Sheet

struct StoriesSheetView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var stories: [Cuentacuentos] = []
    @State private var isLoading = true
    @State private var activeStory: Cuentacuentos?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 18)

            Text("stories from your writing")
                .font(.system(size: 10, weight: .medium))
                .kerning(1.5)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            if isLoading {
                VStack {
                    Spacer(minLength: 40)
                    ProgressView()
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
            } else if stories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("no stories yet")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    Text("write for 8 minutes. a story is born from what comes out.")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 20)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(stories) { story in
                            StorySheetRow(story: story)
                                .onTapGesture { activeStory = story }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .presentationDetents([.fraction(0.65)])
        .presentationDragIndicator(.hidden)
        .task { await loadStories() }
        .fullScreenCover(item: $activeStory) { story in
            StoryPlayerView(story: story) { completed in
                guard completed else { return }
                try? await AnkyAPI.shared.completeCuentacuentos(id: story.id)
                await loadStories()
            }
        }
    }

    private func loadStories() async {
        defer { isLoading = false }
        do {
            stories = try await AnkyAPI.shared.getCuentacuentosHistory(childId: nil)
            prefetchImages(from: stories)
        } catch {
            stories = []
        }
    }

    private func prefetchImages(from stories: [Cuentacuentos]) {
        let urls = stories.flatMap { story in
            story.guidancePhases.compactMap { $0.imageUrl.flatMap { URL(string: $0) } }
        }
        for url in urls {
            Task.detached(priority: .background) {
                _ = try? await URLSession.shared.data(for: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad))
            }
        }
    }

    private func guidanceSession(from story: Cuentacuentos) -> GuidanceSession {
        GuidanceSession(
            id: story.id,
            title: story.title,
            description: story.content,
            durationSeconds: story.guidancePhases.reduce(0) { $0 + $1.durationSeconds },
            phases: story.guidancePhases
        )
    }
}

struct StorySheetRow: View {
    let story: Cuentacuentos

    private var allImageUrls: [URL] {
        story.guidancePhases.compactMap { $0.imageUrl.flatMap { URL(string: $0) } }
    }

    private var coverImageUrl: URL? { allImageUrls.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let url = coverImageUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .transition(.opacity.animation(.easeIn(duration: 0.2)))
                    case .failure:
                        imagePlaceholder
                    case .empty:
                        ZStack {
                            Color.white.opacity(0.04)
                            SkeletonBar().padding(20)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: 140)
                .clipped()
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
            } else {
                imagePlaceholder
                    .frame(height: 100)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(story.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer()

                    if UserSettings.shared.isStoryCompleted(story.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green.opacity(0.8))
                    } else if UserSettings.shared.resumePosition(for: story.id) != nil {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }

                HStack(spacing: 6) {
                    if allImageUrls.count > 1 {
                        HStack(spacing: 3) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 9))
                            Text("\(allImageUrls.count)")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.secondary)
                    }
                    Text("8 min")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var imagePlaceholder: some View {
        LinearGradient(
            colors: [Color.orange.opacity(0.15), Color.orange.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Text("✦").font(.custom("Georgia", size: 28)).foregroundStyle(.orange.opacity(0.4))
        )
    }
}

// MARK: - Profile Sheet

struct ProfileSheetView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var dayKingdom: Kingdom { Kingdom.ankyverseDay() }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header with close button
                    HStack {
                        Spacer()
                        Text("Profile")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Spacer()
                    }
                    .overlay(alignment: .trailing) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 20)

                    // Profile card
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(dayKingdom.color.opacity(0.4), lineWidth: 3)
                                .frame(width: 82, height: 82)

                            Circle()
                                .fill(Color(hex: "1c1c1e"))
                                .frame(width: 76, height: 76)

                            if let user = appState.user, let name = user.displayName ?? user.username {
                                Text(String(name.prefix(1)).uppercased())
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(dayKingdom.color)
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundStyle(dayKingdom.color)
                            }
                        }

                        if let user = appState.user {
                            Text(user.displayName ?? user.username ?? "writer")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.white)
                        } else {
                            Text("writer")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }

                        Text(dayKingdom.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(dayKingdom.color)
                    }

                    // Stats card
                    VStack(spacing: 0) {
                        if let user = appState.user {
                            statRow("Sessions", "\(user.totalWritings)")
                            Divider().overlay(Color.white.opacity(0.08))
                            statRow("Ankys", "\(user.totalAnkys)")
                            Divider().overlay(Color.white.opacity(0.08))
                            statRow("Local", "\(appState.localArchiveRecords.count)")
                        } else {
                            statRow("Sessions", "\(appState.localArchiveRecords.count)")
                        }
                    }
                    .background(Color(hex: "1c1c1e"))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Kingdom info card
                    VStack(spacing: 0) {
                        statRow("Kingdom", dayKingdom.name)
                        Divider().overlay(Color.white.opacity(0.08))
                        statRow("Chakra", dayKingdom.chakra)
                        Divider().overlay(Color.white.opacity(0.08))
                        statRow("Time", Kingdom.ankyverseTimeLabel())
                    }
                    .background(Color(hex: "1c1c1e"))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(0.9))
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Date Extension

extension Date {
    var chatShortTime: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f.string(from: self)
    }

    var chatTimeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: self)
    }
}
