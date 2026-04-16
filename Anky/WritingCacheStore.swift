//
//  WritingCacheStore.swift
//  Anky
//

import Foundation

/// Legacy cache adapter kept for existing UI/tests while `LocalArchiveStore`
/// owns canonical archive persistence.
enum WritingCacheStore {
    static func load() -> [CachedWritingEntry] {
        LocalArchiveStore.load().map(\.legacyCachedWritingEntry)
    }

    static func save(_ entries: [CachedWritingEntry]) {
        LocalArchiveStore.save(entries.map(\.localArchiveRecord))
    }

    static func prepend(_ entry: CachedWritingEntry) -> [CachedWritingEntry] {
        LocalArchiveStore.prepend(entry.localArchiveRecord).map(\.legacyCachedWritingEntry)
    }

    static func mergeRemote(_ items: [WritingItem]) -> [CachedWritingEntry] {
        LocalArchiveStore.mergeRemote(items).map(\.legacyCachedWritingEntry)
    }

    static func migrateLegacyShortPendingWrites() -> [CachedWritingEntry] {
        LocalArchiveStore.migrateLegacyShortPendingWrites().map(\.legacyCachedWritingEntry)
    }

    static func updateResponse(for id: String, response: String) -> [CachedWritingEntry] {
        LocalArchiveStore.updateResponse(for: id, response: response).map(\.legacyCachedWritingEntry)
    }

    static func updateGeneratedArtifacts(
        for id: String,
        response: String? = nil,
        ankyTitle: String? = nil,
        ankyImagePath: String? = nil
    ) -> [CachedWritingEntry] {
        LocalArchiveStore.updateGeneratedArtifacts(
            for: id,
            reflection: response,
            ankyTitle: ankyTitle,
            ankyImagePath: ankyImagePath
        )
        .map(\.legacyCachedWritingEntry)
    }

    static func updateRetryArtifacts(
        for id: String,
        ankySessionString: String? = nil,
        ankyFilePath: String? = nil,
        sessionHash: String? = nil
    ) -> [CachedWritingEntry] {
        LocalArchiveStore.updateRetryArtifacts(
            for: id,
            ankySessionString: ankySessionString,
            ankyFilePath: ankyFilePath,
            sessionHash: sessionHash
        )
        .map(\.legacyCachedWritingEntry)
    }

    static func updateSyncState(
        for id: String,
        syncState: CachedWritingSyncState
    ) -> [CachedWritingEntry] {
        LocalArchiveStore.updateSyncStatus(
            for: id,
            syncStatus: syncState.canonicalSyncStatus
        )
        .map(\.legacyCachedWritingEntry)
    }

    static func clear() {
        LocalArchiveStore.clear()
    }

    static func mergedEntries(
        remoteItems: [WritingItem],
        existingEntries: [CachedWritingEntry]
    ) -> [CachedWritingEntry] {
        LocalArchiveStore.mergedRecords(
            remoteRecords: remoteItems.map(\.localArchiveRecord),
            existingRecords: existingEntries.map(\.localArchiveRecord)
        )
        .map(\.legacyCachedWritingEntry)
    }
}
