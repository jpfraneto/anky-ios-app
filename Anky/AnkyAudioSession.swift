//
//  AnkyAudioSession.swift
//  Anky
//

import AVFoundation

enum AnkyAudioSession {
    static func configureIfNeeded() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session configuration failed: \(error)")
        }
    }
}
