import AVFoundation
import Combine
import SwiftUI
import UIKit

enum GuidancePlaybackMode: Equatable {
    case meditation
    case breathwork(style: String?)

    var accent: Color {
        switch self {
        case .meditation:
            return .ankyGold
        case .breathwork:
            return .ankyPurpleSoft
        }
    }

    var restingColor: Color {
        switch self {
        case .meditation:
            return .ankyAmber.opacity(0.78)
        case .breathwork:
            return Color(red: 0.15, green: 0.22, blue: 0.42)
        }
    }

    var title: String {
        switch self {
        case .meditation:
            return "Sit"
        case .breathwork:
            return "Breathe"
        }
    }

    var experience: AppState.ActiveExperience {
        switch self {
        case .meditation:
            return .meditation
        case .breathwork:
            return .breathwork
        }
    }
}

@MainActor
final class GuidancePlaybackModel: NSObject, ObservableObject {
    enum BreathCue: String {
        case inhale = "Inhale"
        case hold = "Hold"
        case exhale = "Exhale"
        case rest = "Rest"
        case settling = "Arrive"
    }

    @Published var currentPhaseIndex = 0
    @Published var currentPhaseName = "Arriving"
    @Published var subtitle = ""
    @Published var cue: BreathCue = .settling
    @Published var repLabel: String?
    @Published var elapsedSeconds = 0
    @Published var isPaused = false
    @Published var isComplete = false
    @Published var controlsVisible = true
    @Published var orbScale: CGFloat = 0.5
    @Published var orbColor: Color

    let session: GuidanceSession
    let mode: GuidancePlaybackMode

    private let speaker = GuidanceSpeaker()
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)

    private var playbackTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var meditationSessionID: String?

    init(session: GuidanceSession, mode: GuidancePlaybackMode) {
        self.session = session
        self.mode = mode
        self.orbColor = mode.restingColor
        super.init()
    }

    func start() {
        guard playbackTask == nil else { return }
        configureSpeaker()

        elapsedTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !self.isComplete {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard !self.isPaused else { continue }
                self.elapsedSeconds += 1
            }
        }

        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.beginLoggingIfNeeded()
            await self.runSession()
        }
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            speaker.pause()
        } else {
            speaker.resume()
        }
    }

    func revealControls() {
        controlsVisible.toggle()
    }

    func finishEarly() async {
        playbackTask?.cancel()
        elapsedTask?.cancel()
        speaker.stop()
        await logCompletion(completed: false)
    }

    func completeAndStopIfNeeded() async {
        await logCompletion(completed: true)
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

    var bpmDuration: Double {
        max(60.0 / Double(max(session.backgroundBeatBpm, 1)), 0.75)
    }

    private func configureSpeaker() {
        speaker.configure()
        lightHaptic.prepare()
        mediumHaptic.prepare()
        heavyHaptic.prepare()
    }

    private func beginLoggingIfNeeded() async {
        guard case .meditation = mode else { return }
        let minutes = max(Int(ceil(Double(session.durationSeconds) / 60.0)), 1)
        meditationSessionID = try? await AnkyAPI.shared.startMeditation(minutes: minutes).sessionId
    }

    private func runSession() async {
        for (index, phase) in session.phases.enumerated() {
            guard !Task.isCancelled else { return }
            currentPhaseIndex = index
            currentPhaseName = phase.name
            subtitle = phase.narration
            repLabel = nil

            switch phase.kind {
            case .narration, .bodyScan, .visualization:
                cue = .settling
                await setOrb(scale: 0.58, color: mode.accent.opacity(0.78), duration: 1.0)
                await speakAndHold(phase)
            case .breathing:
                await runBreathingPhase(phase)
            case .hold:
                cue = .hold
                heavyHaptic.impactOccurred()
                await setOrb(scale: 0.88, color: mode.accent, duration: 0.8)
                if !phase.narration.isEmpty {
                    _ = await speaker.speak(phase.narration)
                }
                let holdSeconds = phase.holdSeconds ?? Double(phase.durationSeconds)
                await sleepRespectingPause(seconds: holdSeconds)
            case .rest:
                cue = .rest
                subtitle = phase.narration.isEmpty ? "Silence." : phase.narration
                await setOrb(scale: 0.42, color: mode.restingColor.opacity(0.72), duration: 1.0)
                await sleepRespectingPause(seconds: Double(phase.durationSeconds))
            }
        }

        isComplete = true
        controlsVisible = true
        cue = .rest
        repLabel = nil
        subtitle = mode == .meditation ? "The sit has landed." : "The breath has come back to stillness."
        await setOrb(scale: 0.46, color: mode.restingColor, duration: 1.2)
        await logCompletion(completed: true)
    }

    private func speakAndHold(_ phase: GuidancePhase) async {
        let spokenDuration = await speaker.speak(phase.narration)
        let remaining = max(0, Double(phase.durationSeconds) - spokenDuration)
        await sleepRespectingPause(seconds: remaining)
    }

    private func runBreathingPhase(_ phase: GuidancePhase) async {
        if !phase.narration.isEmpty {
            _ = await speaker.speak(phase.narration)
        }

        let inhale = phase.inhaleSeconds ?? 4
        let hold = phase.holdSeconds ?? 0
        let exhale = phase.exhaleSeconds ?? 4
        let reps = max(phase.reps ?? 4, 1)

        for rep in 0..<reps {
            guard !Task.isCancelled else { return }

            repLabel = "\(rep + 1) / \(reps)"

            cue = .inhale
            lightHaptic.impactOccurred()
            await setOrb(scale: 1.0, color: mode.accent, duration: inhale)
            await sleepRespectingPause(seconds: inhale)

            if hold > 0 {
                cue = .hold
                heavyHaptic.impactOccurred()
                await setOrb(scale: 0.92, color: mode.accent.opacity(0.92), duration: 0.4)
                await sleepRespectingPause(seconds: hold)
            }

            cue = .exhale
            mediumHaptic.impactOccurred()
            await setOrb(scale: 0.42, color: mode.restingColor, duration: exhale)
            await sleepRespectingPause(seconds: exhale)
        }
    }

    private func setOrb(scale: CGFloat, color: Color, duration: Double) async {
        withAnimation(.easeInOut(duration: duration)) {
            orbScale = scale
            orbColor = color
        }
    }

    private func sleepRespectingPause(seconds: Double) async {
        guard seconds > 0 else { return }

        var remaining = seconds
        while remaining > 0, !Task.isCancelled {
            if isPaused {
                try? await Task.sleep(for: .milliseconds(150))
                continue
            }

            let slice = min(remaining, 0.1)
            try? await Task.sleep(for: .milliseconds(Int(slice * 1000)))
            remaining -= slice
        }
    }

    private func logCompletion(completed: Bool) async {
        guard !Task.isCancelled else { return }

        switch mode {
        case .meditation:
            guard let meditationSessionID else { return }
            _ = try? await AnkyAPI.shared.completeMeditation(
                MeditationCompleteRequest(
                    sessionId: meditationSessionID,
                    actualSeconds: elapsedSeconds,
                    completed: completed
                )
            )
            self.meditationSessionID = nil
        case .breathwork:
            guard completed, let sessionID = session.id else { return }
            _ = try? await AnkyAPI.shared.completeBreathwork(
                BreathworkCompleteRequest(sessionId: sessionID, notes: nil)
            )
        }
    }
}

@MainActor
private final class GuidanceSpeaker: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Double, Never>?
    private var startedAt: Date?

    func configure() {
        synthesizer.delegate = self
    }

    func speak(_ text: String) async -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = bestVoice()
        utterance.rate = 0.42
        utterance.pitchMultiplier = 0.9
        utterance.preUtteranceDelay = 0.4
        utterance.postUtteranceDelay = 0.25
        startedAt = .now

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            synthesizer.speak(utterance)
        }
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

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

    private func bestVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice
            .speechVoices()
            .filter { $0.language.starts(with: "en") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .first
    }
}

struct GuidancePlaybackView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model: GuidancePlaybackModel

    init(session: GuidanceSession, mode: GuidancePlaybackMode) {
        _model = StateObject(wrappedValue: GuidancePlaybackModel(session: session, mode: mode))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.ankyBlack, model.mode.restingColor.opacity(0.22), Color.ankyBlack],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                topBar

                Spacer(minLength: 20)

                VStack(spacing: 18) {
                    Text(model.currentPhaseName.uppercased())
                        .font(.custom("Righteous-Regular", size: 12))
                        .foregroundStyle(model.mode.accent.opacity(0.92))
                        .tracking(1.6)

                    GuidanceOrb(
                        scale: model.orbScale,
                        color: model.orbColor,
                        pulseDuration: model.bpmDuration
                    )

                    VStack(spacing: 10) {
                        Text(model.cue.rawValue)
                            .font(.custom("Righteous-Regular", size: 30))
                            .foregroundStyle(Color.ankyInk)

                        if let repLabel = model.repLabel {
                            Text(repLabel)
                                .font(.custom("Righteous-Regular", size: 13))
                                .foregroundStyle(model.mode.accent)
                        }
                    }
                }

                Spacer(minLength: 20)

                VStack(spacing: 16) {
                    Text(model.subtitle)
                        .font(.custom("Georgia", size: 21))
                        .foregroundStyle(Color.ankyInk.opacity(0.92))
                        .lineSpacing(8)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))

                            Capsule(style: .continuous)
                                .fill(model.mode.accent)
                                .frame(width: max(proxy.size.width * model.progress, 14))
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 8)

                    Text(model.elapsedLabel)
                        .font(.custom("Righteous-Regular", size: 12))
                        .foregroundStyle(Color.ankyMuted)
                }

                if model.controlsVisible {
                    controls
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.35)) {
                model.revealControls()
            }
        }
        .task {
            appState.activeExperience = model.mode.experience
            model.start()
        }
        .onDisappear {
            appState.activeExperience = nil
        }
        .statusBarHidden(true)
    }

    private var topBar: some View {
        HStack {
            Text(model.mode.title)
                .font(.custom("Righteous-Regular", size: 20))
                .foregroundStyle(model.mode.accent)

            Spacer()

            Button {
                Task {
                    await model.finishEarly()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ankyInk)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if model.isComplete {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.custom("Righteous-Regular", size: 18))
                        .foregroundStyle(Color.ankyBlack)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(model.mode.accent)
                        )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        model.togglePause()
                    }
                } label: {
                    Text(model.isPaused ? "Resume" : "Pause")
                        .font(.custom("Righteous-Regular", size: 17))
                        .foregroundStyle(model.mode.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct GuidanceOrb: View {
    let scale: CGFloat
    let color: Color
    let pulseDuration: Double

    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 1)
                .frame(width: 320, height: 320)
                .scaleEffect(pulse ? 1.02 : 0.96)
                .animation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true), value: pulse)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.96), color.opacity(0.26), .clear],
                        center: .center,
                        startRadius: 24,
                        endRadius: 170
                    )
                )
                .frame(width: 300, height: 300)
                .scaleEffect(scale)
        }
        .frame(height: 320)
        .onAppear {
            pulse = true
        }
    }
}
