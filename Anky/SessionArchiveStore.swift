import Foundation
import Combine

class SessionArchiveStore: ObservableObject {
    @Published var sessions: [AnkySession] = []

    private let appGroupURL: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: AppGroup.suiteName
    )?.appendingPathComponent("sessions", isDirectory: true)

    func loadAll() {
        guard let dir = appGroupURL else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        sessions = jsonFiles.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(AnkySession.self, from: data)
        }.sorted { $0.startTime > $1.startTime }
    }

    func rawStream(for session: AnkySession) -> String? {
        guard let dir = appGroupURL else { return nil }
        let url = dir.appendingPathComponent("\(session.id.uuidString).txt")
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
