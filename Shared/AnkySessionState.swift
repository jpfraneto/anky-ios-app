import Foundation

/// Legacy shared session-state snapshot from the pre-session-bundle model.
struct AnkySessionState: Codable {
    var isActive: Bool = false
    var phase: SessionPhase = .idle
    var streakSeconds: Double = 0
    var totalDuration: Double = 0
    var keystrokeCount: Int = 0
    var sessionID: UUID? = nil
    var isExternalApp: Bool = false
    var pendingFormattedText: String? = nil
}
