//
//  WritingCacheStore.swift
//  Anky
//

import Foundation

enum WritingCacheStore {
    private static let cacheKey = "anky.cached.writings"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func load() -> [CachedWritingEntry] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return [] }
        return (try? decoder.decode([CachedWritingEntry].self, from: data)) ?? []
    }

    static func save(_ entries: [CachedWritingEntry]) {
        guard let data = try? encoder.encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    static func prepend(_ entry: CachedWritingEntry) -> [CachedWritingEntry] {
        var entries = load().filter { $0.id != entry.id }
        entries.insert(entry, at: 0)
        save(entries)
        return entries
    }

    static func mergeRemote(_ items: [WritingItem]) -> [CachedWritingEntry] {
        let remoteEntries = items.map { CachedWritingEntry(item: $0) }
        let localUnsynced = load().filter { $0.syncState != .synced }
        let remoteIDs = Set(remoteEntries.map { $0.id })
        let merged = remoteEntries + localUnsynced.filter { !remoteIDs.contains($0.id) }
        let sorted = merged.sorted { $0.createdAt > $1.createdAt }
        save(sorted)
        return sorted
    }

    static func migrateLegacyShortPendingWrites() -> [CachedWritingEntry] {
        let migrated = load().map { entry in
            guard entry.syncState == .pending else { return entry }
            guard !LocalWritingCapture.qualifiesForAnky(text: entry.content, duration: entry.durationSeconds) else {
                return entry
            }

            return CachedWritingEntry(
                id: entry.id,
                prompt: entry.prompt,
                content: entry.content,
                durationSeconds: entry.durationSeconds,
                wordCount: entry.wordCount,
                isAnky: false,
                response: entry.response,
                ankyId: entry.ankyId,
                ankyTitle: entry.ankyTitle,
                ankyImagePath: entry.ankyImagePath,
                createdAt: entry.createdAt,
                flowScore: entry.flowScore,
                syncState: .localOnly
            )
        }

        save(migrated)
        return migrated
    }

    static func updateResponse(for id: String, response: String) -> [CachedWritingEntry] {
        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResponse.isEmpty else { return load() }

        let updated = load().map { entry in
            guard entry.id == id else { return entry }
            return CachedWritingEntry(
                id: entry.id,
                prompt: entry.prompt,
                content: entry.content,
                durationSeconds: entry.durationSeconds,
                wordCount: entry.wordCount,
                isAnky: entry.isAnky,
                response: trimmedResponse,
                ankyId: entry.ankyId,
                ankyTitle: entry.ankyTitle,
                ankyImagePath: entry.ankyImagePath,
                createdAt: entry.createdAt,
                flowScore: entry.flowScore,
                syncState: entry.syncState
            )
        }

        save(updated)
        return updated
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
