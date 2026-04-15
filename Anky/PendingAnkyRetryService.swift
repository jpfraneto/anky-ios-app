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
            return "this device no longer has the canonical .anky session needed to resend this anky safely."
        }
    }
}

@MainActor
enum PendingAnkyRetryService {
    static func retryPendingEntries(appState: AppState) async -> PendingAnkyRetrySweepSummary {
        var summary = PendingAnkyRetrySweepSummary()
        let entries = appState.pendingPersistedWrites.sorted { $0.createdAt < $1.createdAt }

        for entry in entries {
            do {
                switch try await retry(entry: entry, appState: appState) {
                case .synced:
                    summary.syncedCount += 1
                case .alreadyRunning:
                    summary.alreadyRunningCount += 1
                case .pending:
                    summary.pendingCount += 1
                }
            } catch {
                summary.failedCount += 1
                print("[PendingAnkyRetry] Failed \(entry.id): \(error.localizedDescription)")
            }
        }

        return summary
    }

    static func retry(entry: CachedWritingEntry, appState: AppState) async throws -> PendingAnkyRetryResult {
        guard entry.isAnky, entry.syncState != .synced else {
            return .synced
        }

        let capture = try resolveCapture(for: entry, appState: appState)

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

        if let status = try? await hydrateFromStatus(capture: capture, appState: appState),
           let existingAnkyId = normalized(status.anky?.id) {
            await persistStoredSubmission(
                ankyId: existingAnkyId,
                capture: capture,
                reflection: status.ankyResponse ?? status.anky?.reflection,
                nextPrompt: status.nextPrompt,
                appState: appState
            )
            return .synced
        }

        var acceptedAnkyId: String?
        var titleText = normalized(entry.ankyTitle)
        var fullReflection = normalized(entry.response) ?? ""
        var streamedImageURL = normalized(entry.ankyImagePath)
        var nextPrompt: String?
        var didPersistStoredSubmission = false

        func persistArtifacts() {
            appState.storeGeneratedArtifacts(
                for: capture.sessionId,
                reflection: normalized(fullReflection),
                ankyTitle: normalized(titleText),
                ankyImagePath: normalized(streamedImageURL)
            )
        }

        func persistStoredSubmissionIfNeeded(ankyId: String) async {
            guard !didPersistStoredSubmission else { return }
            didPersistStoredSubmission = true
            await persistStoredSubmission(
                ankyId: ankyId,
                capture: capture,
                reflection: normalized(fullReflection),
                nextPrompt: normalized(nextPrompt),
                appState: appState
            )
        }

        func pollForMissingArtifacts() async {
            let needsAnkyID = normalized(acceptedAnkyId) == nil
            let needsReflection = normalized(fullReflection) == nil
            let needsTitle = normalized(titleText) == nil
            let needsImage = normalized(streamedImageURL) == nil
            let needsPrompt = normalized(nextPrompt) == nil

            guard needsAnkyID || needsReflection || needsTitle || needsImage || needsPrompt else { return }

            var retryDelay: UInt64 = 1_500_000_000
            for attempt in 0..<20 {
                try? await Task.sleep(nanoseconds: retryDelay)

                do {
                    let status = try await AnkyAPI.shared.getWritingStatus(sessionId: capture.sessionId)
                    if needsAnkyID, let ankyId = normalized(status.anky?.id) {
                        acceptedAnkyId = ankyId
                    }
                    if needsReflection, let reflection = normalized(status.ankyResponse ?? status.anky?.reflection) {
                        fullReflection = reflection
                    }
                    if needsTitle, let title = normalized(status.anky?.title) {
                        titleText = title
                    }
                    if needsImage, let imageURL = normalized(status.anky?.imageUrl) {
                        streamedImageURL = imageURL
                    }
                    if needsPrompt, let prompt = normalized(status.nextPrompt) {
                        nextPrompt = prompt
                    }

                    persistArtifacts()

                    let stillNeedsAnkyID = needsAnkyID && normalized(acceptedAnkyId) == nil
                    let stillNeedsReflection = needsReflection && normalized(fullReflection) == nil
                    let stillNeedsTitle = needsTitle && normalized(titleText) == nil
                    let stillNeedsImage = needsImage && normalized(streamedImageURL) == nil
                    let stillNeedsPrompt = needsPrompt && normalized(nextPrompt) == nil
                    if !stillNeedsAnkyID && !stillNeedsReflection && !stillNeedsTitle && !stillNeedsImage && !stillNeedsPrompt {
                        break
                    }
                } catch let error as AnkyError where error.isConnectivityIssue {
                    retryDelay = min(retryDelay * 2, 8_000_000_000)
                    if attempt > 10 { break }
                } catch {
                    break
                }
            }
        }

        func finalizeIfPossible() async -> PendingAnkyRetryResult {
            await pollForMissingArtifacts()
            persistArtifacts()

            if let ankyId = normalized(acceptedAnkyId) {
                await persistStoredSubmissionIfNeeded(ankyId: ankyId)
                if let prompt = normalized(nextPrompt) {
                    await DailyPromptNotificationManager.scheduleWithPrompt(prompt)
                }
                DailyPromptNotificationManager.clearPendingSession()
                return .synced
            }

            return .pending(
                message: "the anky is still saved locally, but the backend has not confirmed processing yet. try this button again later."
            )
        }

        do {
            for try await event in AnkyAPI.shared.streamAnkySubmit(capture: capture, kingdom: .ankyverseDay()) {
                switch event {
                case .accepted(let ankyId):
                    acceptedAnkyId = ankyId

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
                    await persistStoredSubmissionIfNeeded(ankyId: ankyId)
                    if let prompt = normalized(nextPrompt) {
                        await DailyPromptNotificationManager.scheduleWithPrompt(prompt)
                    }
                    DailyPromptNotificationManager.clearPendingSession()
                    return .synced

                case .error(let stage, _):
                    if (stage == "solana" || stage == "image"),
                       let ankyId = normalized(acceptedAnkyId) {
                        persistArtifacts()
                        await persistStoredSubmissionIfNeeded(ankyId: ankyId)
                        return .synced
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
        for entry: CachedWritingEntry,
        appState: AppState
    ) throws -> LocalWritingCapture {
        if let capture = entry.retryableAnkyCapture {
            return capture
        }

        if let artifact = AnkySessionFileStore.recoverStoredSession(matching: entry.content, around: entry.createdAt) {
            appState.storeRetryArtifacts(
                for: entry.id,
                ankySessionString: artifact.sessionString,
                ankyFilePath: artifact.fileURL.path,
                sessionHash: artifact.sessionHash
            )

            return LocalWritingCapture(
                sessionId: entry.id,
                prompt: entry.prompt,
                text: entry.content,
                duration: entry.durationSeconds,
                wordCount: entry.wordCount,
                keystrokeDeltas: [],
                finishedAt: entry.createdAt,
                estimatedFlowScore: entry.flowScore ?? 0,
                ankySessionString: artifact.sessionString,
                ankyFilePath: artifact.fileURL.path,
                sessionHash: artifact.sessionHash
            )
        }

        throw PendingAnkyRetryError.missingRetryPayload
    }

    private static func hydrateFromStatus(
        capture: LocalWritingCapture,
        appState: AppState
    ) async throws -> WritingStatusResponse {
        let status = try await AnkyAPI.shared.getWritingStatus(sessionId: capture.sessionId)
        appState.storeGeneratedArtifacts(
            for: capture.sessionId,
            reflection: normalized(status.ankyResponse ?? status.anky?.reflection),
            ankyTitle: normalized(status.anky?.title),
            ankyImagePath: normalized(status.anky?.imageUrl)
        )
        return status
    }

    private static func persistStoredSubmission(
        ankyId: String,
        capture: LocalWritingCapture,
        reflection: String?,
        nextPrompt: String?,
        appState: AppState
    ) async {
        let response = MobileWriteResponse(
            ok: true,
            sessionId: capture.sessionId,
            outcome: "anky",
            wordCount: capture.wordCount,
            durationSeconds: capture.duration,
            flowScore: capture.estimatedFlowScore,
            persisted: true,
            spawned: SpawnedArtifacts(
                ankyId: ankyId,
                feedback: nil,
                meditation: nil,
                breathwork: nil,
                cuentacuentos: nil
            ),
            walletAddress: nil,
            statusUrl: nil,
            ankyResponse: normalized(reflection),
            nextPrompt: normalized(nextPrompt),
            mood: nil,
            error: nil
        )

        await appState.applyPersistedAnkySuccess(
            capture: capture,
            response: response,
            shouldRouteToUnlocked: false,
            shouldSwitchToStories: false
        )
        WritingFlowModel.autoMintCNFT(sessionId: capture.sessionId, appState: appState)
        WritingFlowModel.archiveToArweave(sessionId: capture.sessionId, text: capture.text)
    }

    private static func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
