//
//  FlowScoreCalculator.swift
//  Anky
//
//  Replicates calculate_flow_score from the backend (src/db/queries.rs).
//  Used for unsynced sessions where the backend hasn't scored yet.
//

import Foundation

enum FlowScoreCalculator {
    /// Calculate flow score from keystroke deltas and session metadata.
    /// Returns a value between 0.0 and 1.0.
    ///
    /// Components:
    /// - Rhythm consistency (30%): 1 - (stddev / mean) of keystroke deltas, clamped 0–1
    /// - Velocity WPM (25%): (wordCount / durationMinutes) / 60, clamped 0–1
    /// - Sustained attention (25%): penalize pauses > 3s. score = max(0, 1 - count * 0.05)
    /// - Duration bonus (20%): min(durationSeconds / 480, 1.0)
    static func calculate(
        keystrokeDeltas: [Double],
        wordCount: Int,
        durationSeconds: Double
    ) -> Double {
        // Rhythm consistency (30%)
        let rhythm: Double
        if keystrokeDeltas.count < 2 {
            rhythm = 0.5
        } else {
            let mean = keystrokeDeltas.reduce(0, +) / Double(keystrokeDeltas.count)
            if mean <= 0 {
                rhythm = 0
            } else {
                let variance = keystrokeDeltas.reduce(0) { $0 + pow($1 - mean, 2) } / Double(keystrokeDeltas.count)
                let stddev = sqrt(variance)
                let cv = stddev / mean
                rhythm = min(max(1 - cv, 0), 1)
            }
        }

        // Velocity WPM (25%)
        let velocity: Double
        if durationSeconds <= 0 {
            velocity = 0
        } else {
            let durationMinutes = durationSeconds / 60.0
            let wpm = Double(wordCount) / durationMinutes
            velocity = min(max(wpm / 60.0, 0), 1)
        }

        // Sustained attention (25%) — penalize pauses > 3000ms
        let longPauseCount = keystrokeDeltas.filter { $0 > 3000 }.count
        let attention = min(max(1.0 - Double(longPauseCount) * 0.05, 0), 1)

        // Duration bonus (20%)
        let duration = min(max(durationSeconds / 480.0, 0), 1)

        // Weighted sum
        let score = (rhythm * 0.30) + (velocity * 0.25) + (attention * 0.25) + (duration * 0.20)
        return min(max(score, 0), 1)
    }
}
