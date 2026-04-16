//
//  OfflineQueue.swift
//  Anky
//

import Foundation

struct PendingAction: Codable, Identifiable, Equatable {
    enum Method: String, Codable {
        case post = "POST"
        case delete = "DELETE"
    }

    let id: String
    let method: String
    let path: String
    let bodyData: Data?
    let createdAt: Date

    init(id: String = UUID().uuidString, method: Method, path: String, bodyData: Data?) {
        self.id = id
        self.method = method.rawValue
        self.path = path
        self.bodyData = bodyData
        self.createdAt = .now
    }
}

actor OfflineQueue {
    static let shared = OfflineQueue()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL

    init() {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = supportURL.appending(path: "Anky", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        self.fileURL = directory.appending(path: "pending-actions.json")
    }

    func enqueue(_ action: PendingAction) {
        var actions = load()
        actions.append(action)
        save(actions)
    }

    func processQueue(using api: AnkyAPI) async -> Int {
        let actions = load().filter { !$0.isObsoleteShortWrite }
        guard !actions.isEmpty else { return 0 }

        var remaining: [PendingAction] = []
        var processedCount = 0

        for action in actions {
            do {
                try await api.send(action)
                processedCount += 1
            } catch let error as AnkyError {
                if error == .unauthorized {
                    if let currentIndex = actions.firstIndex(where: { $0.id == action.id }) {
                        remaining.append(contentsOf: actions[currentIndex...])
                    }
                    break
                }
                remaining.append(action)
            } catch {
                remaining.append(action)
            }
        }

        save(remaining)
        return processedCount
    }

    func count() -> Int {
        load().count
    }

    func clear() {
        save([])
    }

    private func load() -> [PendingAction] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([PendingAction].self, from: data)) ?? []
    }

    private func save(_ actions: [PendingAction]) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        guard let data = try? encoder.encode(actions) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

extension PendingAction {
    nonisolated var isObsoleteShortWrite: Bool {
        guard path == "/write", method == Method.post.rawValue, let bodyData else {
            return false
        }

        guard let object = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            return false
        }

        guard let text = object["text"] as? String, let duration = object["duration"] as? Double else {
            return false
        }

        return !qualifiesForAnky(text: text, duration: duration)
    }

    nonisolated func qualifiesForAnky(text: String, duration: Double) -> Bool {
        AnkyContract.Qualification.qualifies(text: text, durationSeconds: duration)
    }

    nonisolated func wordCount(in text: String) -> Int {
        AnkyContract.Qualification.wordCount(in: text)
    }
}
