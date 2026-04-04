//
//  VoiceRecordingView.swift
//  Anky
//

import SwiftUI

struct VoiceRecordingView: View {
    let storyTitle: String
    let storyText: String
    let storyWordCount: Int
    let storyId: String
    let attemptNumber: Int
    let language: String
    let onDismiss: (Bool) -> Void

    @StateObject private var manager: VoiceRecordingManager
    @Environment(\.dismiss) private var dismiss

    init(
        storyTitle: String,
        storyText: String,
        storyWordCount: Int,
        storyId: String,
        attemptNumber: Int,
        language: String,
        onDismiss: @escaping (Bool) -> Void
    ) {
        self.storyTitle = storyTitle
        self.storyText = storyText
        self.storyWordCount = storyWordCount
        self.storyId = storyId
        self.attemptNumber = attemptNumber
        self.language = language
        self.onDismiss = onDismiss
        _manager = StateObject(wrappedValue: VoiceRecordingManager(
            storyId: storyId,
            storyWordCount: storyWordCount,
            attemptNumber: attemptNumber,
            language: language
        ))
    }

    var body: some View {
        ZStack {
            Color.ankyVoid.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                scrollableStoryText
                Spacer(minLength: 16)
                waveformSection
                controlsSection
            }

            if let error = manager.error {
                errorBanner(error)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            manager.requestPermissionAndPrepare()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                manager.stopPlayback()
                onDismiss(manager.state == .submitted)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("record your voice")
                    .font(.ankyLabel(13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text("attempt \(attemptNumber)")
                    .font(.ankyMono(11))
                    .foregroundStyle(Color.white.opacity(0.3))
            }

            Spacer()

            // Balance spacer
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 12)
    }

    // MARK: - Story Text

    private var scrollableStoryText: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text(storyTitle)
                    .font(.custom("Georgia", size: 18))
                    .foregroundStyle(Color.white.opacity(0.9))

                Text(storyText)
                    .font(.custom("Georgia", size: 15))
                    .lineSpacing(8)
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.4)
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
            }
        )
    }

    // MARK: - Waveform

    private var waveformSection: some View {
        VStack(spacing: 8) {
            if manager.state == .recording || manager.state == .recorded || manager.state == .playing {
                LiveWaveformView(
                    samples: manager.waveformSamples,
                    isRecording: manager.state == .recording,
                    playbackProgress: manager.state == .playing ? manager.playbackProgress : nil
                )
                .frame(height: 64)
                .padding(.horizontal, 24)
            } else {
                // Placeholder waveform
                HStack(spacing: 2) {
                    ForEach(0..<40, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 3, height: CGFloat.random(in: 4...24))
                    }
                }
                .frame(height: 64)
            }

            // Timer
            HStack {
                Text(manager.elapsedLabel)
                    .font(.ankyMono(24))
                    .foregroundStyle(timerColor)

                Spacer()

                Text("max \(manager.maxDurationLabel)")
                    .font(.ankyMono(12))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 16)
    }

    private var timerColor: Color {
        switch manager.state {
        case .recording: return Color.white.opacity(0.9)
        case .recorded where manager.durationTooShort: return Color(hex: "8b0000")
        default: return Color.white.opacity(0.5)
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 16) {
            switch manager.state {
            case .idle:
                recordButton
                Text("tap to begin reading")
                    .font(.ankyBody(13))
                    .foregroundStyle(Color.white.opacity(0.3))

            case .recording:
                stopButton
                Text("reading...")
                    .font(.ankyBody(13))
                    .foregroundStyle(Color.white.opacity(0.3))

            case .recorded:
                if manager.durationTooShort {
                    Text("too short — read the full story")
                        .font(.ankyBody(13))
                        .foregroundStyle(Color(hex: "8b0000").opacity(0.8))
                    retryButton
                } else if manager.isRecordingValid {
                    HStack(spacing: 24) {
                        // Play/stop preview
                        Button {
                            manager.playRecording()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .frame(width: 48, height: 48)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)

                        // Submit
                        submitButton

                        // Retry
                        retryButton
                    }
                } else {
                    retryButton
                }

            case .playing:
                HStack(spacing: 24) {
                    Button {
                        manager.stopPlayback()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .frame(width: 48, height: 48)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)

                    submitButton
                }

            case .uploading:
                ProgressView()
                    .tint(.white)
                Text("submitting to anky...")
                    .font(.ankyBody(13))
                    .foregroundStyle(Color.white.opacity(0.4))

            case .submitted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.ankyGold)
                Text("your voice has been offered")
                    .font(.ankyBody(15))
                    .foregroundStyle(Color.white.opacity(0.7))
                Button {
                    onDismiss(true)
                } label: {
                    Text("return")
                        .font(.ankyLabel(14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .padding(.bottom, 48)
        .animation(.easeInOut(duration: 0.3), value: manager.state)
    }

    private var recordButton: some View {
        Button {
            manager.startRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: "8b0000").opacity(0.15))
                    .frame(width: 88, height: 88)

                Circle()
                    .fill(Color(hex: "cc2222"))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )

                Image(systemName: "mic.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.white)
            }
        }
        .buttonStyle(.plain)
    }

    private var stopButton: some View {
        Button {
            manager.stopRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: "8b0000").opacity(0.15))
                    .frame(width: 88, height: 88)

                Circle()
                    .fill(Color(hex: "cc2222"))
                    .frame(width: 64, height: 64)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
            }
        }
        .buttonStyle(.plain)
    }

    private var submitButton: some View {
        Button {
            Task { await manager.submitRecording() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                Text("submit to anky")
                    .font(.ankyLabel(14, weight: .medium))
            }
            .foregroundStyle(Color.ankyVoid)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color.ankyGold)
            )
        }
        .buttonStyle(.plain)
    }

    private var retryButton: some View {
        Button {
            manager.discardAndRetry()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack {
            HStack {
                Text(message)
                    .font(.ankyBody(13))
                    .foregroundStyle(Color.white.opacity(0.9))
                Spacer()
                Button {
                    manager.error = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "8b0000").opacity(0.9))
            )
            .padding(.horizontal, 20)
            .padding(.top, 60)

            Spacer()
        }
    }
}

// MARK: - Live Waveform

struct LiveWaveformView: View {
    let samples: [Float]
    let isRecording: Bool
    let playbackProgress: Double?

    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxBars = 60

    var body: some View {
        GeometryReader { proxy in
            let availableBars = Int(proxy.size.width / (barWidth + barSpacing))
            let barsToShow = min(availableBars, maxBars)
            let displaySamples = resample(to: barsToShow)

            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(Array(displaySamples.enumerated()), id: \.offset) { index, sample in
                    let height = max(CGFloat(sample) * proxy.size.height, 2)
                    let progress = Double(index) / max(Double(displaySamples.count - 1), 1)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(progress: progress))
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func barColor(progress: Double) -> Color {
        if let playbackProgress, progress <= playbackProgress {
            return Color.ankyGold.opacity(0.8)
        }
        if isRecording {
            let opacity = 0.2 + progress * 0.6
            return Color.white.opacity(opacity)
        }
        return Color.white.opacity(0.25)
    }

    private func resample(to count: Int) -> [Float] {
        guard !samples.isEmpty, count > 0 else {
            return Array(repeating: 0.05, count: count)
        }

        if samples.count <= count {
            var result = samples
            while result.count < count {
                result.insert(0.05, at: 0)
            }
            return result
        }

        let stride = Float(samples.count) / Float(count)
        var result: [Float] = []
        for i in 0..<count {
            let start = Int(Float(i) * stride)
            let end = min(Int(Float(i + 1) * stride), samples.count)
            let slice = samples[start..<end]
            let avg = slice.reduce(0, +) / max(Float(slice.count), 1)
            result.append(avg)
        }
        return result
    }
}
