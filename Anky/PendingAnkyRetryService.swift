//
//  PendingAnkyRetryService.swift
//  Anky
//

import Foundation

actor PendingAnkyRetryGate {
    static let shared = PendingAnkyRetryGate()

    private var activeSessionIDs = Set<String>()

    func claim(sessionId: String) -> Bool {
        guard !activeSessionIDs.contains(sessionId) else { return false }
        activeSessionIDs.insert(sessionId)
        return true
    }

    func release(sessionId: String) {
        activeSessionIDs.remove(sessionId)
    }
}

enum PendingAnkyRetryResult: Equatable {
    case synced
    case alreadyRunning
    case pending(message: String)
}

struct PendingAnkyRetrySweepSummary: Equatable {
    var syncedCount = 0
    var pendingCount = 0
    var alreadyRunningCount = 0
    var failedCount = 0

    var attemptedCount: Int {
        syncedCount + pendingCount + alreadyRunningCount + failedCount
    }
}

enum PendingAnkyRetryError: LocalizedError {
    case missingRetryPayload

    var errorDescription: String? {
        switch self {
        case .missingRetryPayload:
            return "this device no longer has the canonical local session bundle needed to resend this anky safely."
        }
    }
}

@MainActor
enum PendingAnkyRetryService {
    static func retryPendingEntries(appState: AppState) async -> PendingAnkyRetrySweepSummary {
        var summary = PendingAnkyRetrySweepSummary()
        let records = appState.pendingArchiveRecords.sorted { $0.createdAt < $1.createdAt }

        for record in records {
            do {
                switch try await retry(record: record, appState: appState) {
                case .synced:
                    summary.syncedCount += 1
                case .alreadyRunning:
                    summary.alreadyRunningCount += 1
                case .pending:
                    summary.pendingCount += 1
                }
            } catch {
                summary.failedCount += 1
                print("[PendingAnkyRetry] Failed \(record.id): \(error.localizedDescription)")
            }
        }

        return summary
    }

    /// Legacy UI adapter until archive/profile surfaces cut over from `CachedWritingEntry`.
    static func retry(entry: CachedWritingEntry, appState: AppState) async throws -> PendingAnkyRetryResult {
        try await retry(record: entry.localArchiveRecord, appState: appState)
    }

    static func retry(record: LocalArchiveRecord, appState: AppState) async throws -> PendingAnkyRetryResult {
        guard record.sessionBundle.qualifiesForCanonicalAnky else {
            return .synced
        }

        guard !record.isCanonicallySealed else {
            return .synced
        }

        let capture = try resolveCapture(for: record, appState: appState)

        guard await PendingAnkyRetryGate.shared.claim(sessionId: capture.sessionId) else {
            return .alreadyRunning
        }
        defer {
            Task {
                await PendingAnkyRetryGate.shared.release(sessionId: capture.sessionId)
            }
        }

        guard await appState.ensureAuthenticatedForWrite() else {
            return .pending(message: "this anky is safe on the device. reconnect and sign in again, then tap send again.")
        }

        appState.updateWritingSyncState(for: capture.sessionId, syncState: .pending)

        if let hydratedRecord = await hydrateFromCanonicalReadback(
            sessionId: capture.sessionId,
            appState: appState
        ) {
            if let existingAnkyId = normalized(hydratedRecord.backendAnkyId) {
                await persistStoredSubmission(
                    ankyId: existingAnkyId,
                    capture: capture,
                    appState: appState
                )
            }

            if hydratedRecord.isCanonicallySealed {
                return .synced
            }

            return .pending(message: pendingMessage(for: hydratedRecord))
        }

        var acceptedAnkyId: String?
        var titleText = normalized(record.sessionBundle.title3Words)
        var fullReflection = normalized(record.sessionBundle.reflection) ?? ""
        var streamedImageURL = normalized(record.sessionBundle.image?.canonicalLocator)
        var didPersistStoredSubmission = false

        func persistArtifacts() {
            appState.storeGeneratedArtifacts(
                for: capture.sessionId,
                reflection: normalized(fullReflection),
                ankyTitle: normalized(titleText),
                ankyImagePath: normalized(streamedImageURL)
            )
        }

        func absorbArchiveRecord(_ updatedRecord: LocalArchiveRecord) {
            if let title = normalized(updatedRecord.sessionBundle.title3Words) {
                titleText = title
            }
            if let reflection = normalized(updatedRecord.sessionBundle.reflection) {
                fullReflection = reflection
            }
            if let imageLocator = normalized(updatedRecord.sessionBundle.image?.canonicalLocator) {
                streamedImageURL = imageLocator
            }
            persistArtifacts()
        }

        func persistStoredSubmissionIfNeeded(ankyId: String) async {
            guard !didPersistStoredSubmission else { return }
            didPersistStoredSubmission = true
            await persistStoredSubmission(
                ankyId: ankyId,
                capture: capture,
                appState: appState
            )
        }

        func reconcileCanonicalArchive(pollUntilSettled: Bool) async -> LocalArchiveRecord? {
            guard let updatedRecord = await appState.reconcileCanonicalArchiveRecord(
                sessionId: capture.sessionId,
                pollUntilSettled: pollUntilSettled
            ) else {
                return nil
            }

            acceptedAnkyId = normalized(updatedRecord.backendAnkyId) ?? acceptedAnkyId
            absorbArchiveRecord(updatedRecord)
            return updatedRecord
        }

        func finalizeIfPossible() async -> PendingAnkyRetryResult {
            let updatedRecord = await reconcileCanonicalArchive(pollUntilSettled: true)

            if let ankyId = normalized(updatedRecord?.backendAnkyId) ?? normalized(acceptedAnkyId) {
                await persistStoredSubmissionIfNeeded(ankyId: ankyId)
            }

            if updatedRecord?.isCanonicallySealed == true {
                return .synced
            }

            return .pending(message: pendingMessage(for: updatedRecord ?? record))
        }

        do {
            for try await event in AnkyAPI.shared.streamAnkySubmit(capture: capture, kingdom: .ankyverseDay()) {
                switch event {
                case .accepted(let ankyId):
                    acceptedAnkyId = ankyId
                    await persistStoredSubmissionIfNeeded(ankyId: ankyId)

                case .title(let title):
                    titleText = title
                    persistArtifacts()

                case .reflectionChunk(let chunk):
                    fullReflection += chunk

                case .reflectionComplete(let reflection):
                    fullReflection = reflection
                    persistArtifacts()

                case .imageURL(let imageURL):
                    streamedImageURL = imageURL
                    persistArtifacts()

                case .solana:
                    break

                case .done(let ankyId):
                    acceptedAnkyId = ankyId
                    persistArtifacts()
                    return await finalizeIfPossible()

                case .error(let stage, _):
                    if (stage == "solana" || stage == "image"),
                       let ankyId = normalized(acceptedAnkyId) {
                        persistArtifacts()
                        await persistStoredSubmissionIfNeeded(ankyId: ankyId)
                        return await finalizeIfPossible()
                    }

                    return await finalizeIfPossible()
                }
            }

            return await finalizeIfPossible()
        } catch is CancellationError {
            return .pending(message: "this resend was cancelled. the anky is still saved locally.")
        } catch {
            return await finalizeIfPossible()
        }
    }

    private static func resolveCapture(
        for record: LocalArchiveRecord,
        appState: AppState
    ) throws -> LocalWritingCapture {
        if let capture = record.retryableCapture {
            return capture
        }

        if let artifact = AnkySessionFileStore.recoverStoredSession(
            matching: record.sessionBundle.writingPlaintext,
            around: record.createdAt
        ) {
            appState.storeRetryArtifacts(
                for: record.id,
                ankySessionString: artifact.sessionString,
                ankyFilePath: artifact.fileURL.path,
                sessionHash: artifact.sessionHash
            )

            return LocalWritingCapture(
                sessionId: record.id,
                prompt: record.prompt ?? "",
                text: record.sessionBundle.writingPlaintext,
                duration: record.sessionBundle.durationSeconds,
                wordCount: record.sessionBundle.wordCount,
                keystrokeDeltas: [],
                finishedAt: record.createdAt,
                estimatedFlowScore: record.flowScore ?? 0,
                ankySessionString: artifact.sessionString,
                ankyFilePath: artifact.fileURL.path,
                sessionHash: artifact.sessionHash
            )
        }

        throw PendingAnkyRetryError.missingRetryPayload
    }

    private static func hydrateFromCanonicalReadback(
        sessionId: String,
        appState: AppState
    ) async -> LocalArchiveRecord? {
        await appState.hydrateCanonicalArchiveRecordIfAvailable(sessionId: sessionId)
    }

    private static func persistStoredSubmission(
        ankyId: String,
        capture: LocalWritingCapture,
        appState: AppState
    ) async {
        await appState.storeCanonicalAcceptedSubmission(
            for: capture.sessionId,
            backendAnkyId: ankyId,
            shouldRouteToUnlocked: false,
            shouldSwitchToStories: false
        )
        await DailyPromptNotificationManager.scheduleWithPrompt(appState.prompt)
        DailyPromptNotificationManager.clearPendingSession()
        WritingFlowModel.autoMintCNFT(sessionId: capture.sessionId, appState: appState)
        WritingFlowModel.archiveToArweave(sessionId: capture.sessionId, text: capture.text)
    }

    private static func pendingMessage(for record: LocalArchiveRecord) -> String {
        let missing = record.artifactCompleteness.missingArtifacts.map(\.rawValue)
        guard !missing.isEmpty else {
            return "the backend already has this session hash. the local archive will keep checking the canonical snapshot and proof until it settles."
        }

        let joinedMissing = missing.joined(separator: ", ")
        return "the backend already has this session hash, but \(joinedMissing) is still pending in the canonical processor readback."
    }

    private static func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
