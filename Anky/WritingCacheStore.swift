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
        let merged = mergedEntries(remoteItems: items, existingEntries: load())
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
                syncState: .localOnly,
                kingdom: entry.kingdom,
                energy: entry.energy,
                reason: entry.reason,
                ankySessionString: entry.ankySessionString,
                ankyFilePath: entry.ankyFilePath,
                sessionHash: entry.sessionHash
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
                syncState: entry.syncState,
                kingdom: entry.kingdom,
                energy: entry.energy,
                reason: entry.reason,
                ankySessionString: entry.ankySessionString,
                ankyFilePath: entry.ankyFilePath,
                sessionHash: entry.sessionHash
            )
        }

        save(updated)
        return updated
    }

    static func updateGeneratedArtifacts(
        for id: String,
        response: String? = nil,
        ankyTitle: String? = nil,
        ankyImagePath: String? = nil
    ) -> [CachedWritingEntry] {
        let trimmedResponse = response?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = ankyTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedImagePath = ankyImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)

        let updated = load().map { entry in
            guard entry.id == id else { return entry }
            return CachedWritingEntry(
                id: entry.id,
                prompt: entry.prompt,
                content: entry.content,
                durationSeconds: entry.durationSeconds,
                wordCount: entry.wordCount,
                isAnky: entry.isAnky,
                response: (trimmedResponse?.isEmpty == false ? trimmedResponse : nil) ?? entry.response,
                ankyId: entry.ankyId,
                ankyTitle: (trimmedTitle?.isEmpty == false ? trimmedTitle : nil) ?? entry.ankyTitle,
                ankyImagePath: (trimmedImagePath?.isEmpty == false ? trimmedImagePath : nil) ?? entry.ankyImagePath,
                createdAt: entry.createdAt,
                flowScore: entry.flowScore,
                syncState: entry.syncState,
                kingdom: entry.kingdom,
                energy: entry.energy,
                reason: entry.reason,
                ankySessionString: entry.ankySessionString,
                ankyFilePath: entry.ankyFilePath,
                sessionHash: entry.sessionHash
            )
        }

        save(updated)
        return updated
    }

    static func updateRetryArtifacts(
        for id: String,
        ankySessionString: String? = nil,
        ankyFilePath: String? = nil,
        sessionHash: String? = nil
    ) -> [CachedWritingEntry] {
        let trimmedSessionString = ankySessionString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFilePath = ankyFilePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSessionHash = sessionHash?.trimmingCharacters(in: .whitespacesAndNewlines)

        let updated = load().map { entry in
            guard entry.id == id else { return entry }
            return CachedWritingEntry(
                id: entry.id,
                prompt: entry.prompt,
                content: entry.content,
                durationSeconds: entry.durationSeconds,
                wordCount: entry.wordCount,
                isAnky: entry.isAnky,
                response: entry.response,
                ankyId: entry.ankyId,
                ankyTitle: entry.ankyTitle,
                ankyImagePath: entry.ankyImagePath,
                createdAt: entry.createdAt,
                flowScore: entry.flowScore,
                syncState: entry.syncState,
                kingdom: entry.kingdom,
                energy: entry.energy,
                reason: entry.reason,
                ankySessionString: (trimmedSessionString?.isEmpty == false ? trimmedSessionString : nil) ?? entry.ankySessionString,
                ankyFilePath: (trimmedFilePath?.isEmpty == false ? trimmedFilePath : nil) ?? entry.ankyFilePath,
                sessionHash: (trimmedSessionHash?.isEmpty == false ? trimmedSessionHash : nil) ?? entry.sessionHash
            )
        }

        save(updated)
        return updated
    }

    static func updateSyncState(for id: String, syncState: CachedWritingSyncState) -> [CachedWritingEntry] {
        let updated = load().map { entry in
            guard entry.id == id else { return entry }
            return CachedWritingEntry(
                id: entry.id,
                prompt: entry.prompt,
                content: entry.content,
                durationSeconds: entry.durationSeconds,
                wordCount: entry.wordCount,
                isAnky: entry.isAnky,
                response: entry.response,
                ankyId: entry.ankyId,
                ankyTitle: entry.ankyTitle,
                ankyImagePath: entry.ankyImagePath,
                createdAt: entry.createdAt,
                flowScore: entry.flowScore,
                syncState: syncState,
                kingdom: entry.kingdom,
                energy: entry.energy,
                reason: entry.reason,
                ankySessionString: entry.ankySessionString,
                ankyFilePath: entry.ankyFilePath,
                sessionHash: entry.sessionHash
            )
        }

        save(updated)
        return updated
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    static func mergedEntries(
        remoteItems: [WritingItem],
        existingEntries: [CachedWritingEntry]
    ) -> [CachedWritingEntry] {
        var merged: [CachedWritingEntry] = remoteItems.map { CachedWritingEntry(item: $0) }

        for localEntry in existingEntries {
            if let index = merged.firstIndex(where: { representsSameWriting($0, localEntry) }) {
                merged[index] = merge(remote: merged[index], local: localEntry)
            } else {
                merged.append(localEntry)
            }
        }

        return merged
    }

    private static func representsSameWriting(_ lhs: CachedWritingEntry, _ rhs: CachedWritingEntry) -> Bool {
        if lhs.id == rhs.id {
            return true
        }

        if let lhsAnkyID = lhs.ankyId,
           let rhsAnkyID = rhs.ankyId,
           lhsAnkyID == rhsAnkyID {
            return true
        }

        guard !lhs.content.isEmpty, lhs.content == rhs.content else {
            return false
        }

        let createdAtDelta = abs(lhs.createdAt.timeIntervalSince(rhs.createdAt))
        let durationDelta = abs(lhs.durationSeconds - rhs.durationSeconds)
        return createdAtDelta < 600 && durationDelta < 5
    }

    private static func merge(remote: CachedWritingEntry, local: CachedWritingEntry) -> CachedWritingEntry {
        CachedWritingEntry(
            id: local.id,
            prompt: local.prompt.isEmpty ? remote.prompt : local.prompt,
            content: local.content.isEmpty ? remote.content : local.content,
            durationSeconds: max(remote.durationSeconds, local.durationSeconds),
            wordCount: max(remote.wordCount, local.wordCount),
            isAnky: remote.isAnky || local.isAnky,
            response: remote.response ?? local.response,
            ankyId: remote.ankyId ?? local.ankyId,
            ankyTitle: remote.ankyTitle ?? local.ankyTitle,
            ankyImagePath: remote.ankyImagePath ?? local.ankyImagePath,
            createdAt: local.createdAt,
            flowScore: remote.flowScore ?? local.flowScore,
            syncState: .synced,
            kingdom: remote.kingdom ?? local.kingdom,
            energy: remote.energy ?? local.energy,
            reason: remote.reason ?? local.reason,
            ankySessionString: local.ankySessionString ?? remote.ankySessionString,
            ankyFilePath: local.ankyFilePath ?? remote.ankyFilePath,
            sessionHash: local.sessionHash ?? remote.sessionHash
        )
    }
}
