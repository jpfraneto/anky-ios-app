import Foundation

enum SessionPhase: String, Codable {
    case idle
    case warming
    case flow
    case transcendent
    case broken
}

/// Legacy pre-session-bundle model shared with older surfaces.
struct AnkySession: Codable, Identifiable {
    var id: UUID = UUID()
    var startTime: Date = Date()
    var keystrokes: [AnkyKeystroke] = []
    var phase: SessionPhase = .idle
    var endTime: Date? = nil
    var formattedOutput: String? = nil

    var text: String {
        keystrokes.map { $0.character }.joined()
    }

    var duration: Double {
        guard let end = endTime else {
            return Date().timeIntervalSince(startTime)
        }
        return end.timeIntervalSince(startTime)
    }

    var rhythmSignature: [Double] {
        keystrokes.map { $0.delta }
    }

    func toRawStream() -> String {
        keystrokes.map { "\($0.character) \(String(format: "%.3f", $0.delta))" }.joined(separator: "\n")
    }
}
