//
//  BellPlayer.swift
//  Anky
//
//  Generates a meditation bell tone (432 Hz sine wave with exponential decay)
//  using AVAudioEngine — no audio file needed.
//

import AVFoundation

final class BellPlayer {
    static let shared = BellPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        try? engine.start()
    }

    /// Rings the bell once. Duration ~4 seconds, decays naturally.
    func ring() {
        let sampleRate: Double = 44_100
        let duration: Double = 4.0
        let frequency: Double = 432.0      // Hz — classic singing-bowl pitch
        let decayRate: Double = 3.0        // higher = faster fade

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let envelope = exp(-decayRate * t)
            let sample = Float(envelope * sin(2.0 * .pi * frequency * t))
            data[i] = sample * 0.8
        }

        // Re-start engine if something killed it (e.g. audio session interruption)
        if !engine.isRunning { try? engine.start() }

        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
