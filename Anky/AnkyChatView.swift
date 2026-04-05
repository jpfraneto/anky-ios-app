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
    static func keyTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
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

    var lastSessionText: String?
    var keystrokeDeltas: [Double] = []
    var pendingCapture: LocalWritingCapture?

    private let sessionGoal: TimeInterval = 480
    private let idleLimit: TimeInterval = 8
    private var sessionStartedAt: Date?
    private var lastInputAt: Date?
    private var lastTick = Date()
    private var sessionID = UUID().uuidString
    private var pendingReplyText: String?

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

    /// 0 → 1 over 8 seconds of idle
    var idleProgress: Double {
        if isSessionPaused { return 1 }
        guard isInSession, sessionStartedAt != nil else { return 0 }
        return min(max(idleElapsed / idleLimit, 0), 1)
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
            || isSessionPaused
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

    var progressBarColor: Color {
        let step = min(Int(sessionProgress * 8), 7)
        return Self.ankyverseColors[step]
    }

    private let currentSessionTag = ChatStore.currentSessionTag

    init() {
        let persisted = ChatStore.shared.load()
        if persisted.isEmpty {
            let welcome = ChatMessage(
                id: UUID(),
                kind: .anky(text: "tell me who you are."),
                timestamp: .now,
                isCurrentSession: true
            )
            messages.append(welcome)
            persist(welcome, kind: .anky(text: "tell me who you are."))
        } else {
            for pm in persisted {
                let isCurrent = pm.sessionTag == currentSessionTag
                let kind: MessageKind
                var msgDuration: TimeInterval? = pm.duration
                switch pm.kind {
                case .anky(let text):
                    kind = .anky(text: text)
                case .user(let text):
                    kind = .user(text: text)
                case .writingSession(let preview, _, _, let dur):
                    kind = .user(text: preview)
                    if msgDuration == nil { msgDuration = dur }
                }
                messages.append(ChatMessage(
                    id: UUID(uuidString: pm.id) ?? UUID(),
                    kind: kind,
                    timestamp: pm.timestamp,
                    isCurrentSession: isCurrent,
                    duration: msgDuration
                ))
            }

            let prompt = ChatMessage(
                id: UUID(),
                kind: .anky(text: "you're back.\nwhat's alive in you right now?"),
                timestamp: .now,
                isCurrentSession: true
            )
            messages.append(prompt)
            persist(prompt, kind: .anky(text: "you're back.\nwhat's alive in you right now?"))
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
        isConversationMode = false
        isInSession = true
        isVoiceSession = voice
        isSessionPaused = false
        sessionText = ""
        sessionElapsed = 0
        idleElapsed = 0
        pendingReplyText = nil
        keystrokeDeltas = []
        sessionStartedAt = nil
        lastInputAt = nil
        lastTick = Date()
        sessionID = UUID().uuidString
    }

    func handleKeyPress(_ character: String) {
        guard !isSessionPaused else { return }

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
    }

    func handleVoiceTranscription(_ text: String) {
        guard !isSessionPaused else { return }

        let now = Date()
        sessionText = text

        if sessionStartedAt == nil {
            sessionStartedAt = now
        }
        lastInputAt = now
        lastTick = now
        idleElapsed = 0
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

        guard sessionStartedAt != nil else { return }

        let delta = min(max(now.timeIntervalSince(lastTick), 0), 0.25)
        lastTick = now

        if isSealEngaged {
            sessionElapsed += delta
            idleElapsed = 0
            return
        }

        idleElapsed = lastInputAt.map { now.timeIntervalSince($0) } ?? 0

        if idleElapsed >= idleLimit {
            if !sessionText.isEmpty {
                isSessionPaused = true
                idleElapsed = idleLimit
            }
            return
        }

        sessionElapsed += delta
    }

    func resumeSession() {
        guard isInSession, isSessionPaused else { return }

        let now = Date()
        isSessionPaused = false
        idleElapsed = 0
        lastInputAt = now
        lastTick = now
    }

    func sendToAnky() {
        guard isInSession, !sessionText.isEmpty else { return }

        let duration = sessionElapsed
        let capturedSessionText = sessionText
        let capture = LocalWritingCapture(
            sessionId: sessionID,
            prompt: "",
            text: capturedSessionText,
            duration: duration,
            wordCount: wordCount,
            keystrokeDeltas: keystrokeDeltas,
            finishedAt: .now,
            estimatedFlowScore: estimateFlowScore()
        )

        let msg = ChatMessage(
            id: UUID(),
            kind: .user(text: capturedSessionText),
            timestamp: .now,
            isCurrentSession: true,
            duration: duration
        )

        lastSessionText = capturedSessionText
        isInSession = false
        isVoiceSession = false
        isSessionPaused = false
        sessionText = ""
        sessionElapsed = 0
        idleElapsed = 0
        isSealEngaged = false
        sessionStartedAt = nil
        lastInputAt = nil
        lastTick = Date()
        isConversationMode = true

        appendMessage(msg)
        persist(msg, kind: .user(text: capturedSessionText), duration: duration)
        AnkyHaptics.messageSent()

        pendingCapture = capture
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
                deliverAnkyResponse(
                    normalizedResponse.isEmpty
                        ? "i'm still here. something slipped on my side. say that again."
                        : normalizedResponse
                )
            } catch {
                pendingReplyText = nil
                deliverAnkyResponse("i'm still here. something slipped on my side. say that again.")
            }
        }
    }

    var shouldShowReplyComposer: Bool {
        guard !isAnkyTyping else { return false }
        return conversationalMessagesForLatestWriting().contains {
            if case .anky = $0.kind { return true }
            return false
        }
    }

    func deliverAnkyResponse(_ text: String) {
        let ankyMsg = ChatMessage(id: UUID(), kind: .anky(text: text), timestamp: .now, isCurrentSession: true)
        appendMessage(ankyMsg)
        persist(ankyMsg, kind: .anky(text: text))
        AnkyHaptics.ankyMessage()
        isAnkyTyping = false
    }

    func leaveWritingSurface() {
        isConversationMode = false
        isInSession = false
        isVoiceSession = false
        isSessionPaused = false
        isSealEngaged = false
        isExternalPresentationActive = false
        sessionText = ""
        sessionElapsed = 0
        idleElapsed = 0
        sessionStartedAt = nil
        lastInputAt = nil
        lastTick = Date()
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
}

// MARK: - AnkyChatView (Root)

struct AnkyChatView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var biometricLock: BiometricLockManager
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var speechManager = SpeechSessionManager()
    @State private var isWritingExperiencePresented = false
    @State private var unlockErrorMessage: String?
    @State private var showAltarSheet = false
    @State private var showProfileSheet = false

    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private var currentDayKingdom: Kingdom { Kingdom.ankyverseDay() }

    /// Latest anky image URL for the pfp button
    private var latestAnkyImageURL: URL? {
        appState.writingHistory.first(where: { $0.isAnky })?.remoteImageURL
    }

    var body: some View {
        ZStack {
            Color.ankyVoid.ignoresSafeArea()

            // Primary surface: chat conversation
            VStack(spacing: 0) {
                // Top nav bar
                chatNavBar

                // Messages
                MessageListView(messages: viewModel.messages, isTyping: viewModel.isAnkyTyping)

                // Bottom input bar
                ChatInputBarView(
                    showsReplyComposer: viewModel.shouldShowReplyComposer,
                    onStartWriting: { presentWritingExperience() },
                    onStartVoice: {
                        viewModel.beginSession(voice: true)
                    },
                    onSendMessage: { message in
                        viewModel.sendReply(message)
                    }
                )
            }
            .opacity(isWritingExperiencePresented ? 0 : 1)

            if isWritingExperiencePresented {
                WritingExperienceContainer(
                    viewModel: viewModel,
                    dayKingdom: currentDayKingdom,
                    onBack: dismissWritingExperience
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .sheet(isPresented: $showAltarSheet) {
            AltarView(isRootExperience: false)
                .environmentObject(appState)
                .sheetStyleBackground(Color.ankyVoid)
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileView()
                .environmentObject(appState)
                .sheetStyleBackground(Color.ankyVoid)
        }
        .onAppear {
            syncExternalPresentationState()
            // App opens directly to writing
            if !viewModel.hasActiveWritingContext && !isWritingExperiencePresented {
                presentWritingExperience()
            }
        }
        .onReceive(tick) { now in
            viewModel.sessionTick(at: now)
        }
        // Voice session cover (only when explicitly started)
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.isVoiceSession && viewModel.isInSession },
            set: { if !$0 { viewModel.isInSession = false } }
        )) {
            VoiceSessionView(viewModel: viewModel, speechManager: speechManager)
        }
        .task(id: viewModel.pendingCapture?.sessionId) {
            guard let capture = viewModel.pendingCapture else { return }
            viewModel.pendingCapture = nil

            do {
                let response = try await AnkyAPI.shared.submitWriting(capture.request)
                appState.recordWriting(capture, response: response, syncState: response.persisted == true ? .synced : .localOnly)

                if response.persisted == true {
                    if response.isAnky {
                        await appState.applyPersistedAnkySuccess(capture: capture, response: response)
                        // Auto-mint cNFT for every persisted anky
                        WritingFlowModel.autoMintCNFT(sessionId: capture.sessionId, appState: appState)
                    }

                    // Poll for ankyResponse
                    var ankyResponseText: String?
                    var nextPrompt: String?
                    var retryDelay: UInt64 = 2_000_000_000
                    for attempt in 0..<30 {
                        try? await Task.sleep(nanoseconds: retryDelay)
                        do {
                            let status = try await AnkyAPI.shared.getWritingStatus(sessionId: capture.sessionId)
                            if let resp = status.ankyResponse {
                                ankyResponseText = resp
                                nextPrompt = status.nextPrompt
                                break
                            }
                        } catch let error as AnkyError where error.isConnectivityIssue {
                            retryDelay = min(retryDelay * 2, 8_000_000_000)
                            if attempt > 15 { break }
                        } catch {
                            break
                        }
                    }

                    let responseText = ankyResponseText
                        ?? "i heard you. every word, every pause between them. sit with what came through — it knows more than you think."
                    appState.storeReflection(responseText, for: capture.sessionId)
                    AnkyNameStore.updateFromReflection(responseText)
                    viewModel.deliverAnkyResponse(responseText)

                    // Archive to Arweave if this was an anky
                    if response.isAnky {
                        WritingFlowModel.archiveToArweave(sessionId: capture.sessionId, text: capture.text)
                    }

                    if let prompt = nextPrompt, !prompt.isEmpty {
                        await DailyPromptNotificationManager.scheduleWithPrompt(prompt)
                    }
                    DailyPromptNotificationManager.clearPendingSession()
                } else {
                    viewModel.deliverAnkyResponse(
                        "i heard you. even the shortest moments of truth leave a mark. come back when you're ready to go deeper."
                    )
                }
            } catch {
                appState.recordWriting(capture, response: nil, syncState: .localOnly)
                viewModel.deliverAnkyResponse(
                    "i heard you. the words are safe. something in what you wrote is trying to reach you — let it."
                )
            }
        }
        .onChange(of: viewModel.isInSession) { _, inSession in
            if !inSession {
                if speechManager.isListening {
                    speechManager.stopListening()
                }
                // Auto-dismiss writing experience when session ends — return to chat
                if isWritingExperiencePresented {
                    dismissWritingExperience()
                }
            }
            syncExternalPresentationState()
        }
        .onChange(of: isWritingExperiencePresented) { _, _ in
            syncExternalPresentationState()
        }
        .onChange(of: viewModel.isConversationMode) { _, _ in
            syncExternalPresentationState()
        }
        .onChange(of: viewModel.isAnkyTyping) { _, _ in
            syncExternalPresentationState()
        }
        .onChange(of: appState.qrSealChallenge) { _, _ in
            syncExternalPresentationState()
        }
        .onChange(of: appState.deepLinkPrompt) { _, prompt in
            guard let prompt, !prompt.isEmpty, !viewModel.isInSession else { return }
            let promptMsg = ChatMessage(
                id: UUID(),
                kind: .anky(text: prompt),
                timestamp: .now,
                isCurrentSession: true
            )
            viewModel.appendMessage(promptMsg)
            appState.deepLinkPrompt = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                presentWritingExperience()
            }
        }
        .task {
            if let pendingId = DailyPromptNotificationManager.pendingSessionId {
                DailyPromptNotificationManager.clearPendingSession()
                do {
                    let status = try await AnkyAPI.shared.getWritingStatus(sessionId: pendingId)
                    if let response = status.ankyResponse {
                        viewModel.deliverAnkyResponse(response)
                    }
                } catch {}
            }
        }
    }

    private var chatNavBar: some View {
        HStack {
            // Left: altar
            Button { showAltarSheet = true } label: {
                Image(systemName: "flame")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("anky")
                .font(.system(size: 13, weight: .medium))
                .kerning(2)
                .foregroundStyle(Color.white.opacity(0.3))

            Spacer()

            // Right: user pfp
            Button { showProfileSheet = true } label: {
                profilePFP
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(appState.kingdom.color.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.ankyVoid)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var profilePFP: some View {
        if let url = latestAnkyImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    pfpPlaceholder
                }
            }
        } else {
            pfpPlaceholder
        }
    }

    private var pfpPlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [appState.kingdom.color.opacity(0.2), Color.ankyVoid],
                        center: .center,
                        startRadius: 4,
                        endRadius: 18
                    )
                )
            AnkyMark(size: 16)
                .opacity(0.5)
        }
    }

    private func presentWritingExperience() {
        if !viewModel.hasActiveWritingContext {
            viewModel.beginSession()
        }

        withAnimation(.easeInOut(duration: 0.28)) {
            isWritingExperiencePresented = true
        }
        syncExternalPresentationState()
    }

    private func dismissWritingExperience() {
        withAnimation(.easeInOut(duration: 0.28)) {
            isWritingExperiencePresented = false
        }
        syncExternalPresentationState()
    }

    private func syncExternalPresentationState() {
        viewModel.setExternalPresentationActive(
            appState.qrSealChallenge != nil
                || (!isWritingExperiencePresented && viewModel.hasActiveWritingContext)
        )
    }
}

private struct WritingExperienceContainer: View {
    @ObservedObject var viewModel: ChatViewModel
    let dayKingdom: Kingdom
    let onBack: () -> Void

    var body: some View {
        Group {
            if viewModel.shouldShowConversationSurface {
                SimpleConversationView(viewModel: viewModel, dayKingdom: dayKingdom)
            } else {
                FullScreenWritingView(viewModel: viewModel, dayKingdom: dayKingdom)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            header
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))

                    Text("altar")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                }
                .foregroundStyle(Color.white.opacity(0.88))
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(dayKingdom.name.lowercased()) day")
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundStyle(dayKingdom.color.opacity(0.92))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    Capsule()
                        .fill(dayKingdom.color.opacity(0.12))
                )
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.9))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
        }
    }
}

private struct SimpleConversationView: View {
    @ObservedObject var viewModel: ChatViewModel
    let dayKingdom: Kingdom

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("stay with the thread.")
                    .font(.custom("Georgia", size: 22))
                    .foregroundStyle(Color.white.opacity(0.9))

                Text(viewModel.isAnkyTyping ? "anky is listening." : "write again or answer directly.")
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)

            MessageListView(messages: viewModel.conversationMessages, isTyping: viewModel.isAnkyTyping)

            ChatInputBarView(
                showsReplyComposer: true,
                onStartWriting: {
                    viewModel.beginSession()
                },
                onStartVoice: {},
                onSendMessage: { message in
                    viewModel.sendReply(message)
                }
            )
            .background(Color.black.opacity(0.92))
        }
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "05050B"),
                    dayKingdom.color.opacity(0.14),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - Full Screen Writing View

struct FullScreenWritingView: View {
    @ObservedObject var viewModel: ChatViewModel
    let dayKingdom: Kingdom

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // 8-second idle bar at top
                IdleProgressBar(progress: viewModel.idleProgress, isPaused: viewModel.isSessionPaused)
                    .padding(.top, 8)

                // Writing canvas — last char at center, text flows left and up
                GeometryReader { geo in
                    let halfW = geo.size.width / 2
                    let halfH = geo.size.height / 2

                    VStack(alignment: .trailing, spacing: 0) {
                        Spacer(minLength: 0)
                        styledText
                            .multilineTextAlignment(.trailing)
                            .frame(width: halfW - 24, alignment: .trailing)
                    }
                    .frame(width: halfW, height: halfH, alignment: .bottomTrailing)
                    .clipped()
                    .position(x: halfW / 2, y: halfH / 2)
                }

                // Chakra progress bar: red → white over 8 minutes
                ChakraProgressBar(progress: viewModel.sessionProgress)
                    .padding(.horizontal, 0)

                if viewModel.isSessionPaused {
                    SessionPauseChoiceView(
                        elapsedLabel: viewModel.elapsedLabel,
                        hasReachedMilestone: viewModel.hasReachedSessionGoal,
                        canSeal: viewModel.canSealSubmission,
                        onSeal: {
                            viewModel.sendToAnky()
                        },
                        onKeepWriting: {
                            viewModel.resumeSession()
                        },
                        onSealInteractionChanged: { isActive in
                            viewModel.setSealInteraction(isActive)
                        }
                    )
                } else {
                    // Keyboard with 8-minute milestone progress and send button
                    WritingKeyboardView(
                        dayKingdom: dayKingdom,
                        elapsedLabel: viewModel.elapsedLabel,
                        progress: viewModel.sessionProgress,
                        progressColor: viewModel.progressBarColor,
                        idleProgress: viewModel.idleProgress,
                        hasReachedMilestone: viewModel.hasReachedSessionGoal,
                        canSeal: viewModel.canSealSubmission,
                        onKeyPress: { char in
                            viewModel.handleKeyPress(char)
                        },
                        onSeal: {
                            viewModel.sendToAnky()
                        },
                        onSealInteractionChanged: { isActive in
                            viewModel.setSealInteraction(isActive)
                        }
                    )
                }
            }
        }
    }

    private var styledText: some View {
        let text = viewModel.sessionText
        if text.isEmpty {
            return AnyView(Text(""))
        }
        let rest = String(text.dropLast())
        let last = String(text.suffix(1))
        return AnyView(
            (Text(rest).foregroundColor(.white) + Text(last).foregroundColor(.red))
                .font(.custom("Georgia", size: 20))
                .lineSpacing(8)
        )
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
                IdleProgressBar(progress: viewModel.idleProgress, isPaused: viewModel.isSessionPaused)
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
                        canSeal: viewModel.canSealSubmission,
                        onSeal: {
                            viewModel.sendToAnky()
                        },
                        onKeepWriting: {
                            viewModel.resumeSession()
                        },
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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: geo.size.width * progress)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 40)
        .opacity(progress > 0 ? 1 : 0.3)
    }

    private var barColor: Color {
        if isPaused {
            return .red
        }
        if progress > 0.6 {
            return Color(hex: "ff4444")
        }
        if progress > 0.3 {
            return Color(hex: "ff8800")
        }
        return Color.white.opacity(0.4)
    }
}

// MARK: - Session Pause Choice

struct SessionPauseChoiceView: View {
    let elapsedLabel: String
    let hasReachedMilestone: Bool
    let canSeal: Bool
    let onSeal: () -> Void
    let onKeepWriting: () -> Void
    var onSealInteractionChanged: ((Bool) -> Void)? = nil

    private let milestoneColor = Color(hex: "f0b35a")

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text(elapsedLabel)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(hasReachedMilestone ? milestoneColor : Color.white.opacity(0.45))
                    .shadow(color: hasReachedMilestone ? milestoneColor.opacity(0.18) : .clear, radius: 10)

                Text("the thread is still here.")
                    .font(.custom("Georgia", size: 19))
                    .foregroundStyle(Color.white.opacity(0.92))

                Text("send what you have, or keep writing.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .padding(.top, 18)

            SealView(label: "seal to send", isEnabled: canSeal) {
                onSeal()
            } onInteractionChanged: { isActive in
                onSealInteractionChanged?(isActive)
            }
            .padding(.horizontal, 28)

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

            Spacer(minLength: 34)
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "0a0a12"))
    }
}

// MARK: - Writing Keyboard (with send button)

struct WritingKeyboardView: View {
    let dayKingdom: Kingdom
    let elapsedLabel: String
    let progress: Double
    let progressColor: Color
    let idleProgress: Double
    let hasReachedMilestone: Bool
    let canSeal: Bool
    let onKeyPress: (String) -> Void
    let onSeal: () -> Void
    var onSealInteractionChanged: ((Bool) -> Void)? = nil

    @State private var showSymbols = false
    @State private var isUppercase = false

    private let row1 = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
    private let row2 = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
    private let row3 = ["z", "x", "c", "v", "b", "n", "m"]
    private let symRow1 = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private let symRow2 = ["!", "@", "#", "$", "%", "&", "*", "(", ")"]
    private let symRow3 = ["-", "+", "=", "'", "\"", ":", ";"]

    private var keyOpacity: Double {
        0.8 - (idleProgress * 0.45)
    }
    private var keyBgOpacity: Double {
        max(0.06, 0.14 - (idleProgress * 0.06))
    }

    private var milestoneColor: Color {
        Color(hex: "f0b35a")
    }

    var body: some View {
        VStack(spacing: 0) {
            SealView(label: "seal to send", isEnabled: canSeal) {
                onSeal()
            } onInteractionChanged: { isActive in
                onSealInteractionChanged?(isActive)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)

            // 8-minute milestone progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    LinearGradient(
                        colors: ChatViewModel.ankyverseColors.map { $0.opacity(0.15) },
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: activeGradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                        .animation(.easeOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 3)

            HStack {
                Text(elapsedLabel)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(hasReachedMilestone ? milestoneColor : progressColor.opacity(0.55))
                    .shadow(color: hasReachedMilestone ? milestoneColor.opacity(0.16) : .clear, radius: 8)

                Spacer()

                Text(dayKingdom.name.lowercased())
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(dayKingdom.color.opacity(0.95))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        Capsule()
                            .fill(dayKingdom.color.opacity(0.12))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 12)

            VStack(spacing: 8) {
                if showSymbols {
                    symbolRows
                } else {
                    letterRows
                }

                bottomActionRow
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 34)
            .animation(.easeOut(duration: 0.15), value: idleProgress)
            .animation(.easeInOut(duration: 0.18), value: showSymbols)
        }
        .background(Color(hex: "0a0a12"))
    }

    private var activeGradientColors: [Color] {
        if hasReachedMilestone {
            return [milestoneColor.opacity(0.9), Color.white.opacity(0.92)]
        }
        let step = min(Int(progress * 8), 7)
        let colors = Array(ChatViewModel.ankyverseColors.prefix(max(step + 1, 1)))
        return colors.isEmpty ? [ChatViewModel.ankyverseColors[0]] : colors
    }

    private var letterRows: some View {
        VStack(spacing: 8) {
            keyRow(row1)
            keyRow(row2)

            HStack(spacing: 5) {
                modifierKey(label: "⇧", width: 46) {
                    isUppercase.toggle()
                }

                ForEach(row3, id: \.self) { key in
                    letterKey(key)
                }

                disabledKey(label: "⌫", width: 46)
            }
        }
    }

    private var symbolRows: some View {
        VStack(spacing: 8) {
            keyRow(symRow1)
            keyRow(symRow2)

            HStack(spacing: 5) {
                Spacer()
                    .frame(width: 46)

                ForEach(symRow3, id: \.self) { key in
                    symbolKey(key)
                }

                disabledKey(label: "⌫", width: 46)
            }
        }
    }

    private var bottomActionRow: some View {
        HStack(spacing: 6) {
            modifierKey(label: showSymbols ? "ABC" : "123", width: 50) {
                showSymbols.toggle()
                isUppercase = false
            }

            symbolKey(",", width: 42)

            Button(action: {
                onKeyPress(" ")
                AnkyHaptics.keyTap()
            }) {
                Text(spaceLabel)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Color.white.opacity(keyOpacity * 0.62))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(dayKingdom.color.opacity(keyBgOpacity))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(dayKingdom.color.opacity(0.22), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)

            symbolKey(".", width: 42)

            modifierKey(label: "↵", width: 46) {
                onKeyPress("\n")
                AnkyHaptics.keyTap()
            }
        }
    }

    private func keyRow(_ keys: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { key in
                if showSymbols {
                    symbolKey(key)
                } else {
                    letterKey(key)
                }
            }
        }
    }

    private func letterKey(_ key: String, width: CGFloat? = nil) -> some View {
        let output = isUppercase ? key.uppercased() : key
        return keyButton(label: output, width: width) {
            onKeyPress(output)
            AnkyHaptics.keyTap()
            if isUppercase {
                isUppercase = false
            }
        }
    }

    private func symbolKey(_ key: String, width: CGFloat? = nil) -> some View {
        keyButton(label: key, width: width) {
            onKeyPress(key)
            AnkyHaptics.keyTap()
        }
    }

    private func modifierKey(label: String, width: CGFloat? = nil, action: @escaping () -> Void) -> some View {
        keyButton(label: label, width: width, fill: Color.white.opacity(0.08), stroke: Color.white.opacity(0.08), font: .system(size: 14, weight: .semibold), action: action)
    }

    private func disabledKey(label: String, width: CGFloat? = nil) -> some View {
        keyButton(label: label, width: width, fill: Color.white.opacity(0.03), stroke: Color.white.opacity(0.04), textColor: Color.white.opacity(0.2), font: .system(size: 14, weight: .semibold), action: {})
    }

    private func keyButton(
        label: String,
        width: CGFloat? = nil,
        fill: Color? = nil,
        stroke: Color? = nil,
        textColor: Color? = nil,
        font: Font? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(font ?? .system(size: 20, weight: .light))
                .foregroundStyle(textColor ?? Color.white.opacity(keyOpacity))
                .frame(maxWidth: width == nil ? .infinity : nil)
                .frame(width: width, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(fill ?? dayKingdom.color.opacity(keyBgOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(stroke ?? dayKingdom.color.opacity(0.18), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    private var spaceLabel: String {
        switch dayKingdom {
        case .primordia:
            return "root"
        case .emblazion:
            return "ember"
        case .chryseos:
            return "gold"
        case .eleutheria:
            return "heart"
        case .voxlumis:
            return "voice"
        case .insightia:
            return "sight"
        case .claridium:
            return "crown"
        case .poiesis:
            return "poiesis"
        }
    }
}

// MARK: - Message List

struct MessageListView: View {
    let messages: [ChatMessage]
    let isTyping: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 22) {
                    ForEach(messages) { message in
                        MessageRow(message: message)
                            .opacity(message.isCurrentSession ? 1 : 0.35)
                            .id(message.id)
                    }

                    if isTyping {
                        TypingIndicatorView()
                            .id("typing")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.count) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onChange(of: isTyping) { _, typing in
                if typing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = false) {
        let target: AnyHashable = isTyping ? "typing" : (messages.last?.id ?? UUID())
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

    var body: some View {
        switch message.kind {
        case .anky(let text):
            AnkyMessageView(text: text, timestamp: message.timestamp)
        case .user(let text):
            UserMessageView(text: text, timestamp: message.timestamp, duration: message.duration)
        }
    }
}

// MARK: - Anky Message

struct AnkyMessageView: View {
    let text: String
    let timestamp: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.custom("Georgia", size: 15))
                .lineSpacing(8)
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(timestamp.chatShortTime)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.25))
        }
    }
}

// MARK: - User Message

struct UserMessageView: View {
    let text: String
    let timestamp: Date
    var duration: TimeInterval?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(6)
                .foregroundStyle(Color.white)
                .lineLimit(12)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(Color.orange.opacity(0.12))
                .clipShape(ChatBubbleShape(isUser: true))
                .frame(maxWidth: 265, alignment: .trailing)

            HStack(spacing: 6) {
                if let duration {
                    Text(durationLabel(duration))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.25))
                }
                Text(timestamp.chatShortTime)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
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

// MARK: - Chat Bubble Shape

struct ChatBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let rSmall: CGFloat = 4
        var path = Path()
        if isUser {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rSmall))
            path.addArc(center: CGPoint(x: rect.maxX - rSmall, y: rect.maxY - rSmall), radius: rSmall, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + rSmall, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + rSmall, y: rect.maxY - rSmall), radius: rSmall, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Chat Header

struct ChatHeaderView: View {
    var onAnkyTap: () -> Void
    var onUserTap: () -> Void

    var body: some View {
        HStack {
            AnkyPFP()
                .onTapGesture { onAnkyTap() }
            Spacer()
            Text("a n k y")
                .font(.system(size: 12, weight: .medium))
                .kerning(4)
                .foregroundStyle(Color.white.opacity(0.35))
            Spacer()
            UserPFP()
                .onTapGesture { onUserTap() }
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
        .background(Color.ankyVoid)
    }
}

struct AnkyPFP: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.12))
                .frame(width: 38, height: 38)
            Text("✦")
                .font(.custom("Georgia", size: 15))
                .foregroundStyle(.orange)
        }
    }
}

struct UserPFP: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: 38, height: 38)
            Image(systemName: "person.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase == i ? 1.3 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
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

// MARK: - Chat Input Bar

struct ChatInputBarView: View {
    let showsReplyComposer: Bool
    var onStartWriting: () -> Void
    var onStartVoice: () -> Void
    var onSendMessage: (String) -> Void

    @State private var replyText = ""

    var body: some View {
        HStack(spacing: 10) {
            if showsReplyComposer {
                Button(action: {
                    replyText = ""
                    onStartWriting()
                }) {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.45))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    TextField("reply...", text: $replyText)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(false)
                        .submitLabel(.send)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .onSubmit {
                            submitReply()
                        }

                    Button(action: submitReply) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(trimmedReply.isEmpty ? Color.white.opacity(0.18) : Color.orange.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedReply.isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
            } else {
                Button(action: onStartWriting) {
                    HStack {
                        Text("write here...")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.25))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onStartVoice) {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "mic")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.4))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.ankyVoid)
    }

    private var trimmedReply: String {
        replyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitReply() {
        let message = trimmedReply
        guard !message.isEmpty else { return }
        replyText = ""
        onSendMessage(message)
    }
}

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

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 20)

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 72, height: 72)
                if let user = appState.user, let name = user.displayName ?? user.username {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.bottom, 10)

            if let user = appState.user {
                Text(user.displayName ?? user.username ?? "writer")
                    .font(.system(size: 16, weight: .medium))
                Text("writing since now")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)

                Divider().opacity(0.2).padding(.vertical, 18)

                HStack {
                    statColumn("\(user.totalWritings)", "sessions")
                    statColumn("\(user.totalAnkys)", "ankys")
                    statColumn("\(appState.writingHistory.count)", "local")
                }
                .padding(.horizontal, 20)
            } else {
                Text("writer").font(.system(size: 16, weight: .medium))
                Text("\(appState.writingHistory.count) sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            Spacer()
        }
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.hidden)
    }

    private func statColumn(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .medium))
            Text(label).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Date Extension

extension Date {
    var chatShortTime: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f.string(from: self)
    }
}
