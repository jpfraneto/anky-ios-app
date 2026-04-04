import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit

struct StoryLanguage: Identifiable, Hashable {
    let id: String
    let label: String
    let voices: [String]

    static let available: [StoryLanguage] = [
        StoryLanguage(id: "en", label: "English", voices: ["en-US", "en-GB", "en-AU", "en"]),
        StoryLanguage(id: "es", label: "Español", voices: ["es-MX", "es-ES", "es-US", "es"]),
        StoryLanguage(id: "pt", label: "Português", voices: ["pt-BR", "pt-PT", "pt"]),
        StoryLanguage(id: "fr", label: "Français", voices: ["fr-FR", "fr-CA", "fr"]),
        StoryLanguage(id: "de", label: "Deutsch", voices: ["de-DE", "de"]),
        StoryLanguage(id: "it", label: "Italiano", voices: ["it-IT", "it"]),
        StoryLanguage(id: "ru", label: "Русский", voices: ["ru-RU", "ru"]),
        StoryLanguage(id: "ja", label: "日本語", voices: ["ja-JP", "ja"]),
        StoryLanguage(id: "ko", label: "한국어", voices: ["ko-KR", "ko"]),
        StoryLanguage(id: "zh", label: "中文", voices: ["zh-CN", "zh-TW", "zh-HK", "zh"]),
        StoryLanguage(id: "ar", label: "العربية", voices: ["ar-SA", "ar-001", "ar"]),
        StoryLanguage(id: "hi", label: "हिन्दी", voices: ["hi-IN", "hi"]),
        StoryLanguage(id: "fil", label: "Filipino", voices: ["fil-PH", "fil"]),
        StoryLanguage(id: "id", label: "Bahasa Indonesia", voices: ["id-ID", "id"]),
        StoryLanguage(id: "tr", label: "Türkçe", voices: ["tr-TR", "tr"]),
        StoryLanguage(id: "pl", label: "Polski", voices: ["pl-PL", "pl"]),
        StoryLanguage(id: "nl", label: "Nederlands", voices: ["nl-NL", "nl-BE", "nl"]),
        StoryLanguage(id: "sv", label: "Svenska", voices: ["sv-SE", "sv"]),
        StoryLanguage(id: "da", label: "Dansk", voices: ["da-DK", "da"]),
        StoryLanguage(id: "nb", label: "Norsk", voices: ["nb-NO", "nb"]),
        StoryLanguage(id: "fi", label: "Suomi", voices: ["fi-FI", "fi"]),
        StoryLanguage(id: "el", label: "Ελληνικά", voices: ["el-GR", "el"]),
        StoryLanguage(id: "he", label: "עברית", voices: ["he-IL", "he"]),
        StoryLanguage(id: "th", label: "ไทย", voices: ["th-TH", "th"]),
        StoryLanguage(id: "vi", label: "Tiếng Việt", voices: ["vi-VN", "vi"]),
        StoryLanguage(id: "uk", label: "Українська", voices: ["uk-UA", "uk"]),
        StoryLanguage(id: "ro", label: "Română", voices: ["ro-RO", "ro"]),
        StoryLanguage(id: "cs", label: "Čeština", voices: ["cs-CZ", "cs"]),
        StoryLanguage(id: "hu", label: "Magyar", voices: ["hu-HU", "hu"]),
        StoryLanguage(id: "sk", label: "Slovenčina", voices: ["sk-SK", "sk"]),
        StoryLanguage(id: "hr", label: "Hrvatski", voices: ["hr-HR", "hr"]),
        StoryLanguage(id: "ca", label: "Català", voices: ["ca-ES", "ca"]),
        StoryLanguage(id: "ms", label: "Bahasa Melayu", voices: ["ms-MY", "ms"]),
        StoryLanguage(id: "bn", label: "বাংলা", voices: ["bn-IN", "bn-BD", "bn"]),
        StoryLanguage(id: "ta", label: "தமிழ்", voices: ["ta-IN", "ta"]),
        StoryLanguage(id: "te", label: "తెలుగు", voices: ["te-IN", "te"]),
    ]
}

// MARK: - Voice Settings

struct VoiceInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality

    var qualityLabel: String {
        switch quality {
        case .enhanced: return "enhanced"
        case .premium: return "premium"
        default: return "default"
        }
    }

    init(from voice: AVSpeechSynthesisVoice) {
        self.id = voice.identifier
        self.name = voice.name
        self.language = voice.language
        self.quality = voice.quality
    }
}

// MARK: - StoryPlaybackModel

@MainActor
final class StoryPlaybackModel: NSObject, ObservableObject {
    @Published var currentPhaseIndex = 0
    @Published var currentPhaseName = ""
    @Published var subtitle = ""
    @Published var elapsedSeconds = 0
    @Published var isPaused = false
    @Published var isComplete = false
    @Published var controlsVisible = true
    @Published var selectedLanguage: StoryLanguage

    // Voice settings
    @Published var speechRate: Float = 0.38
    @Published var speechPitch: Float = 0.95
    @Published var selectedVoiceId: String?
    @Published var availableVoices: [VoiceInfo] = []

    let session: GuidanceSession
    let storyId: String
    let onFinish: ((Bool) async -> Void)?

    private let speaker = StorySpeaker()
    private var playbackTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var didReportCompletion = false

    init(
        session: GuidanceSession,
        storyId: String = "",
        onFinish: ((Bool) async -> Void)? = nil
    ) {
        self.session = session
        self.storyId = storyId
        self.onFinish = onFinish

        // Use user's preferred language, falling back to content detection
        let settings = UserSettings.shared
        self.selectedLanguage = settings.preferredStoryLanguage

        super.init()
        refreshAvailableVoices()
    }

    func start() {
        guard playbackTask == nil else { return }
        applySpeakerSettings()
        setupRemoteCommands()

        // Resume from saved position if available
        var startIndex = 0
        if let savedPosition = UserSettings.shared.resumePosition(for: storyId) {
            let targetSeconds = Int(savedPosition)
            var accumulated = 0
            for (i, phase) in session.phases.enumerated() {
                if accumulated + phase.durationSeconds > targetSeconds {
                    startIndex = i
                    elapsedSeconds = targetSeconds
                    break
                }
                accumulated += phase.durationSeconds
            }
        }

        elapsedTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !self.isComplete {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard !self.isPaused else { continue }
                self.elapsedSeconds += 1
                self.savePosition()
                self.updateNowPlaying()
            }
        }

        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.runSession(from: startIndex)
        }
    }

    func changeLanguage(to language: StoryLanguage) {
        selectedLanguage = language
        selectedVoiceId = nil
        refreshAvailableVoices()
        restartFromCurrentPhase()
    }

    func applyVoiceSettings() {
        restartFromCurrentPhase()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            speaker.pause()
            savePosition()
        } else {
            speaker.resume()
        }
        updateNowPlaying()
    }

    func skipToNext() {
        playbackTask?.cancel()
        let nextIndex = currentPhaseIndex + 1
        guard nextIndex < session.phases.count else {
            isComplete = true
            controlsVisible = true
            return
        }
        speaker.stop()
        currentPhaseIndex = nextIndex

        // Recalculate elapsed to match phase start
        var accumulated = 0
        for i in 0..<nextIndex {
            accumulated += session.phases[i].durationSeconds
        }
        elapsedSeconds = accumulated

        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.runSession(from: nextIndex)
        }
    }

    func skipToPrevious() {
        playbackTask?.cancel()
        let prevIndex = max(currentPhaseIndex - 1, 0)
        speaker.stop()
        currentPhaseIndex = prevIndex

        var accumulated = 0
        for i in 0..<prevIndex {
            accumulated += session.phases[i].durationSeconds
        }
        elapsedSeconds = accumulated

        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.runSession(from: prevIndex)
        }
    }

    func finishEarly() async {
        playbackTask?.cancel()
        elapsedTask?.cancel()
        speaker.stop()
        savePosition()
        clearRemoteCommands()
        await reportCompletion(completed: false)
    }

    func seekTo(fraction: Double) {
        let total = max(session.durationSeconds, 1)
        elapsedSeconds = Int(fraction * Double(total))
    }

    var progress: Double {
        let total = max(session.durationSeconds, 1)
        return min(Double(elapsedSeconds) / Double(total), 1)
    }

    var elapsedLabel: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var totalLabel: String {
        let minutes = session.durationSeconds / 60
        let seconds = session.durationSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var fullNarration: String {
        session.phases.map { $0.translatedNarration(for: selectedLanguage.id) }.joined(separator: "\n\n")
    }

    func refreshAvailableVoices() {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let matching = allVoices.filter { voice in
            selectedLanguage.voices.contains { lang in
                voice.language == lang || voice.language.hasPrefix(lang)
            }
        }
        .sorted { $0.quality.rawValue > $1.quality.rawValue }

        availableVoices = matching.map { VoiceInfo(from: $0) }

        if selectedVoiceId == nil || !availableVoices.contains(where: { $0.id == selectedVoiceId }) {
            selectedVoiceId = availableVoices.first?.id
        }
    }

    // MARK: - Now Playing

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPaused else { return }
                self.togglePause()
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPaused else { return }
                self.togglePause()
            }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePause() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToNext() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToPrevious() }
            return .success
        }

        updateNowPlaying()
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: session.title,
            MPMediaItemPropertyArtist: "Anky",
            MPMediaItemPropertyPlaybackDuration: NSNumber(value: session.durationSeconds),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: elapsedSeconds),
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: isPaused ? 0.0 : 1.0),
        ]

        // Set artwork from current phase image if available
        if let imageUrl = session.phases[safe: currentPhaseIndex]?.imageUrl,
           let url = URL(string: imageUrl),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            let artwork = MPMediaItemArtwork(boundsSize: uiImage.size) { _ in uiImage }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Playback Position

    private func savePosition() {
        guard !storyId.isEmpty else { return }
        UserSettings.shared.savePlaybackPosition(storyId: storyId, position: Double(elapsedSeconds))
    }

    // MARK: - Private

    private func applySpeakerSettings() {
        speaker.configure(
            preferredLanguages: selectedLanguage.voices,
            rate: speechRate,
            pitch: speechPitch,
            voiceId: selectedVoiceId
        )
    }

    private func restartFromCurrentPhase() {
        speaker.stop()
        applySpeakerSettings()
        let currentIndex = currentPhaseIndex
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.runSession(from: currentIndex)
        }
    }

    private func runSession(from startIndex: Int = 0) async {
        for index in startIndex..<session.phases.count {
            guard !Task.isCancelled else { return }
            let phase = session.phases[index]
            currentPhaseIndex = index
            currentPhaseName = phase.name

            // Use translated narration if available for selected language
            let narrationText = phase.translatedNarration(for: selectedLanguage.id)
            subtitle = narrationText
            updateNowPlaying()

            // Speak narration — flows continuously, minimal gap between phases
            await speaker.speak(narrationText)

            // Brief transition pause between phases (not the full durationSeconds gap)
            if index < session.phases.count - 1 {
                await sleepRespectingPause(seconds: 0.3)
            }
        }

        isComplete = true
        controlsVisible = true
        subtitle = ""

        // Mark completed
        if !storyId.isEmpty {
            UserSettings.shared.markStoryCompleted(storyId)
            UserSettings.shared.clearPlaybackPosition()
        }
        clearRemoteCommands()
        await reportCompletion(completed: true)
    }

    private func sleepRespectingPause(seconds: Double) async {
        guard seconds > 0 else { return }
        var remaining = seconds
        while remaining > 0, !Task.isCancelled {
            if isPaused {
                try? await Task.sleep(nanoseconds: 150_000_000)
                continue
            }
            let slice = min(remaining, 0.1)
            try? await Task.sleep(nanoseconds: UInt64(slice * 1_000_000_000))
            remaining -= slice
        }
    }

    private func reportCompletion(completed: Bool) async {
        guard !didReportCompletion else { return }
        didReportCompletion = true
        await onFinish?(completed)
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - StorySpeaker

@MainActor
private final class StorySpeaker: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Double, Never>?
    private var startedAt: Date?
    private var preferredLanguages: [String] = ["en-US", "en"]
    private var rate: Float = 0.38
    private var pitch: Float = 0.95
    private var voiceId: String?

    func configure(preferredLanguages: [String], rate: Float, pitch: Float, voiceId: String?) {
        synthesizer.delegate = self
        self.preferredLanguages = preferredLanguages
        self.rate = rate
        self.pitch = pitch
        self.voiceId = voiceId
    }

    func speak(_ text: String) async -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = resolveVoice()
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.1
        startedAt = .now

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            synthesizer.speak(utterance)
        }
    }

    func pause() { synthesizer.pauseSpeaking(at: .word) }
    func resume() { synthesizer.continueSpeaking() }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish()
    }

    private func finish() {
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        continuation?.resume(returning: duration)
        continuation = nil
    }

    private func resolveVoice() -> AVSpeechSynthesisVoice? {
        if let voiceId, let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            return voice
        }
        return AVSpeechSynthesisVoice
            .speechVoices()
            .filter { voice in
                preferredLanguages.contains { language in
                    voice.language == language || voice.language.hasPrefix(language)
                }
            }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .first
            ?? AVSpeechSynthesisVoice.speechVoices()
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .first
    }
}

// MARK: - GuidancePlaybackView (Legacy wrapper)

struct GuidancePlaybackView: View {
    @Environment(\.dismiss) private var dismiss

    let session: GuidanceSession
    let onFinish: ((Bool) async -> Void)?

    init(
        session: GuidanceSession,
        onFinish: ((Bool) async -> Void)? = nil
    ) {
        self.session = session
        self.onFinish = onFinish
    }

    var body: some View {
        let story = Cuentacuentos(
            id: session.id ?? UUID().uuidString,
            writingId: "",
            title: session.title,
            content: session.description,
            guidancePhases: session.phases,
            played: false,
            generatedAt: "",
            contentEs: nil,
            contentZh: nil,
            contentHi: nil,
            contentAr: nil
        )

        StoryPlayerView(story: story, onFinish: onFinish)
    }
}
