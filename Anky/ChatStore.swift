//
//  ChatStore.swift
//  Anky
//
//  Persists the conversation thread between Anky and the user.
//  One long, growing thread. Previous sessions load dimmed.
//

import Foundation

struct PersistedMessage: Codable, Identifiable, Equatable {
    let id: String
    let kind: PersistedMessageKind
    let timestamp: Date
    let sessionTag: String  // groups messages into sessions
    var duration: TimeInterval?  // writing session duration (seconds)

    static func == (lhs: PersistedMessage, rhs: PersistedMessage) -> Bool {
        lhs.id == rhs.id
    }
}

enum PersistedMessageKind: Codable, Equatable {
    case anky(text: String)
    case user(text: String)
    case writingSession(preview: String, wordCount: Int, flowScore: Int, duration: Double)
}

final class ChatStore {
    static let shared = ChatStore()

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("anky_chat_thread.json")
    }()

    private var cache: [PersistedMessage]?

    func load() -> [PersistedMessage] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = []
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let messages = try decoder.decode([PersistedMessage].self, from: data)
            cache = messages
            return messages
        } catch {
            cache = []
            return []
        }
    }

    func append(_ message: PersistedMessage) {
        var all = load()
        all.append(message)
        cache = all
        save(all)
    }

    func appendAll(_ messages: [PersistedMessage]) {
        guard !messages.isEmpty else { return }
        var all = load()
        all.append(contentsOf: messages)
        cache = all
        save(all)
    }

    /// Current session tag — changes each app launch
    static let currentSessionTag: String = UUID().uuidString

    func clearAll() {
        cache = []
        save([])
    }

    private func save(_ messages: [PersistedMessage]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(messages)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silent failure — chat is not critical data
        }
    }
}
