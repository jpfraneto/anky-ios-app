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
    case ankyImage(url: String)
    case writingSession(preview: String, wordCount: Int, flowScore: Int, duration: Double)
}

struct ChatArchiveDay: Identifiable, Equatable {
    let dayKey: String
    let messages: [PersistedMessage]

    var id: String { dayKey }

    var date: Date? {
        ChatStore.utcDayFormatter.date(from: dayKey)
    }

    var sessionCount: Int {
        messages.filter { $0.duration != nil }.count
    }
}

final class ChatStore {
    static let shared = ChatStore()
    private static let lastSessionStartKey = "anky.chat.last-session-start"
    static let utcDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("anky_chat_thread.json")
    }()

    private var cache: [PersistedMessage]?

    func load() -> [PersistedMessage] {
        messages(forDayKey: Self.currentUTCKey())
    }

    func loadArchivedDays(includeCurrentDay: Bool = false) -> [ChatArchiveDay] {
        let currentDayKey = Self.currentUTCKey()
        let grouped = Dictionary(grouping: loadAll(), by: { Self.utcDayKey(for: $0.timestamp) })

        return grouped
            .filter { includeCurrentDay || $0.key != currentDayKey }
            .map { key, messages in
                ChatArchiveDay(
                    dayKey: key,
                    messages: messages.sorted { $0.timestamp < $1.timestamp }
                )
            }
            .sorted { $0.dayKey > $1.dayKey }
    }

    func hasAnyHistory() -> Bool {
        !loadAll().isEmpty
    }

    func recordSessionStart(at date: Date = .now) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.lastSessionStartKey)
    }

    func lastSessionStartDate() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: Self.lastSessionStartKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    func needsUTCReset(referenceDate: Date = .now) -> Bool {
        guard let lastSessionStart = lastSessionStartDate() else { return false }
        return Self.utcDayKey(for: lastSessionStart) != Self.utcDayKey(for: referenceDate)
    }

    func messages(forDayKey dayKey: String) -> [PersistedMessage] {
        loadAll()
            .filter { Self.utcDayKey(for: $0.timestamp) == dayKey }
            .sorted { $0.timestamp < $1.timestamp }
    }

    static func currentUTCKey(referenceDate: Date = .now) -> String {
        utcDayKey(for: referenceDate)
    }

    static func utcDayKey(for date: Date) -> String {
        utcDayFormatter.string(from: date)
    }

    private func loadAll() -> [PersistedMessage] {
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
        var all = loadAll()
        all.append(message)
        cache = all
        save(all)
    }

    func appendAll(_ messages: [PersistedMessage]) {
        guard !messages.isEmpty else { return }
        var all = loadAll()
        all.append(contentsOf: messages)
        cache = all
        save(all)
    }

    /// Current session tag — changes each app launch
    static let currentSessionTag: String = UUID().uuidString

    func clearAll() {
        cache = []
        save([])
        UserDefaults.standard.removeObject(forKey: Self.lastSessionStartKey)
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
