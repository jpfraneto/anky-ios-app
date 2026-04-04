//
//  VoiceRecordingManager.swift
//  Anky
//

import AVFoundation
import Combine
import SwiftUI

@MainActor
final class VoiceRecordingManager: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case recorded
        case playing
        case uploading
        case submitted
    }

    @Published var state: State = .idle
    @Published var elapsedSeconds: Double = 0
    @Published var waveformSamples: [Float] = []
    @Published var playbackProgress: Double = 0
    @Published var error: String?

    let storyId: String
    let storyWordCount: Int
    let attemptNumber: Int
    let language: String

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var displayLink: CADisplayLink?
    private var recordingURL: URL?
    private var tickTimer: Timer?
    private var recordingStartedAt: Date?
    private var playbackTimer: Timer?

    var maxDuration: Double {
        Double(storyWordCount) / 2.5 + 30
    }

    var minDuration: Double {
        Double(storyWordCount) / 5.0
    }

    var recordedDuration: Double {
        elapsedSeconds
    }

    var isRecordingValid: Bool {
        elapsedSeconds >= minDuration && elapsedSeconds <= maxDuration
    }

    var durationTooShort: Bool {
        elapsedSeconds > 0 && elapsedSeconds < minDuration
    }

    var elapsedLabel: String {
        let total = max(Int(elapsedSeconds), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var maxDurationLabel: String {
        let total = max(Int(maxDuration), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    init(storyId: String, storyWordCount: Int, attemptNumber: Int, language: String) {
        self.storyId = storyId
        self.storyWordCount = storyWordCount
        self.attemptNumber = attemptNumber
        self.language = language
    }

    func requestPermissionAndPrepare() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard granted else {
                    self?.error = "Microphone access is required to record your voice."
                    return
                }
                self?.prepareRecorder()
            }
        }
    }

    func startRecording() {
        guard state == .idle else { return }
        prepareRecorder()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            self.error = "Could not configure audio session."
            return
        }

        guard let recorder else {
            self.error = "Recorder not ready."
            return
        }

        recorder.isMeteringEnabled = true
        recorder.record()
        recordingStartedAt = .now
        state = .recording
        elapsedSeconds = 0
        waveformSamples = []

        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func stopRecording() {
        guard state == .recording else { return }
        recorder?.stop()
        tickTimer?.invalidate()
        tickTimer = nil
        state = .recorded
    }

    func playRecording() {
        guard state == .recorded, let url = recordingURL else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            state = .playing
            playbackProgress = 0

            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let player = self.player else { return }
                    if player.isPlaying {
                        self.playbackProgress = player.currentTime / max(player.duration, 1)
                    } else {
                        self.playbackTimer?.invalidate()
                        self.playbackTimer = nil
                        self.playbackProgress = 0
                        self.state = .recorded
                    }
                }
            }
        } catch {
            self.error = "Could not play recording."
        }
    }

    func stopPlayback() {
        player?.stop()
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackProgress = 0
        state = .recorded
    }

    func submitRecording() async {
        guard state == .recorded, let url = recordingURL else { return }

        state = .uploading

        do {
            let audioData = try Data(contentsOf: url)

            // Step 1: Create recording via multipart POST, get presigned R2 URL
            let response = try await AnkyAPI.shared.createRecording(
                storyId: storyId,
                audioData: audioData,
                language: language,
                durationSeconds: elapsedSeconds
            )

            // Step 2: PUT raw audio to presigned R2 URL for permanent storage
            try await AnkyAPI.shared.uploadAudioToR2(
                uploadUrl: response.uploadUrl,
                audioData: audioData
            )

            state = .submitted
        } catch {
            self.error = "Upload failed: \(error.localizedDescription)"
            state = .recorded
        }
    }

    func discardAndRetry() {
        player?.stop()
        playbackTimer?.invalidate()
        playbackTimer = nil
        recorder = nil
        player = nil
        elapsedSeconds = 0
        waveformSamples = []
        playbackProgress = 0
        state = .idle
    }

    private func prepareRecorder() {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("anky-voice-\(UUID().uuidString).m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.prepareToRecord()
    }

    private func tick() {
        guard state == .recording, let recorder, recorder.isRecording else { return }

        if let start = recordingStartedAt {
            elapsedSeconds = Date().timeIntervalSince(start)
        }

        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        // Normalize: -160..0 dB → 0..1
        let normalized = max(0, min(1, (power + 50) / 50))
        waveformSamples.append(normalized)

        // Auto-stop at max duration
        if elapsedSeconds >= maxDuration {
            stopRecording()
        }
    }
}
