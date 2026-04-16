//
//  AnkyContractFoundation.swift
//  Anky
//

import Foundation

/// Canonical contract foundation for the sacred Anky loop.
/// This file is intentionally additive: it names the locked truths without
/// cutting over runtime behavior yet.
enum AnkyContract {
    static let canonicalLoop = "write -> title -> reflect -> image -> prove -> archive"

    enum Qualification {
        static let minimumDurationSeconds: TimeInterval = 480
        static let minimumWordCount = 300

        static func wordCount(in text: String) -> Int {
            text
                .split { $0.isWhitespace || $0.isNewline }
                .count
        }

        static func qualifies(text: String, durationSeconds: TimeInterval) -> Bool {
            qualifies(durationSeconds: durationSeconds, wordCount: wordCount(in: text))
        }

        static func qualifies(durationSeconds: TimeInterval, wordCount: Int) -> Bool {
            durationSeconds >= minimumDurationSeconds && wordCount >= minimumWordCount
        }
    }

    enum Title {
        static let requiredWordCount = 3

        static func normalized(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }

        static func wordCount(in value: String) -> Int {
            value.split(whereSeparator: \.isWhitespace).count
        }

        static func validation(for value: String?) -> AnkyTitleValidationResult {
            guard let normalized = normalized(value) else {
                return .missing
            }

            let count = wordCount(in: normalized)
            guard count == requiredWordCount else {
                return .wrongWordCount(actual: count)
            }

            return .valid(normalizedTitle: normalized)
        }

        static func isValid(_ value: String?) -> Bool {
            if case .valid = validation(for: value) {
                return true
            }
            return false
        }
    }

    enum Artifacts {
        static func completeness(
            title: String?,
            reflection: String?,
            image: AnkyImageArtifact?,
            proof: AnkyProofMetadata?
        ) -> AnkyArtifactCompleteness {
            var missing: [AnkyRequiredArtifact] = []

            if !Title.isValid(title) {
                missing.append(.title)
            }

            if normalized(reflection) == nil {
                missing.append(.reflection)
            }

            if image?.isPresent != true {
                missing.append(.image)
            }

            if proof?.isComplete != true {
                missing.append(.proof)
            }

            return AnkyArtifactCompleteness(missingArtifacts: missing)
        }

        static func completeness(
            title: String?,
            reflection: String?,
            imageLocator: String?,
            proof: AnkyProofMetadata?
        ) -> AnkyArtifactCompleteness {
            completeness(
                title: title,
                reflection: reflection,
                image: AnkyImageArtifact(remoteURL: imageLocator),
                proof: proof
            )
        }

        static func normalized(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }
    }
}

enum AnkyTitleValidationResult: Equatable {
    case valid(normalizedTitle: String)
    case missing
    case wrongWordCount(actual: Int)
}

enum AnkyRequiredArtifact: String, Codable, CaseIterable {
    case title
    case reflection
    case image
    case proof
}

struct AnkyArtifactCompleteness: Codable, Equatable {
    let missingArtifacts: [AnkyRequiredArtifact]

    var isComplete: Bool {
        missingArtifacts.isEmpty
    }
}

enum AnkyProofVerificationStatus: String, Codable {
    case missing
    case pending
    case verified
    case failed
    case legacyReceiptOnly
}

enum AnkyProofSource: String, Codable {
    case apiSubmit
    case localRetry
    case legacySealedWrite
    case legacyRelay
    case legacyArweave
    case legacyRemoteHistory
    case unknown
}

struct AnkyProofMetadata: Codable, Equatable {
    let sessionHash: String
    let walletSignature: String?
    let anchorSignature: String?
    let proofURL: String?
    let source: AnkyProofSource
    let verificationStatus: AnkyProofVerificationStatus
    let anchoredAt: Date?

    init(
        sessionHash: String,
        walletSignature: String? = nil,
        anchorSignature: String? = nil,
        proofURL: String? = nil,
        source: AnkyProofSource,
        verificationStatus: AnkyProofVerificationStatus,
        anchoredAt: Date? = nil
    ) {
        self.sessionHash = sessionHash
        self.walletSignature = walletSignature?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.anchorSignature = anchorSignature?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.proofURL = proofURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.verificationStatus = verificationStatus
        self.anchoredAt = anchoredAt
    }

    var isComplete: Bool {
        guard !sessionHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        switch verificationStatus {
        case .verified, .legacyReceiptOnly:
            return true
        case .pending:
            return anchorSignature != nil || proofURL != nil
        case .failed, .missing:
            return false
        }
    }
}

struct AnkyImageArtifact: Codable, Equatable {
    let remoteURL: String?
    let localPath: String?
    let mimeType: String?

    init(
        remoteURL: String? = nil,
        localPath: String? = nil,
        mimeType: String? = nil
    ) {
        self.remoteURL = remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.localPath = localPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mimeType = mimeType?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canonicalLocator: String? {
        if let remoteURL, !remoteURL.isEmpty {
            return remoteURL
        }
        if let localPath, !localPath.isEmpty {
            return localPath
        }
        return nil
    }

    var isPresent: Bool {
        canonicalLocator != nil
    }
}

struct AnkySessionBundle: Codable, Equatable, Identifiable {
    struct ClientOrigin: Codable, Equatable {
        let platform: String
        let surface: String
        let appVersion: String?

        static var nativeIOS: ClientOrigin {
            ClientOrigin(
                platform: "ios",
                surface: "native-ios-app",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            )
        }
    }

    struct KeystrokeMetadata: Codable, Equatable {
        let keystrokeDeltas: [Double]
        let canonicalSessionFilePath: String?
        let canonicalSessionString: String?
        let firstKeystrokeAt: Date?
    }

    enum ArtifactStatus: String, Codable {
        case writingOnly
        case processing
        case complete
    }

    enum SyncStatus: String, Codable {
        case localOnly
        case pending
        case synced
        case legacyRemoteProjection
    }

    enum DeletionStatus: String, Codable {
        case active
        case tombstoned
    }

    let sessionId: String
    let authorIdentity: String?
    let clientOrigin: ClientOrigin
    let startedAt: Date
    let completedAt: Date
    let durationSeconds: Double
    let wordCount: Int
    let writingPlaintext: String
    let keystrokeMetadata: KeystrokeMetadata?
    let title3Words: String?
    let reflection: String?
    let image: AnkyImageArtifact?
    let sessionHash: String?
    let proofMetadata: AnkyProofMetadata?
    let artifactStatus: ArtifactStatus
    let syncStatus: SyncStatus
    let deletionStatus: DeletionStatus

    var id: String { sessionId }

    var qualifiesForCanonicalAnky: Bool {
        AnkyContract.Qualification.qualifies(
            durationSeconds: durationSeconds,
            wordCount: wordCount
        )
    }

    var artifactCompleteness: AnkyArtifactCompleteness {
        AnkyContract.Artifacts.completeness(
            title: title3Words,
            reflection: reflection,
            image: image,
            proof: proofMetadata
        )
    }

    init(
        sessionId: String,
        authorIdentity: String?,
        clientOrigin: ClientOrigin = .nativeIOS,
        startedAt: Date,
        completedAt: Date,
        durationSeconds: Double,
        wordCount: Int,
        writingPlaintext: String,
        keystrokeMetadata: KeystrokeMetadata? = nil,
        title3Words: String? = nil,
        reflection: String? = nil,
        image: AnkyImageArtifact? = nil,
        sessionHash: String? = nil,
        proofMetadata: AnkyProofMetadata? = nil,
        artifactStatus: ArtifactStatus? = nil,
        syncStatus: SyncStatus,
        deletionStatus: DeletionStatus = .active
    ) {
        self.sessionId = sessionId
        self.authorIdentity = authorIdentity
        self.clientOrigin = clientOrigin
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.writingPlaintext = writingPlaintext
        self.keystrokeMetadata = keystrokeMetadata
        self.title3Words = title3Words
        self.reflection = reflection
        self.image = image
        self.sessionHash = sessionHash
        self.proofMetadata = proofMetadata
        self.syncStatus = syncStatus
        self.deletionStatus = deletionStatus

        let completeness = AnkyContract.Artifacts.completeness(
            title: title3Words,
            reflection: reflection,
            image: image,
            proof: proofMetadata
        )

        if let artifactStatus {
            self.artifactStatus = artifactStatus
        } else if completeness.isComplete {
            self.artifactStatus = .complete
        } else if title3Words != nil || reflection != nil || image?.isPresent == true || proofMetadata != nil {
            self.artifactStatus = .processing
        } else {
            self.artifactStatus = .writingOnly
        }
    }

    var canonicalSessionFilePath: String? {
        keystrokeMetadata?.canonicalSessionFilePath
    }

    var canonicalSessionString: String? {
        keystrokeMetadata?.canonicalSessionString
    }

    func updatingArtifacts(
        title3Words: String? = nil,
        reflection: String? = nil,
        image: AnkyImageArtifact? = nil,
        proofMetadata: AnkyProofMetadata? = nil,
        sessionHash: String? = nil
    ) -> AnkySessionBundle {
        AnkySessionBundle(
            sessionId: sessionId,
            authorIdentity: authorIdentity,
            clientOrigin: clientOrigin,
            startedAt: startedAt,
            completedAt: completedAt,
            durationSeconds: durationSeconds,
            wordCount: wordCount,
            writingPlaintext: writingPlaintext,
            keystrokeMetadata: keystrokeMetadata,
            title3Words: title3Words ?? self.title3Words,
            reflection: reflection ?? self.reflection,
            image: image ?? self.image,
            sessionHash: sessionHash ?? self.sessionHash,
            proofMetadata: proofMetadata ?? self.proofMetadata,
            syncStatus: syncStatus,
            deletionStatus: deletionStatus
        )
    }

    func updatingSyncStatus(_ syncStatus: SyncStatus) -> AnkySessionBundle {
        AnkySessionBundle(
            sessionId: sessionId,
            authorIdentity: authorIdentity,
            clientOrigin: clientOrigin,
            startedAt: startedAt,
            completedAt: completedAt,
            durationSeconds: durationSeconds,
            wordCount: wordCount,
            writingPlaintext: writingPlaintext,
            keystrokeMetadata: keystrokeMetadata,
            title3Words: title3Words,
            reflection: reflection,
            image: image,
            sessionHash: sessionHash,
            proofMetadata: proofMetadata,
            syncStatus: syncStatus,
            deletionStatus: deletionStatus
        )
    }

    func updatingLocalBundlePayload(
        canonicalSessionString: String? = nil,
        canonicalSessionFilePath: String? = nil,
        sessionHash: String? = nil,
        proofMetadata: AnkyProofMetadata? = nil
    ) -> AnkySessionBundle {
        let updatedKeystrokeMetadata = KeystrokeMetadata(
            keystrokeDeltas: keystrokeMetadata?.keystrokeDeltas ?? [],
            canonicalSessionFilePath: canonicalSessionFilePath ?? self.canonicalSessionFilePath,
            canonicalSessionString: canonicalSessionString ?? self.canonicalSessionString,
            firstKeystrokeAt: keystrokeMetadata?.firstKeystrokeAt
        )

        return AnkySessionBundle(
            sessionId: sessionId,
            authorIdentity: authorIdentity,
            clientOrigin: clientOrigin,
            startedAt: startedAt,
            completedAt: completedAt,
            durationSeconds: durationSeconds,
            wordCount: wordCount,
            writingPlaintext: writingPlaintext,
            keystrokeMetadata: updatedKeystrokeMetadata,
            title3Words: title3Words,
            reflection: reflection,
            image: image,
            sessionHash: sessionHash ?? self.sessionHash,
            proofMetadata: proofMetadata ?? self.proofMetadata,
            syncStatus: syncStatus,
            deletionStatus: deletionStatus
        )
    }
}

struct LocalArchiveRecord: Codable, Equatable, Identifiable {
    enum RecordSource: String, Codable {
        case localSessionBundle
        case legacyCachedWritingProjection
        case legacyRemoteHistoryProjection
    }

    let sessionBundle: AnkySessionBundle
    let backendAnkyId: String?
    let createdAt: Date
    let lastUpdatedAt: Date
    let source: RecordSource
    let isAnky: Bool?
    let prompt: String?
    let flowScore: Double?
    let kingdom: String?
    let energy: String?
    let reason: String?

    var id: String { sessionBundle.sessionId }

    var artifactCompleteness: AnkyArtifactCompleteness {
        sessionBundle.artifactCompleteness
    }

    var isCanonicalLocalArchive: Bool {
        sessionBundle.qualifiesForCanonicalAnky
            && sessionBundle.sessionHash?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var hasCanonicalSessionPayload: Bool {
        let hasText = !sessionBundle.writingPlaintext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasHash = sessionBundle.sessionHash?.isEmpty == false
        return hasText && hasHash
    }

    var isCanonicallySealed: Bool {
        sessionBundle.syncStatus == .synced && artifactCompleteness.isComplete
    }

    var needsCanonicalProcessorReconciliation: Bool {
        guard isCanonicalLocalArchive else { return false }
        guard sessionBundle.syncStatus != .localOnly else { return false }
        return sessionBundle.syncStatus == .pending || !artifactCompleteness.isComplete
    }

    var legacyCachedWritingEntry: CachedWritingEntry {
        CachedWritingEntry(
            id: sessionBundle.sessionId,
            prompt: prompt ?? "",
            content: sessionBundle.writingPlaintext,
            durationSeconds: sessionBundle.durationSeconds,
            wordCount: sessionBundle.wordCount,
            isAnky: isAnky ?? sessionBundle.qualifiesForCanonicalAnky,
            response: sessionBundle.reflection,
            ankyId: backendAnkyId,
            ankyTitle: sessionBundle.title3Words,
            ankyImagePath: sessionBundle.image?.canonicalLocator,
            createdAt: createdAt,
            flowScore: flowScore,
            syncState: sessionBundle.syncStatus.legacyCachedSyncState,
            kingdom: kingdom,
            energy: energy,
            reason: reason,
            ankySessionString: sessionBundle.canonicalSessionString,
            ankyFilePath: sessionBundle.canonicalSessionFilePath,
            sessionHash: sessionBundle.sessionHash
        )
    }

    var retryableCapture: LocalWritingCapture? {
        guard sessionBundle.qualifiesForCanonicalAnky else { return nil }
        guard sessionBundle.canonicalSessionString?.isEmpty == false || sessionBundle.canonicalSessionFilePath?.isEmpty == false else {
            return nil
        }

        return LocalWritingCapture(
            sessionId: sessionBundle.sessionId,
            prompt: prompt ?? "",
            text: sessionBundle.writingPlaintext,
            duration: sessionBundle.durationSeconds,
            wordCount: sessionBundle.wordCount,
            keystrokeDeltas: sessionBundle.keystrokeMetadata?.keystrokeDeltas ?? [],
            finishedAt: createdAt,
            estimatedFlowScore: flowScore ?? 0,
            ankySessionString: sessionBundle.canonicalSessionString,
            ankyFilePath: sessionBundle.canonicalSessionFilePath,
            sessionHash: sessionBundle.sessionHash
        )
    }

    func updating(
        sessionBundle: AnkySessionBundle? = nil,
        backendAnkyId: String? = nil,
        lastUpdatedAt: Date = .now,
        source: RecordSource? = nil,
        isAnky: Bool? = nil,
        prompt: String? = nil,
        flowScore: Double? = nil,
        kingdom: String? = nil,
        energy: String? = nil,
        reason: String? = nil
    ) -> LocalArchiveRecord {
        LocalArchiveRecord(
            sessionBundle: sessionBundle ?? self.sessionBundle,
            backendAnkyId: backendAnkyId ?? self.backendAnkyId,
            createdAt: createdAt,
            lastUpdatedAt: lastUpdatedAt,
            source: source ?? self.source,
            isAnky: isAnky ?? self.isAnky,
            prompt: prompt ?? self.prompt,
            flowScore: flowScore ?? self.flowScore,
            kingdom: kingdom ?? self.kingdom,
            energy: energy ?? self.energy,
            reason: reason ?? self.reason
        )
    }

    func updatingSyncStatus(_ syncStatus: AnkySessionBundle.SyncStatus, updatedAt: Date = .now) -> LocalArchiveRecord {
        updating(
            sessionBundle: sessionBundle.updatingSyncStatus(syncStatus),
            lastUpdatedAt: updatedAt
        )
    }

    func reconcilingCanonicalSyncStatus(updatedAt: Date? = nil) -> LocalArchiveRecord {
        guard isCanonicalLocalArchive else { return self }
        guard sessionBundle.syncStatus != .localOnly else { return self }

        let resolvedSyncStatus: AnkySessionBundle.SyncStatus = artifactCompleteness.isComplete ? .synced : .pending
        guard resolvedSyncStatus != sessionBundle.syncStatus else { return self }

        return updatingSyncStatus(
            resolvedSyncStatus,
            updatedAt: updatedAt ?? lastUpdatedAt
        )
    }

    func applyingArtifacts(
        title3Words: String? = nil,
        reflection: String? = nil,
        imageLocator: String? = nil,
        proofMetadata: AnkyProofMetadata? = nil,
        backendAnkyId: String? = nil,
        updatedAt: Date = .now
    ) -> LocalArchiveRecord {
        let imageArtifact = imageLocator.map { AnkyImageArtifact(remoteURL: $0) }
        return updating(
            sessionBundle: sessionBundle.updatingArtifacts(
                title3Words: title3Words,
                reflection: reflection,
                image: imageArtifact,
                proofMetadata: proofMetadata
            ),
            backendAnkyId: backendAnkyId,
            lastUpdatedAt: updatedAt
        )
        .reconcilingCanonicalSyncStatus(updatedAt: updatedAt)
    }

    func updatingLocalBundlePayload(
        canonicalSessionString: String? = nil,
        canonicalSessionFilePath: String? = nil,
        sessionHash: String? = nil,
        proofMetadata: AnkyProofMetadata? = nil,
        updatedAt: Date = .now
    ) -> LocalArchiveRecord {
        updating(
            sessionBundle: sessionBundle.updatingLocalBundlePayload(
                canonicalSessionString: canonicalSessionString,
                canonicalSessionFilePath: canonicalSessionFilePath,
                sessionHash: sessionHash,
                proofMetadata: proofMetadata
            ),
            lastUpdatedAt: updatedAt
        )
    }
}

extension LocalWritingCapture {
    func canonicalSessionBundle(syncStatus: AnkySessionBundle.SyncStatus = .localOnly) -> AnkySessionBundle {
        let resolvedSessionHash: String? = {
            if let sessionHash, !sessionHash.isEmpty {
                return sessionHash
            }
            if let ankySessionString, !ankySessionString.isEmpty {
                return AnkySessionFileStore.sha256Hex(of: Data(ankySessionString.utf8))
            }
            return nil
        }()

        let startedAt: Date
        if let ankySessionString,
           let firstKeystrokeDate = AnkySessionFileStore.firstKeystrokeDate(from: ankySessionString) {
            startedAt = firstKeystrokeDate
        } else {
            startedAt = finishedAt.addingTimeInterval(-duration)
        }

        let proofMetadata = resolvedSessionHash.map {
            AnkyProofMetadata(
                sessionHash: $0,
                source: .apiSubmit,
                verificationStatus: .pending
            )
        }

        return AnkySessionBundle(
            sessionId: sessionId,
            authorIdentity: try? SeedIdentityManager.shared.walletAddress(),
            startedAt: startedAt,
            completedAt: finishedAt,
            durationSeconds: duration,
            wordCount: wordCount,
            writingPlaintext: text,
            keystrokeMetadata: .init(
                keystrokeDeltas: keystrokeDeltas,
                canonicalSessionFilePath: ankyFilePath,
                canonicalSessionString: ankySessionString,
                firstKeystrokeAt: startedAt
            ),
            sessionHash: resolvedSessionHash,
            proofMetadata: proofMetadata,
            syncStatus: syncStatus
        )
    }

    var canonicalSessionBundle: AnkySessionBundle {
        canonicalSessionBundle()
    }

    func localArchiveRecord(
        syncStatus: AnkySessionBundle.SyncStatus = .localOnly,
        backendAnkyId: String? = nil,
        reflection: String? = nil,
        title3Words: String? = nil,
        imageLocator: String? = nil
    ) -> LocalArchiveRecord {
        let bundle = canonicalSessionBundle(syncStatus: syncStatus).updatingArtifacts(
            title3Words: title3Words,
            reflection: reflection,
            image: imageLocator.map { AnkyImageArtifact(remoteURL: $0) }
        )

        return LocalArchiveRecord(
            sessionBundle: bundle,
            backendAnkyId: backendAnkyId,
            createdAt: finishedAt,
            lastUpdatedAt: finishedAt,
            source: .localSessionBundle,
            isAnky: bundle.qualifiesForCanonicalAnky,
            prompt: prompt,
            flowScore: estimatedFlowScore,
            kingdom: nil,
            energy: nil,
            reason: nil
        )
    }

    var localArchiveRecord: LocalArchiveRecord {
        localArchiveRecord()
    }
}

extension CachedWritingEntry {
    var canonicalImageArtifact: AnkyImageArtifact? {
        guard remoteImageURL != nil || ankyImagePath?.isEmpty == false else {
            return nil
        }
        return AnkyImageArtifact(remoteURL: ankyImagePath)
    }

    var canonicalProofMetadata: AnkyProofMetadata? {
        guard let sessionHash = sessionHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionHash.isEmpty else {
            return nil
        }

        let verificationStatus: AnkyProofVerificationStatus = syncState == .synced ? .legacyReceiptOnly : .pending

        return AnkyProofMetadata(
            sessionHash: sessionHash,
            source: syncState == .synced ? .legacyRemoteHistory : .localRetry,
            verificationStatus: verificationStatus
        )
    }

    var canonicalSessionBundle: AnkySessionBundle {
        AnkySessionBundle(
            sessionId: id,
            authorIdentity: nil,
            startedAt: createdAt.addingTimeInterval(-durationSeconds),
            completedAt: createdAt,
            durationSeconds: durationSeconds,
            wordCount: wordCount,
            writingPlaintext: content,
            keystrokeMetadata: .init(
                keystrokeDeltas: [],
                canonicalSessionFilePath: ankyFilePath,
                canonicalSessionString: ankySessionString,
                firstKeystrokeAt: createdAt.addingTimeInterval(-durationSeconds)
            ),
            title3Words: ankyTitle,
            reflection: response,
            image: canonicalImageArtifact,
            sessionHash: sessionHash,
            proofMetadata: canonicalProofMetadata,
            syncStatus: syncState.canonicalSyncStatus
        )
    }

    var localArchiveRecord: LocalArchiveRecord {
        LocalArchiveRecord(
            sessionBundle: canonicalSessionBundle,
            backendAnkyId: ankyId,
            createdAt: createdAt,
            lastUpdatedAt: createdAt,
            source: .legacyCachedWritingProjection,
            isAnky: isAnky,
            prompt: prompt,
            flowScore: flowScore,
            kingdom: kingdom,
            energy: energy,
            reason: reason
        )
    }
}

extension WritingItem {
    var canonicalSessionBundle: AnkySessionBundle {
        let createdAtDate = ISO8601DateFormatter().date(from: createdAt) ?? .now

        return AnkySessionBundle(
            sessionId: id,
            authorIdentity: nil,
            startedAt: createdAtDate.addingTimeInterval(-durationSeconds),
            completedAt: createdAtDate,
            durationSeconds: durationSeconds,
            wordCount: wordCount,
            writingPlaintext: content,
            title3Words: ankyTitle,
            reflection: response,
            image: AnkyImageArtifact(remoteURL: ankyImagePath),
            sessionHash: nil,
            proofMetadata: nil,
            syncStatus: .legacyRemoteProjection
        )
    }

    var localArchiveRecord: LocalArchiveRecord {
        let createdAtDate = ISO8601DateFormatter().date(from: createdAt) ?? .now

        return LocalArchiveRecord(
            sessionBundle: canonicalSessionBundle,
            backendAnkyId: ankyId,
            createdAt: createdAtDate,
            lastUpdatedAt: createdAtDate,
            source: .legacyRemoteHistoryProjection,
            isAnky: isAnky && canonicalSessionBundle.qualifiesForCanonicalAnky,
            prompt: nil,
            flowScore: flowScore,
            kingdom: kingdom,
            energy: energy,
            reason: reason
        )
    }
}

extension WritingStatusResponse {
    var artifactCompleteness: AnkyArtifactCompleteness {
        AnkyContract.Artifacts.completeness(
            title: anky?.title,
            reflection: ankyResponse ?? anky?.reflection,
            imageLocator: anky?.imageUrl,
            proof: nil
        )
    }
}

extension CachedWritingSyncState {
    var canonicalSyncStatus: AnkySessionBundle.SyncStatus {
        switch self {
        case .localOnly:
            return .localOnly
        case .pending:
            return .pending
        case .synced:
            return .synced
        }
    }
}

extension AnkySessionBundle.SyncStatus {
    var legacyCachedSyncState: CachedWritingSyncState {
        switch self {
        case .localOnly:
            return .localOnly
        case .pending:
            return .pending
        case .synced, .legacyRemoteProjection:
            return .synced
        }
    }
}
