//
//  AnkyThreadChatStore.swift
//  Anky
//
//  Per-anky chat threads. Each past anky has its own conversation history.
//

import Foundation

struct AnkyThreadMessage: Codable, Identifiable, Equatable {
    let id: String
    let role: String  // "user" or "anky"
    let text: String
    let timestamp: Date
}

final class AnkyThreadChatStore {
    static let shared = AnkyThreadChatStore()

    private let directory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("anky_thread_chats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var cache: [String: [AnkyThreadMessage]] = [:]

    func load(ankyId: String) -> [AnkyThreadMessage] {
        if let cached = cache[ankyId] { return cached }
        let url = fileURL(for: ankyId)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let messages = try decoder.decode([AnkyThreadMessage].self, from: data)
            cache[ankyId] = messages
            return messages
        } catch {
            return []
        }
    }

    func append(ankyId: String, message: AnkyThreadMessage) {
        var messages = load(ankyId: ankyId)
        messages.append(message)
        cache[ankyId] = messages
        save(ankyId: ankyId, messages: messages)
    }

    private func save(ankyId: String, messages: [AnkyThreadMessage]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(messages)
            try data.write(to: fileURL(for: ankyId), options: .atomic)
        } catch {}
    }

    private func fileURL(for ankyId: String) -> URL {
        let safeId = ankyId.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safeId).json")
    }
}
