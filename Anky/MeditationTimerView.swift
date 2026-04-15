//
//  MeditationTimerView.swift
//  Anky
//

import AVFoundation
import Combine
import SwiftUI

struct MeditationTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var elapsed: TimeInterval = 0
    @State private var isPaused = false
    @State private var lastTick = Date()
    @State private var player: AVAudioPlayer?

    private let duration: TimeInterval = 480 // 8 minutes
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var remaining: TimeInterval {
        max(duration - elapsed, 0)
    }

    private var progress: Double {
        min(elapsed / duration, 1)
    }

    private var timeLabel: String {
        let total = max(Int(remaining), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text(timeLabel)
                    .font(.anky(72))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.1), value: timeLabel)

                Spacer()

                HStack(spacing: 40) {
                    Button {
                        isPaused.toggle()
                        lastTick = Date()
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .frame(width: 64, height: 64)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .frame(width: 52, height: 52)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 32)

                ChakraProgressBar(progress: progress)
                    .frame(height: 4)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            lastTick = Date()
            AnkyHaptics.timerStarted()
        }
        .onReceive(tick) { now in
            guard !isPaused else {
                lastTick = now
                return
            }
            let delta = min(max(now.timeIntervalSince(lastTick), 0), 0.25)
            lastTick = now
            elapsed += delta

            if elapsed >= duration {
                elapsed = duration
                playBellSound()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    dismiss()
                }
            }
        }
    }

    private func playBellSound() {
        guard let url = Bundle.main.url(forResource: "meditation-bell", withExtension: "mp3") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            // Silent fail — bell is nice-to-have
        }
    }
}
