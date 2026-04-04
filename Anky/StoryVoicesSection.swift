//
//  StoryVoicesSection.swift
//  Anky
//

import AVFoundation
import Combine
import SwiftUI

// MARK: - Story Voices Model

@MainActor
final class StoryVoicesModel: ObservableObject {
    @Published var recordings: [VoiceRecording] = []
    @Published var storyVoice: StoryVoice?
    @Published var isLoading = false
    @Published var voicePlayerState: VoicePlayerState = .idle

    let storyId: String
    let storyWordCount: Int
    var language: String = "en"

    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var completionFired = false
    private var activeRecordingId: String?

    @Published var playbackProgress: Double = 0
    @Published var playbackElapsed: Double = 0

    /// All approved recordings from any user
    var approvedVoices: [VoiceRecording] {
        recordings.filter { $0.status == .approved }
    }

    /// Only the current user's recordings
    var myRecordings: [VoiceRecording] {
        guard let myId = currentUserId else { return [] }
        return recordings.filter { $0.userId == myId }
    }

    var myAttemptCount: Int { myRecordings.count }
    var canRecord: Bool { myAttemptCount < 4 }
    var nextAttemptNumber: Int { myAttemptCount + 1 }

    var hasApprovedVoice: Bool {
        storyVoice != nil || !approvedVoices.isEmpty
    }

    var currentUserId: String?

    enum VoicePlayerState: Equatable {
        case idle
        case loading
        case playing
        case paused
    }

    init(storyId: String, storyWordCount: Int) {
        self.storyId = storyId
        self.storyWordCount = storyWordCount
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let recordingsTask: [VoiceRecording]? = {
            try? await AnkyAPI.shared.getRecordings(storyId: storyId)
        }()
        async let voiceTask: StoryVoice? = {
            try? await AnkyAPI.shared.getStoryVoice(storyId: storyId, language: language)
        }()

        let (fetchedRecordings, fetchedVoice) = await (recordingsTask, voiceTask)
        recordings = fetchedRecordings ?? []
        storyVoice = fetchedVoice
    }

    func playVoice(audioUrl: String? = nil, recordingId: String? = nil) {
        let urlString = audioUrl ?? storyVoice?.audioUrl
        let recId = recordingId ?? storyVoice?.recordingId
        guard let urlString, let url = URL(string: urlString) else { return }

        // Stop current playback if switching voices
        if voicePlayerState == .playing || voicePlayerState == .paused {
            stopVoice()
        }

        activeRecordingId = recId
        voicePlayerState = .loading

        Task {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)

                let (data, _) = try await URLSession.shared.data(from: url)
                let player = try AVAudioPlayer(data: data)
                self.audioPlayer = player
                player.play()
                voicePlayerState = .playing
                completionFired = false

                playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.updatePlayback()
                    }
                }
            } catch {
                voicePlayerState = .idle
            }
        }
    }

    func togglePlayPause(audioUrl: String? = nil, recordingId: String? = nil) {
        let recId = recordingId ?? storyVoice?.recordingId

        // If tapping a different recording, start fresh
        if let recId, recId != activeRecordingId {
            playVoice(audioUrl: audioUrl, recordingId: recId)
            return
        }

        guard let player = audioPlayer else {
            playVoice(audioUrl: audioUrl, recordingId: recId)
            return
        }

        if player.isPlaying {
            player.pause()
            voicePlayerState = .paused
        } else {
            player.play()
            voicePlayerState = .playing
        }
    }

    func stopVoice() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackProgress = 0
        playbackElapsed = 0
        voicePlayerState = .idle
        activeRecordingId = nil
    }

    func isActiveRecording(_ id: String) -> Bool {
        activeRecordingId == id
    }

    var playbackElapsedLabel: String {
        let total = max(Int(playbackElapsed), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var voiceDurationLabel: String {
        guard let voice = storyVoice else { return "0:00" }
        let total = max(Int(voice.durationSeconds), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func updatePlayback() {
        guard let player = audioPlayer else { return }

        if player.isPlaying {
            playbackElapsed = player.currentTime
            playbackProgress = player.currentTime / max(player.duration, 1)
        } else if player.currentTime >= player.duration - 0.1 {
            if !completionFired, let recId = activeRecordingId {
                completionFired = true
                Task {
                    try? await AnkyAPI.shared.markListenComplete(
                        storyId: storyId,
                        recordingId: recId
                    )
                }
            }
            stopVoice()
        }
    }
}

// MARK: - Story Voices Section View

struct StoryVoicesSection: View {
    @ObservedObject var model: StoryVoicesModel
    @State private var showRecording = false

    let storyTitle: String
    let storyText: String
    let language: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Voice picker — all approved voices
            voicePickerSection

            separator

            // Your recordings
            myRecordingsSection
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .fullScreenCover(isPresented: $showRecording) {
            VoiceRecordingView(
                storyTitle: storyTitle,
                storyText: storyText,
                storyWordCount: model.storyWordCount,
                storyId: model.storyId,
                attemptNumber: model.nextAttemptNumber,
                language: language,
                onDismiss: { submitted in
                    showRecording = false
                    if submitted {
                        Task { await model.load() }
                    }
                }
            )
        }
        .task {
            model.language = language
            await model.load()
        }
    }

    // MARK: - Voice Picker

    private var voicePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VOICES")
                .font(.ankyLabel(9, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.35))
                .kerning(1)

            if model.approvedVoices.isEmpty && model.storyVoice == nil {
                Text("no human voice yet — be the first to record this story")
                    .font(.ankyBody(13))
                    .foregroundStyle(Color.white.opacity(0.35))
            } else {
                VStack(spacing: 6) {
                    // Show the default TTS option
                    voiceRow(
                        icon: "waveform",
                        name: "Anky",
                        detail: "text-to-speech",
                        listens: nil,
                        isPlaying: false,
                        onTap: {}
                    )

                    // Show all approved human voices
                    ForEach(model.approvedVoices) { recording in
                        let isActive = model.isActiveRecording(recording.id)
                        let isPlaying = isActive && model.voicePlayerState == .playing

                        voiceRow(
                            icon: "person.wave.2",
                            name: recording.username ?? "anonymous",
                            detail: "\(recording.language ?? "?") · \(recording.durationLabel) · \(recording.listenCountLabel)",
                            listens: recording.fullListenCount,
                            isPlaying: isPlaying,
                            onTap: {
                                if let url = recording.audioUrl {
                                    model.togglePlayPause(audioUrl: url, recordingId: recording.id)
                                }
                            }
                        )
                    }

                    // Fallback: show storyVoice if no approved recordings match it
                    if model.approvedVoices.isEmpty, let voice = model.storyVoice {
                        let isActive = model.isActiveRecording(voice.recordingId)
                        let isPlaying = isActive && model.voicePlayerState == .playing

                        voiceRow(
                            icon: "person.wave.2",
                            name: voice.username ?? "anonymous",
                            detail: "\(voice.language) · \(formatDuration(voice.durationSeconds))",
                            listens: nil,
                            isPlaying: isPlaying,
                            onTap: {
                                model.togglePlayPause(audioUrl: voice.audioUrl, recordingId: voice.recordingId)
                            }
                        )
                    }
                }

                // Playback progress bar (visible when playing any voice)
                if model.voicePlayerState == .playing || model.voicePlayerState == .paused {
                    VStack(spacing: 4) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 3)
                                Capsule()
                                    .fill(Color.ankyGold.opacity(0.7))
                                    .frame(
                                        width: max(proxy.size.width * model.playbackProgress, 0),
                                        height: 3
                                    )
                            }
                        }
                        .frame(height: 3)

                        HStack {
                            Text(model.playbackElapsedLabel)
                                .font(.ankyMono(11))
                                .foregroundStyle(Color.white.opacity(0.35))
                            Spacer()
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func voiceRow(
        icon: String,
        name: String,
        detail: String,
        listens: Int?,
        isPlaying: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isPlaying ? Color.ankyGold : Color.white.opacity(0.5))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.ankyLabel(13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(isPlaying ? 0.95 : 0.7))

                    Text(detail)
                        .font(.ankyBody(11))
                        .foregroundStyle(Color.white.opacity(0.3))
                }

                Spacer()

                if isPlaying {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ankyGold)
                } else if icon == "person.wave.2" {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPlaying ? Color.ankyGold.opacity(0.08) : Color.white.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isPlaying ? Color.ankyGold.opacity(0.3) : Color.white.opacity(0.06),
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - My Recordings Section

    private var myRecordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR RECORDINGS")
                .font(.ankyLabel(9, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.35))
                .kerning(1)

            if model.myRecordings.isEmpty && !model.isLoading {
                Text("you haven't recorded this story yet")
                    .font(.ankyBody(13))
                    .foregroundStyle(Color.white.opacity(0.25))
            } else {
                VStack(spacing: 8) {
                    ForEach(model.myRecordings) { recording in
                        attemptCard(recording)
                    }
                }
            }

            if model.canRecord {
                Button {
                    showRecording = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14))
                        Text("record attempt \(model.nextAttemptNumber)")
                            .font(.ankyLabel(14, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            } else {
                Text("all 4 attempts used for this story")
                    .font(.ankyBody(12))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
    }

    // MARK: - Attempt Card

    private func attemptCard(_ recording: VoiceRecording) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor(recording.status))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("attempt \(recording.attemptNumber)")
                    .font(.ankyLabel(13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))

                HStack(spacing: 6) {
                    Text(recording.durationLabel)
                        .font(.ankyMono(11))
                        .foregroundStyle(Color.white.opacity(0.35))

                    if let lang = recording.language {
                        Text("·")
                            .foregroundStyle(Color.white.opacity(0.15))
                        Text(lang)
                            .font(.ankyBody(11))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }

                    if let count = recording.fullListenCount, count > 0 {
                        Text("·")
                            .foregroundStyle(Color.white.opacity(0.15))
                        Text(recording.listenCountLabel)
                            .font(.ankyBody(11))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }

                if recording.status == .rejected, let reason = recording.rejectionReason {
                    Text(reason)
                        .font(.ankyBody(10))
                        .foregroundStyle(Color(hex: "8b0000").opacity(0.7))
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(recording.statusLabel)
                .font(.ankyLabel(11, weight: .medium))
                .foregroundStyle(statusColor(recording.status))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(statusColor(recording.status).opacity(0.12))
                )

            if recording.status == .approved {
                ShareLink(
                    item: URL(string: "https://anky.lat/story/\(model.storyId)?recording=\(recording.id)")!
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ankyGold.opacity(0.7))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(recording.status == .approved ? 0.05 : 0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            recording.status == .approved
                                ? Color.ankyGold.opacity(0.3)
                                : Color.white.opacity(0.06),
                            lineWidth: recording.status == .approved ? 1 : 0.5
                        )
                )
        )
    }

    private func statusColor(_ status: VoiceRecordingStatus) -> Color {
        switch status {
        case .pending: return Color.white.opacity(0.4)
        case .approved: return Color.ankyGold
        case .rejected: return Color(hex: "8b0000")
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.5)
    }
}
