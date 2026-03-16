import Foundation

enum GuidanceCacheStore {
    private static let defaults = UserDefaults.standard
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static let meditationReadyKey = "anky.guidance.meditation.ready"
    private static let breathworkReadyKey = "anky.guidance.breathwork.ready"
    private static let breathworkSessionPrefix = "anky.guidance.breathwork.style."

    static func saveMeditationReady(_ response: ReadyResponse) {
        guard let data = try? encoder.encode(response) else { return }
        defaults.set(data, forKey: meditationReadyKey)
    }

    static func loadMeditationReady() -> ReadyResponse? {
        guard let data = defaults.data(forKey: meditationReadyKey) else { return nil }
        return try? decoder.decode(ReadyResponse.self, from: data)
    }

    static func saveBreathworkReady(_ response: ReadyResponse) {
        guard let data = try? encoder.encode(response) else { return }
        defaults.set(data, forKey: breathworkReadyKey)
    }

    static func loadBreathworkReady() -> ReadyResponse? {
        guard let data = defaults.data(forKey: breathworkReadyKey) else { return nil }
        return try? decoder.decode(ReadyResponse.self, from: data)
    }

    static func saveBreathworkSession(_ session: GuidanceSession, style: String) {
        guard let data = try? encoder.encode(session) else { return }
        defaults.set(data, forKey: breathworkSessionPrefix + style)
    }

    static func loadBreathworkSession(style: String) -> GuidanceSession? {
        guard let data = defaults.data(forKey: breathworkSessionPrefix + style) else { return nil }
        return try? decoder.decode(GuidanceSession.self, from: data)
    }
}
