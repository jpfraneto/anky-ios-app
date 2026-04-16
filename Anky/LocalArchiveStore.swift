//
//  LocalArchiveStore.swift
//  Anky
//

import Foundation

/// Canonical local archive persistence for the session-bundle era.
/// Legacy cache/history models adapt to this store instead of owning it.
enum LocalArchiveStore {
    private static let archiveKey = "anky.local.archive.records.v1"
    private static let legacyCacheKey = "anky.cached.writings"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func load() -> [LocalArchiveRecord] {
        guard let data = UserDefaults.standard.data(forKey: archiveKey) else {
            let migrated = loadLegacyEntries().map(\.localArchiveRecord)
            if !migrated.isEmpty {
                save(migrated)
            }
            return sorted(migrated)
        }

        guard let records = try? decoder.decode([LocalArchiveRecord].self, from: data) else {
            let migrated = loadLegacyEntries().map(\.localArchiveRecord)
            if !migrated.isEmpty {
                save(migrated)
            }
            return sorted(migrated)
        }

        return sorted(records)
    }

    static func save(_ records: [LocalArchiveRecord]) {
        let sortedRecords = sorted(records)

        guard let archiveData = try? encoder.encode(sortedRecords) else { return }
        UserDefaults.standard.set(archiveData, forKey: archiveKey)

        guard let legacyData = try? encoder.encode(sortedRecords.map(\.legacyCachedWritingEntry)) else { return }
        UserDefaults.standard.set(legacyData, forKey: legacyCacheKey)
    }

    static func prepend(_ record: LocalArchiveRecord) -> [LocalArchiveRecord] {
        var records = load().filter { $0.id != record.id }
        records.insert(record, at: 0)
        save(records)
        return sorted(records)
    }

    static func mergeRemote(_ items: [WritingItem]) -> [LocalArchiveRecord] {
        let merged = mergedRecords(
            remoteRecords: items.map(\.localArchiveRecord),
            existingRecords: load()
        )
        save(merged)
        return sorted(merged)
    }

    static func migrateLegacyShortPendingWrites() -> [LocalArchiveRecord] {
        let migrated = load().map { record in
            guard record.sessionBundle.syncStatus == .pending else { return record }
            guard !record.sessionBundle.qualifiesForCanonicalAnky else { return record }
            return record
                .updatingSyncStatus(.localOnly, updatedAt: record.lastUpdatedAt)
                .updating(lastUpdatedAt: record.lastUpdatedAt, isAnky: false)
        }

        save(migrated)
        return sorted(migrated)
    }

    static func updateResponse(for id: String, response: String) -> [LocalArchiveRecord] {
        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResponse.isEmpty else { return load() }

        return updateRecord(for: id) { record in
            record.applyingArtifacts(
                reflection: trimmedResponse,
                updatedAt: .now
            )
        }
    }

    static func updateGeneratedArtifacts(
        for id: String,
        reflection: String? = nil,
        ankyTitle: String? = nil,
        ankyImagePath: String? = nil
    ) -> [LocalArchiveRecord] {
        let trimmedReflection = reflection?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = ankyTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedImagePath = ankyImagePath?.trimmingCharacters(in: .whitespacesAndNewlines)

        return updateRecord(for: id) { record in
            record.applyingArtifacts(
                title3Words: trimmedTitle?.isEmpty == false ? trimmedTitle : nil,
                reflection: trimmedReflection?.isEmpty == false ? trimmedReflection : nil,
                imageLocator: trimmedImagePath?.isEmpty == false ? trimmedImagePath : nil,
                updatedAt: .now
            )
        }
    }

    static func updateRetryArtifacts(
        for id: String,
        ankySessionString: String? = nil,
        ankyFilePath: String? = nil,
        sessionHash: String? = nil
    ) -> [LocalArchiveRecord] {
        let trimmedSessionString = ankySessionString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFilePath = ankyFilePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSessionHash = sessionHash?.trimmingCharacters(in: .whitespacesAndNewlines)

        return updateRecord(for: id) { record in
            let proofMetadata: AnkyProofMetadata?
            if let resolvedSessionHash = trimmedSessionHash ?? record.sessionBundle.sessionHash {
                proofMetadata = AnkyProofMetadata(
                    sessionHash: resolvedSessionHash,
                    source: .localRetry,
                    verificationStatus: .pending
                )
            } else {
                proofMetadata = record.sessionBundle.proofMetadata
            }

            return record.updatingLocalBundlePayload(
                canonicalSessionString: trimmedSessionString?.isEmpty == false ? trimmedSessionString : nil,
                canonicalSessionFilePath: trimmedFilePath?.isEmpty == false ? trimmedFilePath : nil,
                sessionHash: trimmedSessionHash?.isEmpty == false ? trimmedSessionHash : nil,
                proofMetadata: proofMetadata,
                updatedAt: .now
            )
        }
    }

    static func updateSyncStatus(
        for id: String,
        syncStatus: AnkySessionBundle.SyncStatus
    ) -> [LocalArchiveRecord] {
        updateRecord(for: id) { record in
            record.updatingSyncStatus(syncStatus, updatedAt: .now)
        }
    }

    static func updateAcceptedSubmission(
        for id: String,
        backendAnkyId: String
    ) -> [LocalArchiveRecord] {
        updateRecord(for: id) { record in
            record
                .updating(
                    backendAnkyId: backendAnkyId,
                    lastUpdatedAt: .now
                )
                .reconcilingCanonicalSyncStatus(updatedAt: .now)
        }
    }

    static func applyCanonicalProcessorStatus(
        for id: String? = nil,
        sessionHash: String,
        response: CanonicalProcessorStatusResponse
    ) -> [LocalArchiveRecord] {
        updateRecord(matching: { record in
            matches(record: record, id: id, sessionHash: sessionHash)
        }) { record in
            record.applyingCanonicalProcessorStatus(response)
        }
    }

    static func applyCanonicalProofReadback(
        for id: String? = nil,
        sessionHash: String,
        response: CanonicalProofResponse
    ) -> [LocalArchiveRecord] {
        updateRecord(matching: { record in
            matches(record: record, id: id, sessionHash: sessionHash)
        }) { record in
            record.applyingCanonicalProofReadback(response)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: archiveKey)
        UserDefaults.standard.removeObject(forKey: legacyCacheKey)
    }

    static func mergedRecords(
        remoteRecords: [LocalArchiveRecord],
        existingRecords: [LocalArchiveRecord]
    ) -> [LocalArchiveRecord] {
        var merged = remoteRecords

        for localRecord in existingRecords {
            if let index = merged.firstIndex(where: { representsSameArchive($0, localRecord) }) {
                merged[index] = merge(remote: merged[index], local: localRecord)
            } else {
                merged.append(localRecord)
            }
        }

        return sorted(merged)
    }

    private static func updateRecord(
        for id: String,
        transform: (LocalArchiveRecord) -> LocalArchiveRecord
    ) -> [LocalArchiveRecord] {
        updateRecord(matching: { $0.id == id }, transform: transform)
    }

    private static func updateRecord(
        matching predicate: (LocalArchiveRecord) -> Bool,
        transform: (LocalArchiveRecord) -> LocalArchiveRecord
    ) -> [LocalArchiveRecord] {
        let updated = load().map { record in
            guard predicate(record) else { return record }
            return transform(record)
        }

        save(updated)
        return sorted(updated)
    }

    private static func sorted(_ records: [LocalArchiveRecord]) -> [LocalArchiveRecord] {
        records.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func loadLegacyEntries() -> [CachedWritingEntry] {
        guard let data = UserDefaults.standard.data(forKey: legacyCacheKey) else { return [] }
        return (try? decoder.decode([CachedWritingEntry].self, from: data)) ?? []
    }

    private static func representsSameArchive(_ lhs: LocalArchiveRecord, _ rhs: LocalArchiveRecord) -> Bool {
        let lhsEntry = lhs.legacyCachedWritingEntry
        let rhsEntry = rhs.legacyCachedWritingEntry

        if lhsEntry.id == rhsEntry.id {
            return true
        }

        if let lhsAnkyID = lhs.backendAnkyId,
           let rhsAnkyID = rhs.backendAnkyId,
           lhsAnkyID == rhsAnkyID {
            return true
        }

        guard !lhs.sessionBundle.writingPlaintext.isEmpty,
              lhs.sessionBundle.writingPlaintext == rhs.sessionBundle.writingPlaintext else {
            return false
        }

        let createdAtDelta = abs(lhs.createdAt.timeIntervalSince(rhs.createdAt))
        let durationDelta = abs(lhs.sessionBundle.durationSeconds - rhs.sessionBundle.durationSeconds)
        return createdAtDelta < 600 && durationDelta < 5
    }

    private static func merge(
        remote: LocalArchiveRecord,
        local: LocalArchiveRecord
    ) -> LocalArchiveRecord {
        let localBundle = local.sessionBundle
        let remoteBundle = remote.sessionBundle
        let localHasPayload = local.hasCanonicalSessionPayload

        let mergedBundle = AnkySessionBundle(
            sessionId: localBundle.sessionId,
            authorIdentity: localBundle.authorIdentity ?? remoteBundle.authorIdentity,
            clientOrigin: localBundle.clientOrigin,
            startedAt: localBundle.startedAt,
            completedAt: max(localBundle.completedAt, remoteBundle.completedAt),
            durationSeconds: max(remoteBundle.durationSeconds, localBundle.durationSeconds),
            wordCount: max(remoteBundle.wordCount, localBundle.wordCount),
            writingPlaintext: localBundle.writingPlaintext.isEmpty ? remoteBundle.writingPlaintext : localBundle.writingPlaintext,
            keystrokeMetadata: preferredKeystrokeMetadata(local: localBundle.keystrokeMetadata, remote: remoteBundle.keystrokeMetadata),
            title3Words: remoteBundle.title3Words ?? localBundle.title3Words,
            reflection: remoteBundle.reflection ?? localBundle.reflection,
            image: remoteBundle.image ?? localBundle.image,
            sessionHash: localBundle.sessionHash ?? remoteBundle.sessionHash,
            proofMetadata: remoteBundle.proofMetadata ?? localBundle.proofMetadata,
            syncStatus: resolvedSyncStatus(
                remote: remoteBundle.syncStatus,
                local: localBundle.syncStatus,
                localHasPayload: localHasPayload
            ),
            deletionStatus: localBundle.deletionStatus
        )

        return LocalArchiveRecord(
            sessionBundle: mergedBundle,
            backendAnkyId: remote.backendAnkyId ?? local.backendAnkyId,
            createdAt: local.createdAt,
            lastUpdatedAt: max(local.lastUpdatedAt, remote.lastUpdatedAt),
            source: localHasPayload ? .localSessionBundle : remote.source,
            isAnky: remote.isAnky ?? local.isAnky ?? mergedBundle.qualifiesForCanonicalAnky,
            prompt: local.prompt ?? remote.prompt,
            flowScore: remote.flowScore ?? local.flowScore,
            kingdom: remote.kingdom ?? local.kingdom,
            energy: remote.energy ?? local.energy,
            reason: remote.reason ?? local.reason
        )
        .reconcilingCanonicalSyncStatus(updatedAt: max(local.lastUpdatedAt, remote.lastUpdatedAt))
    }

    private static func preferredKeystrokeMetadata(
        local: AnkySessionBundle.KeystrokeMetadata?,
        remote: AnkySessionBundle.KeystrokeMetadata?
    ) -> AnkySessionBundle.KeystrokeMetadata? {
        if local?.canonicalSessionFilePath?.isEmpty == false || local?.canonicalSessionString?.isEmpty == false {
            return local
        }
        return local ?? remote
    }

    private static func resolvedSyncStatus(
        remote: AnkySessionBundle.SyncStatus,
        local: AnkySessionBundle.SyncStatus,
        localHasPayload: Bool
    ) -> AnkySessionBundle.SyncStatus {
        if localHasPayload {
            if local == .localOnly {
                return .localOnly
            }
            if local == .synced {
                return .synced
            }
            if local == .pending || remote == .pending {
                return .pending
            }
            if remote == .synced || remote == .legacyRemoteProjection {
                return .pending
            }
            return .localOnly
        }

        if remote == .legacyRemoteProjection {
            return .legacyRemoteProjection
        }

        if remote == .synced || local == .synced {
            return .synced
        }

        if remote == .pending || local == .pending {
            return .pending
        }

        return .localOnly
    }

    private static func matches(
        record: LocalArchiveRecord,
        id: String?,
        sessionHash: String
    ) -> Bool {
        if let id, record.id == id {
            return true
        }

        return record.sessionBundle.sessionHash == sessionHash
    }
}
