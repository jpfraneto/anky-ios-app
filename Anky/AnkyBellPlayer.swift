//
//  AnkyBellPlayer.swift
//  Anky
//
//  Plays the anky bell at writing session boundaries.
//

import AVFoundation

final class AnkyBellPlayer {
    static let shared = AnkyBellPlayer()
    private var player: AVAudioPlayer?

    private init() {}

    func play() {
        guard let url = Bundle.main.url(forResource: "anky_bell", withExtension: "wav") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            // Bell is nice-to-have, silent fail
        }
    }
}
