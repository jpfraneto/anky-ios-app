//
//  AnkyModels.swift
//  Anky
//

import Foundation

enum AnkyError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case missingSession
    case unauthorized
    case api(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL is invalid."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .missingSession:
            return "Your identity is not ready to sync yet."
        case .unauthorized:
            return "Anky needs to quietly restore your session."
        case .api(let message), .transport(let message):
            return message
        }
    }

    var isConnectivityIssue: Bool {
        if case .transport = self {
            return true
        }
        return false
    }
}

struct EmptyResponse: Codable {
    let ok: Bool?
}

struct ErrorResponse: Codable {
    let error: String
}

// MARK: - Auth

struct SeedAuthChallengeRequest: Codable {
    let walletAddress: String
}

struct SeedAuthChallengeResponse: Codable {
    let ok: Bool
    let challengeId: String
    let message: String
    let expiresAt: String
}

struct SeedAuthVerifyRequest: Codable {
    let walletAddress: String
    let challengeId: String
    let signature: String
}

struct SeedAuthVerifyResponse: Codable {
    let ok: Bool
    let sessionToken: String
    let userId: String
    let walletAddress: String
}

struct UserProfile: Codable {
    let userId: String
    let username: String?
    let displayName: String?
    let profileImageUrl: String?
    let email: String?
    let walletAddress: String?
    let totalWritings: Int
    let totalAnkys: Int
    let isPremium: Bool?
}

struct ConnectedDevicesResponse: Decodable {
    let items: [ConnectedDevice]

    init(items: [ConnectedDevice]) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        if let array = try? [ConnectedDevice](from: decoder) {
            items = array
            return
        }

        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        items = try container.decodeFlexibleArray(
            ConnectedDevice.self,
            forKeys: ["devices", "sessions", "items", "results"],
            defaultValue: []
        )
    }
}

struct ConnectedDevice: Codable, Identifiable, Equatable {
    let id: String
    let deviceName: String?
    let model: String?
    let platform: String?
    let osVersion: String?
    let appVersion: String?
    let location: String?
    let ipAddress: String?
    let lastSeenAt: String?
    let createdAt: String?
    let revokedAt: String?
    let isCurrent: Bool
    let isRevoked: Bool

    init(
        id: String,
        deviceName: String? = nil,
        model: String? = nil,
        platform: String? = nil,
        osVersion: String? = nil,
        appVersion: String? = nil,
        location: String? = nil,
        ipAddress: String? = nil,
        lastSeenAt: String? = nil,
        createdAt: String? = nil,
        revokedAt: String? = nil,
        isCurrent: Bool = false,
        isRevoked: Bool = false
    ) {
        self.id = id
        self.deviceName = deviceName
        self.model = model
        self.platform = platform
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.location = location
        self.ipAddress = ipAddress
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
        self.revokedAt = revokedAt
        self.isCurrent = isCurrent
        self.isRevoked = isRevoked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)

        id = (try? container.decodeFlexibleString(forKeys: ["id", "device_id", "session_id"])) ?? UUID().uuidString
        deviceName = try container.decodeFlexibleOptionalString(forKeys: ["device_name", "name", "label", "title"])
        model = try container.decodeFlexibleOptionalString(forKeys: ["model", "device_model", "client_name", "browser"])
        platform = try container.decodeFlexibleOptionalString(forKeys: ["platform", "os", "system", "device_type"])
        osVersion = try container.decodeFlexibleOptionalString(forKeys: ["os_version", "system_version", "platform_version"])
        appVersion = try container.decodeFlexibleOptionalString(forKeys: ["app_version", "version"])
        location = try container.decodeFlexibleOptionalString(forKeys: ["location", "city", "region"])
        ipAddress = try container.decodeFlexibleOptionalString(forKeys: ["ip_address", "ip"])
        lastSeenAt = try container.decodeFlexibleOptionalString(forKeys: ["last_seen_at", "last_active_at", "updated_at", "seen_at"])
        createdAt = try container.decodeFlexibleOptionalString(forKeys: ["created_at", "signed_in_at"])
        revokedAt = try container.decodeFlexibleOptionalString(forKeys: ["revoked_at"])
        isCurrent = try container.decodeFlexibleBool(
            forKeys: ["is_current", "current", "current_session", "current_device"],
            defaultValue: false
        )
        isRevoked = try container.decodeFlexibleBool(
            forKeys: ["is_revoked", "revoked"],
            defaultValue: revokedAt != nil
        )
    }

    static func currentFallback(appVersion: String) -> ConnectedDevice {
        ConnectedDevice(
            id: "this-device",
            deviceName: nil,
            model: "iPhone",
            platform: "iOS",
            osVersion: nil,
            appVersion: appVersion,
            location: nil,
            ipAddress: nil,
            lastSeenAt: ISO8601DateFormatter().string(from: .now),
            createdAt: nil,
            revokedAt: nil,
            isCurrent: true,
            isRevoked: false
        )
    }

    var canRevoke: Bool {
        !isCurrent && !isRevoked
    }
}

// MARK: - Writing

struct ChatHistoryItem: Codable, Equatable {
    let role: String
    let content: String
}

struct QuickChatRequest: Codable {
    let writing: String
    let message: String
    let history: [ChatHistoryItem]
}

struct QuickChatResponse: Codable {
    let response: String
}

struct AnkyConversationRequest: Codable {
    let text: String
}

struct AnkyConversationResponse: Codable {
    let role: String
    let text: String
}

struct MobileWriteRequest: Codable {
    let text: String
    let duration: Double
    let sessionId: String?
    let keystrokeDeltas: [Double]?
    let isCheckpoint: Bool?
    let nowSlug: String?

    init(
        text: String,
        duration: Double,
        sessionId: String?,
        keystrokeDeltas: [Double]?,
        isCheckpoint: Bool?,
        nowSlug: String? = nil
    ) {
        self.text = text
        self.duration = duration
        self.sessionId = sessionId
        self.keystrokeDeltas = keystrokeDeltas
        self.isCheckpoint = isCheckpoint
        self.nowSlug = nowSlug
    }
}

struct MobileWriteResponse: Codable {
    let ok: Bool
    let sessionId: String
    let outcome: String?
    let wordCount: Int
    let durationSeconds: Double?
    let flowScore: Double?
    let persisted: Bool?
    let spawned: SpawnedArtifacts?
    let walletAddress: String?
    let statusUrl: String?
    let ankyResponse: String?
    let nextPrompt: String?
    let mood: String?
    let error: String?

    var isAnky: Bool {
        outcome == "anky"
    }

    var ankyId: String? {
        spawned?.ankyId
    }
}

struct SpawnedArtifacts: Codable {
    let ankyId: String?
    let feedback: Bool?
    let meditation: Bool?
    let breathwork: Bool?
    let cuentacuentos: Bool?
}

struct WritingStatusResponse: Codable {
    let sessionId: String
    let isAnky: Bool?
    let durationSeconds: Double?
    let wordCount: Int?
    let anky: AnkyArtifactStatus?
    let cuentacuentos: CuentacuentosArtifactStatus?
    let meditation: ArtifactStatus?
    let breathwork: BreathworkArtifactStatus?
    let ankyResponse: String?
    let nextPrompt: String?
    let mood: String?
}

/// Canonical processor submit/readback models for the local-archive-first flow.
struct CanonicalProcessorSubmitResponse: Codable, Equatable {
    let sessionHash: String
    let statusPath: String?
    let proofPath: String?
    let artifactSetValid: Bool?
}

struct CanonicalProcessorReadbackPaths: Codable, Equatable {
    let statusPath: String?
    let proofPath: String?
}

struct CanonicalProcessorSessionIdentity: Codable, Equatable {
    let sessionHash: String
    let ankyId: String?
    let walletAddress: String?
}

struct CanonicalProcessorLifecycleTimestamps: Codable, Equatable {
    let submittedAt: String?
    let acceptedAt: String?
    let reflectedAt: String?
    let imagedAt: String?
    let provedAt: String?
    let completedAt: String?
}

struct CanonicalProcessorStatusSnapshot: Codable, Equatable {
    let overallStatus: String?
    let titleStatus: String?
    let reflectionStatus: String?
    let imageStatus: String?
    let proofStatus: String?
}

struct CanonicalProcessorImageArtifact: Codable, Equatable {
    let imageUrl: String?
    let artifactRef: String?
    let mimeType: String?
}

struct CanonicalProcessorArtifacts: Codable, Equatable {
    let title: String?
    let reflection: String?
    let image: CanonicalProcessorImageArtifact?
}

struct CanonicalProofReadback: Codable, Equatable {
    let sessionHash: String?
    let status: String?
    let receipt: String?
    let proofUrl: String?
    let walletSignature: String?
    let verificationStatus: String?
    let completedAt: String?
}

struct LegacyProcessorRetentionBoundary: Codable, Equatable {
    let plaintextWritingRetained: Bool?
    let sessionPayloadRetained: Bool?
}

struct CanonicalProcessorStatusResponse: Codable, Equatable {
    let identity: CanonicalProcessorSessionIdentity
    let readbackPaths: CanonicalProcessorReadbackPaths?
    let status: CanonicalProcessorStatusSnapshot?
    let lifecycle: CanonicalProcessorLifecycleTimestamps?
    let artifacts: CanonicalProcessorArtifacts?
    let proof: CanonicalProofReadback?
    let artifactCompleteness: AnkyArtifactCompleteness?
    let artifactSetValid: Bool?
    let legacyRetentionBoundary: LegacyProcessorRetentionBoundary?
}

struct CanonicalProofResponse: Codable, Equatable {
    let identity: CanonicalProcessorSessionIdentity
    let readbackPaths: CanonicalProcessorReadbackPaths?
    let proof: CanonicalProofReadback
}

/// Canonical `/api/anky/submit` request payload for the current core processor path.
struct AnkySubmitRequest: Encodable {
    let sessionHash: String
    let durationSeconds: Int
    let wordCount: Int
    let kingdom: String
    let startedAt: String
    let walletSignature: String
    let session: String
}

enum AnkySubmitStreamEvent: Equatable {
    case accepted(ankyId: String)
    case title(String)
    case reflectionChunk(String)
    case reflectionComplete(String)
    case imageURL(String)
    case solana(signature: String)
    case done(ankyId: String)
    case error(stage: String, retryable: Bool)
}

struct AnkySubmitStreamResult: Equatable {
    var ankyId: String?
    var title: String?
    var reflection: String = ""
    var imageURL: String?
    var solanaSignature: String?
    var didReachDone = false
}

extension CanonicalProofReadback {
    var canonicalProofMetadata: AnkyProofMetadata? {
        let resolvedSessionHash = normalized(sessionHash)
        guard let resolvedSessionHash else { return nil }

        return AnkyProofMetadata(
            sessionHash: resolvedSessionHash,
            walletSignature: normalized(walletSignature),
            anchorSignature: normalized(receipt),
            proofURL: normalized(proofUrl),
            source: .apiSubmit,
            verificationStatus: resolvedVerificationStatus,
            anchoredAt: completedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }

    private var resolvedVerificationStatus: AnkyProofVerificationStatus {
        let candidates = [verificationStatus, status]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        for candidate in candidates {
            if candidate.contains("verified") || candidate.contains("complete") || candidate.contains("anchored") {
                return .verified
            }
            if candidate.contains("pending") || candidate.contains("processing") || candidate.contains("queued") {
                return .pending
            }
            if candidate.contains("fail") || candidate.contains("error") {
                return .failed
            }
        }

        return .missing
    }
}

extension CanonicalProcessorStatusResponse {
    var canonicalProofMetadata: AnkyProofMetadata? {
        proof?.canonicalProofMetadata
    }

    var canonicalImageArtifact: AnkyImageArtifact? {
        guard let image = artifacts?.image else { return nil }
        return AnkyImageArtifact(
            remoteURL: normalized(image.imageUrl),
            mimeType: normalized(image.mimeType)
        )
    }

    var lastCanonicalUpdateAt: Date? {
        let formatter = ISO8601DateFormatter()
        let candidates = [
            lifecycle?.completedAt,
            lifecycle?.provedAt,
            lifecycle?.imagedAt,
            lifecycle?.reflectedAt,
            lifecycle?.acceptedAt,
            lifecycle?.submittedAt
        ]

        for candidate in candidates {
            if let normalized = normalized(candidate),
               let date = formatter.date(from: normalized) {
                return date
            }
        }

        return nil
    }
}

extension CanonicalProofResponse {
    var canonicalProofMetadata: AnkyProofMetadata? {
        proof.canonicalProofMetadata
    }
}

extension LocalArchiveRecord {
    func applyingCanonicalProcessorStatus(_ response: CanonicalProcessorStatusResponse) -> LocalArchiveRecord {
        applyingArtifacts(
            title3Words: normalized(response.artifacts?.title),
            reflection: normalized(response.artifacts?.reflection),
            imageLocator: normalized(response.artifacts?.image?.imageUrl),
            proofMetadata: response.canonicalProofMetadata ?? sessionBundle.proofMetadata,
            backendAnkyId: normalized(response.identity.ankyId),
            updatedAt: response.lastCanonicalUpdateAt ?? .now
        )
        .reconcilingCanonicalSyncStatus(updatedAt: response.lastCanonicalUpdateAt ?? .now)
    }

    func applyingCanonicalProofReadback(_ response: CanonicalProofResponse) -> LocalArchiveRecord {
        let updatedAt = response.proof.completedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? .now

        return applyingArtifacts(
            proofMetadata: response.canonicalProofMetadata,
            backendAnkyId: normalized(response.identity.ankyId),
            updatedAt: updatedAt
        )
        .reconcilingCanonicalSyncStatus(updatedAt: updatedAt)
    }
}

private func normalized(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

/// Legacy backend `/swift/v2/writing/{id}/status` compatibility projection.
/// Canonical runtime proof/artifact reconciliation now uses session-hash readback.
struct AnkyArtifactStatus: Codable {
    let id: String?
    let status: String
    let imageUrl: String?
    let title: String?
    let reflection: String?
}

struct CuentacuentosArtifactStatus: Codable {
    let id: String?
    let status: String
    let chakra: Int?
    let kingdom: String?
    let city: String?
    let title: String?
    let translationsDone: [String]?
    let imagesTotal: Int?
    let imagesDone: Int?
}

struct ArtifactStatus: Codable {
    let status: String
}

struct BreathworkArtifactStatus: Codable {
    let status: String
    let style: String?
}

/// Legacy backend history projection kept only as a compatibility adapter into
/// `LocalArchiveRecord`. It is not the canonical client archive model.
struct WritingItem: Codable, Identifiable {
    let id: String
    let content: String
    let durationSeconds: Double
    let wordCount: Int
    let isAnky: Bool
    let response: String?
    let ankyId: String?
    let ankyTitle: String?
    let ankyImagePath: String?
    let createdAt: String
    let flowScore: Double?
    let kingdom: String?
    let energy: String?
    let reason: String?

    init(
        id: String,
        content: String,
        durationSeconds: Double,
        wordCount: Int,
        isAnky: Bool,
        response: String?,
        ankyId: String?,
        ankyTitle: String?,
        ankyImagePath: String?,
        createdAt: String,
        flowScore: Double? = nil,
        kingdom: String? = nil,
        energy: String? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.content = content
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.isAnky = isAnky
        self.response = response
        self.ankyId = ankyId
        self.ankyTitle = ankyTitle
        self.ankyImagePath = ankyImagePath
        self.createdAt = createdAt
        self.flowScore = flowScore
        self.kingdom = kingdom
        self.energy = energy
        self.reason = reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        let nestedAnky = try container.decodeFlexibleOptionalNestedObject(WritingHistoryAnkyPayload.self, forKeys: ["anky", "generated_anky"])

        id = try container.decodeFlexibleString(forKeys: ["id", "anky_id", "session_id"])
        content = try container.decodeFlexibleString(forKeys: ["content", "text"])
        durationSeconds = try container.decodeFlexibleDouble(forKeys: ["duration_seconds", "duration"], defaultValue: 0)
        wordCount = try container.decodeFlexibleInt(forKeys: ["word_count"], defaultValue: AnkyContract.Qualification.wordCount(in: content))
        isAnky = try container.decodeFlexibleBool(forKeys: ["is_anky"], defaultValue: false)
        response = try container.decodeFlexibleOptionalString(forKeys: ["response", "reflection", "anky_response", "anky_reflection"])
            ?? nestedAnky?.reflection
            ?? nestedAnky?.response
        ankyId = try container.decodeFlexibleOptionalString(forKeys: ["anky_id"])
            ?? nestedAnky?.id
        ankyTitle = try container.decodeFlexibleOptionalString(forKeys: ["anky_title", "title"])
            ?? nestedAnky?.title
        ankyImagePath = try container.decodeFlexibleOptionalString(forKeys: ["anky_image_path", "image_path", "image_url", "anky_image_url"])
            ?? nestedAnky?.imagePath
            ?? nestedAnky?.imageUrl
        createdAt = try container.decodeFlexibleString(forKeys: ["created_at", "updated_at"])
        flowScore = try container.decodeFlexibleOptionalDouble(forKeys: ["flow_score"])
        kingdom = try container.decodeFlexibleOptionalString(forKeys: ["kingdom"])
        energy = try container.decodeFlexibleOptionalString(forKeys: ["energy"])
        reason = try container.decodeFlexibleOptionalString(forKeys: ["reason"])
    }
}

private struct WritingHistoryAnkyPayload: Codable {
    let id: String?
    let title: String?
    let reflection: String?
    let response: String?
    let imagePath: String?
    let imageUrl: String?
}

enum CachedWritingSyncState: String, Codable {
    case synced
    case pending
    case localOnly
}

/// Legacy cache read model kept for runtime stability until archive cutover.
/// New contract work should prefer `LocalArchiveRecord`.
struct CachedWritingEntry: Codable, Identifiable, Equatable {
    let id: String
    let prompt: String
    let content: String
    let durationSeconds: Double
    let wordCount: Int
    let isAnky: Bool
    let response: String?
    let ankyId: String?
    let ankyTitle: String?
    let ankyImagePath: String?
    let createdAt: Date
    let flowScore: Double?
    let syncState: CachedWritingSyncState
    let kingdom: String?
    let energy: String?
    let reason: String?
    let ankySessionString: String?
    let ankyFilePath: String?
    let sessionHash: String?

    /// Parsed kingdom enum. Null if not yet classified by backend.
    var ankyKingdom: AnkyKingdom? {
        kingdom.flatMap { AnkyKingdom(rawValue: $0.lowercased()) }
    }

    var createdAtLabel: String {
        Self.dayFormatter.string(from: createdAt)
    }

    var durationLabel: String {
        let totalSeconds = max(Int(durationSeconds.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes)m \(seconds)s"
    }

    var remoteImageURL: URL? {
        guard let ankyImagePath = ankyImagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ankyImagePath.isEmpty else {
            return nil
        }

        if ankyImagePath.hasPrefix("http://") || ankyImagePath.hasPrefix("https://") {
            return URL(string: ankyImagePath)
        }

        let normalizedPath = ankyImagePath.hasPrefix("/") ? ankyImagePath : "/\(ankyImagePath)"
        return URL(string: "https://anky.app\(normalizedPath)")
    }

    var retryableAnkyCapture: LocalWritingCapture? {
        localArchiveRecord.retryableCapture
    }

    init(
        id: String,
        prompt: String,
        content: String,
        durationSeconds: Double,
        wordCount: Int,
        isAnky: Bool,
        response: String?,
        ankyId: String?,
        ankyTitle: String?,
        ankyImagePath: String?,
        createdAt: Date,
        flowScore: Double?,
        syncState: CachedWritingSyncState,
        kingdom: String? = nil,
        energy: String? = nil,
        reason: String? = nil,
        ankySessionString: String? = nil,
        ankyFilePath: String? = nil,
        sessionHash: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.content = content
        self.durationSeconds = durationSeconds
        self.wordCount = wordCount
        self.isAnky = isAnky
        self.response = response
        self.ankyId = ankyId
        self.ankyTitle = ankyTitle
        self.ankyImagePath = ankyImagePath
        self.createdAt = createdAt
        self.flowScore = flowScore
        self.syncState = syncState
        self.kingdom = kingdom
        self.energy = energy
        self.reason = reason
        self.ankySessionString = ankySessionString
        self.ankyFilePath = ankyFilePath
        self.sessionHash = sessionHash
    }

    init(item: WritingItem, prompt: String = "") {
        let qualifiesForAnky = AnkyContract.Qualification.qualifies(
            durationSeconds: item.durationSeconds,
            wordCount: item.wordCount
        )

        self.init(
            id: item.id,
            prompt: prompt,
            content: item.content,
            durationSeconds: item.durationSeconds,
            wordCount: item.wordCount,
            isAnky: item.isAnky && qualifiesForAnky,
            response: item.response,
            ankyId: item.ankyId,
            ankyTitle: item.ankyTitle,
            ankyImagePath: item.ankyImagePath,
            createdAt: Self.isoFormatter.date(from: item.createdAt) ?? .now,
            flowScore: item.flowScore,
            syncState: .synced,
            kingdom: item.kingdom,
            energy: item.energy,
            reason: item.reason,
            ankySessionString: nil,
            ankyFilePath: nil,
            sessionHash: nil
        )
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - Prompts

struct PromptResponse: Codable {
    let id: String
    let text: String
}

// MARK: - Generate

struct GenerateAnkyRequest: Codable, Equatable {
    let model: String
    let writing: String
    let aspectRatio: String
}

struct GenerateAnkyResponse: Codable, Equatable {
    let ankyId: String?
    let error: String?
}

struct GeneratedAnkyListResponse: Codable, Equatable {
    let ankys: [GeneratedAnky]
}

struct GeneratedAnky: Codable, Equatable, Identifiable {
    let id: String
    let createdAt: String?
    let title: String?
    let status: String?
    let origin: String?
    let imagePath: String?
    let imageUrl: String?
    let imageWebp: String?
    let imagePrompt: String?
    let reflection: String?
    let thinkerName: String?

    private static let webDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    var createdAtDate: Date? {
        guard let createdAt = createdAt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !createdAt.isEmpty else {
            return nil
        }

        return Self.isoFormatter.date(from: createdAt)
            ?? Self.webDateFormatter.date(from: createdAt)
    }

    var createdAtLabel: String {
        guard let createdAtDate else { return "recently" }
        return RelativeDateTimeFormatter().localizedString(for: createdAtDate, relativeTo: .now)
    }

    var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let thinkerName = thinkerName?.trimmingCharacters(in: .whitespacesAndNewlines), !thinkerName.isEmpty {
            return thinkerName
        }
        if let imagePrompt = imagePrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !imagePrompt.isEmpty {
            let words = imagePrompt.split(whereSeparator: \.isWhitespace).prefix(7).joined(separator: " ")
            return words.isEmpty ? "anky" : words
        }
        return "anky"
    }

    var displayPrompt: String? {
        let trimmed = imagePrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    var remoteImageURL: URL? {
        let candidates = [imageWebp, imageUrl, imagePath]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in candidates {
            if candidate.hasPrefix("http://") || candidate.hasPrefix("https://") {
                return URL(string: candidate)
            }

            if candidate.hasPrefix("/") {
                return URL(string: "https://anky.app\(candidate)")
            }

            if candidate.hasSuffix(".webp"), !candidate.contains("/") {
                return URL(string: "https://anky.app/data/images/\(candidate)")
            }

            return URL(string: "https://anky.app/\(candidate)")
        }

        return nil
    }
}

// MARK: - Altar

struct AltarState: Codable, Equatable {
    let imageUrl: String
    let totalBurnedUsdc: Int
    let totalBurns: Int
    let topBurners: [AltarBurner]
    let recentBurns: [RecentAltarBurn]
    let stripePublishableKey: String?
    let network: String?
    let treasuryAddress: String?
    let usdcTokenAddress: String?

    var remoteImageURL: URL? {
        if imageUrl.hasPrefix("http://") || imageUrl.hasPrefix("https://") {
            return URL(string: imageUrl)
        }

        let normalizedPath = imageUrl.hasPrefix("/") ? imageUrl : "/\(imageUrl)"
        return URL(string: "https://anky.app\(normalizedPath)")
    }
}

struct AltarBurner: Codable, Equatable, Identifiable {
    let userIdentifier: String
    let displayName: String
    let totalUsdc: Int
    let burnCount: Int

    var id: String { userIdentifier }
}

struct RecentAltarBurn: Codable, Equatable, Identifiable {
    let displayName: String
    let amountUsdc: Int
    let createdAt: String

    var id: String { "\(displayName)-\(createdAt)-\(amountUsdc)" }
}

struct AltarPaymentIntentRequest: Codable, Equatable {
    let amountCents: Int
}

struct AltarPaymentIntentResponse: Codable, Equatable {
    let clientSecret: String
    let paymentIntentId: String
}

struct RecordApplePayBurnRequest: Codable, Equatable {
    let paymentIntentId: String
    let solanaAddress: String
    let displayName: String?
}

// MARK: - QR Seal Auth

struct QRSealChallenge: Identifiable, Equatable {
    let token: String

    var id: String { token }
}

struct QRSealRequest: Codable, Equatable {
    let token: String
    let signature: String
    let solanaAddress: String
}

struct QRSealResponse: Codable, Equatable {
    let ok: Bool
    let solanaAddress: String
}

struct SharedAnkyLink: Identifiable, Equatable {
    let id: String
}

// MARK: - Child Worlds

struct ChildProfile: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let birthdate: String
    let derivedWalletAddress: String
    let emojiPattern: [String]
    let parentWalletAddress: String
    let createdAt: String
}

struct Cuentacuentos: Codable, Identifiable, Equatable {
    let id: String
    let writingId: String
    let title: String
    let content: String
    let guidancePhases: [GuidancePhase]
    let played: Bool
    let generatedAt: String

    // Translated full-text content
    let contentEs: String?
    let contentZh: String?
    let contentHi: String?
    let contentAr: String?

    func translatedContent(for languageId: String) -> String {
        switch languageId {
        case "es": return contentEs ?? content
        case "zh": return contentZh ?? content
        case "hi": return contentHi ?? content
        case "ar": return contentAr ?? content
        default: return content
        }
    }
}

struct CreateChildRequest: Codable, Equatable {
    let name: String
    let birthdate: String
    let derivedWalletAddress: String
    let emojiPattern: [String]
}

private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == DynamicCodingKeys {
    func decodeFlexibleString(forKeys keys: [String]) throws -> String {
        for key in keys {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            if let value = try decodeIfPresent(String.self, forKey: codingKey) {
                return value
            }
        }
        throw DecodingError.keyNotFound(
            DynamicCodingKeys(stringValue: keys.first ?? "value")!,
            .init(codingPath: codingPath, debugDescription: "Missing expected string value.")
        )
    }

    func decodeFlexibleOptionalString(forKeys keys: [String]) throws -> String? {
        for key in keys {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            if let value = try decodeIfPresent(String.self, forKey: codingKey) {
                return value
            }
        }
        return nil
    }

    func decodeFlexibleDouble(forKeys keys: [String], defaultValue: Double) throws -> Double {
        for key in keys {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            if let value = try decodeIfPresent(Double.self, forKey: codingKey) {
                return value
            }
            if let value = try decodeIfPresent(Int.self, forKey: codingKey) {
                return Double(value)
            }
        }
        return defaultValue
    }

    func decodeFlexibleOptionalDouble(forKeys keys: [String]) throws -> Double? {
        for key in keys {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            if let value = try decodeIfPresent(Double.self, forKey: codingKey) {
                return value
            }
            if let value = try decodeIfPresent(Int.self, forKey: codingKey) {
                return Double(value)
            }
        }
        return nil
    }

    func decodeFlexibleInt(forKeys keys: [String], defaultValue: Int) throws -> Int {
        for key in keys {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            if let value = try decodeIfPresent(Int.self, forKey: codingKey) {
                return value
            }
            if let value = try decodeIfPresent(Double.self, forKey: codingKey) {
                return Int(value)
            }
        }
        return defaultValue
    }

    func decodeFlexibleBool(forKeys keys: [String], defaultValue: Bool) throws -> Bool {
        for key in keys {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            if let value = try decodeIfPresent(Bool.self, forKey: codingKey) {
                return value
            }
            if let value = try decodeIfPresent(Int.self, forKey: codingKey) {
                return value != 0
            }
            if let value = try decodeIfPresent(String.self, forKey: codingKey) {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalized == "true" || normalized == "1" || normalized == "yes" {
                    return true
                }
                if normalized == "false" || normalized == "0" || normalized == "no" {
                    return false
                }
            }
        }
        return defaultValue
    }

    func decodeFlexibleArray<T: Decodable>(_ type: T.Type, forKeys keys: [String], defaultValue: [T]) throws -> [T] {
        for key in keys {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            if let value = try decodeIfPresent([T].self, forKey: codingKey) {
                return value
            }
        }
        return defaultValue
    }

    func decodeFlexibleOptionalNestedObject<T: Decodable>(_ type: T.Type, forKeys keys: [String]) throws -> T? {
        for key in keys {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            if let value = try decodeIfPresent(T.self, forKey: codingKey) {
                return value
            }
        }
        return nil
    }
}

struct LocalWritingCapture: Equatable {
    static let requiredDurationForAnky: Double = AnkyContract.Qualification.minimumDurationSeconds
    static let requiredWordCountForAnky = AnkyContract.Qualification.minimumWordCount

    let sessionId: String
    let prompt: String
    let text: String
    let duration: Double
    let wordCount: Int
    let keystrokeDeltas: [Double]
    let finishedAt: Date
    let estimatedFlowScore: Double
    let nowSlug: String?
    let ankySessionString: String?
    let ankyFilePath: String?
    let sessionHash: String?

    init(
        sessionId: String,
        prompt: String,
        text: String,
        duration: Double,
        wordCount: Int,
        keystrokeDeltas: [Double],
        finishedAt: Date,
        estimatedFlowScore: Double,
        nowSlug: String? = nil,
        ankySessionString: String? = nil,
        ankyFilePath: String? = nil,
        sessionHash: String? = nil
    ) {
        self.sessionId = sessionId
        self.prompt = prompt
        self.text = text
        self.duration = duration
        self.wordCount = wordCount
        self.keystrokeDeltas = keystrokeDeltas
        self.finishedAt = finishedAt
        self.estimatedFlowScore = estimatedFlowScore
        self.nowSlug = nowSlug
        self.ankySessionString = ankySessionString
        self.ankyFilePath = ankyFilePath
        self.sessionHash = sessionHash
    }

    var qualifiesForAnky: Bool {
        Self.qualifiesForAnky(text: text, duration: duration)
    }

    var request: MobileWriteRequest {
        MobileWriteRequest(
            text: text,
            duration: duration,
            sessionId: sessionId,
            keystrokeDeltas: keystrokeDeltas,
            isCheckpoint: nil,
            nowSlug: nowSlug
        )
    }

    func checkpointRequest(text: String, duration: Double, keystrokeDeltas: [Double]) -> MobileWriteRequest {
        MobileWriteRequest(
            text: text,
            duration: duration,
            sessionId: sessionId,
            keystrokeDeltas: keystrokeDeltas,
            isCheckpoint: true,
            nowSlug: nowSlug
        )
    }

    static func qualifiesForAnky(text: String, duration: Double) -> Bool {
        AnkyContract.Qualification.qualifies(text: text, durationSeconds: duration)
    }

    static func wordCount(in text: String) -> Int {
        AnkyContract.Qualification.wordCount(in: text)
    }
}

// MARK: - Voice Recordings

enum VoiceRecordingStatus: String, Codable {
    case pending
    case approved
    case rejected
}

struct VoiceRecording: Codable, Identifiable {
    let id: String
    let attemptNumber: Int
    let status: VoiceRecordingStatus
    let durationSeconds: Double
    let createdAt: String
    let audioUrl: String?
    let rejectionReason: String?
    let language: String?
    let fullListenCount: Int?
    let userId: String?
    let username: String?

    var createdAtDate: Date? {
        ISO8601DateFormatter().date(from: createdAt)
    }

    var durationLabel: String {
        let total = max(Int(durationSeconds.rounded(.down)), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var statusLabel: String {
        switch status {
        case .pending: return "pending"
        case .approved: return "approved"
        case .rejected: return "rejected"
        }
    }

    var listenCountLabel: String {
        let count = fullListenCount ?? 0
        return count == 1 ? "1 listen" : "\(count) listens"
    }
}

struct VoiceRecordingCreateResponse: Codable {
    let recordingId: String
    let status: String
    let uploadUrl: String
}

struct StoryVoice: Codable {
    let recordingId: String
    let audioUrl: String
    let language: String
    let durationSeconds: Double
    let userId: String?
    let username: String?
}

// MARK: - Settings

struct UserSettingsResponse: Codable {
    let preferredLanguage: String?
    let fontSize: Int?
    let fontFamily: String?
    let theme: String?
    let idleTimeout: Int?
    let keyboardLayout: String?
}

struct UserSettingsUpdate: Codable {
    var preferredLanguage: String?
    var fontSize: Int?
}

struct DeviceRegistration: Encodable {
    let token: String
    let platform: String
}

// MARK: - Mirror Mint (Solana cNFT, backend-driven)

struct MirrorMintRequest: Codable {
    let writingSessionId: String
    let recipient: String
}

struct MirrorMintResponse: Codable {
    let success: Bool
    let mirrorId: String?
    let kingdom: String?
    let kingdomChakra: String?
    let kingdomId: Int?
    let txSignature: String?
    let items: MirrorItemsWrapper?
    let imageUrl: String?
    let error: String?
    let alreadyMinted: Bool?
    let existingTxSignature: String?
}

struct MirrorItemsWrapper: Codable {
    let items: [KingdomItem]?
}

struct KingdomItem: Codable, Identifiable, Hashable {
    let kingdom: String
    let chakra: String
    let name: String
    let description: String
    let material: String

    var id: String { "\(kingdom)-\(name)" }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: KingdomItem, rhs: KingdomItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct UserItemsResponse: Codable {
    let mirrorId: String?
    let items: [KingdomItem]?
    let source: String?      // "mirror", "derived", or "none"
    let message: String?
}

// MARK: - Guidance

struct GuidancePhase: Codable, Hashable, Identifiable {
    let name: String
    let phaseType: String
    let durationSeconds: Int
    let narration: String
    let imageUrl: String?

    // Translated narrations
    let narrationEs: String?
    let narrationZh: String?
    let narrationHi: String?
    let narrationAr: String?

    var id: String {
        "\(name)-\(durationSeconds)-\(phaseType)"
    }

    func translatedNarration(for languageId: String) -> String {
        switch languageId {
        case "es": return narrationEs ?? narration
        case "zh": return narrationZh ?? narration
        case "hi": return narrationHi ?? narration
        case "ar": return narrationAr ?? narration
        default: return narration
        }
    }
}

struct GuidanceSession: Codable, Equatable, Identifiable {
    let id: String?
    let title: String
    let description: String
    let durationSeconds: Int
    let phases: [GuidancePhase]
}

// MARK: - Sealed Write (enclave endpoint)

struct EnclavePublicKeyResponse: Codable {
    let encryptionPublicKey: String  // base64 X25519 pubkey
}

/// Request body for POST /api/sealed-write.
/// Uses explicit CodingKeys to emit camelCase JSON (the shared encoder uses snake_case).
struct SealedWriteRequest: Codable {
    let sessionId: String
    let ciphertext: String           // base64: AES-256-GCM encrypted writing
    let nonce: String                // base64: 12-byte random nonce
    let tag: String                  // base64: GCM auth tag
    let ephemeralPublicKey: String   // base64: ephemeral X25519 public key
    let sessionHash: String          // hex: SHA256 of PLAINTEXT writing
    let duration: Double
    let wordCount: Int
    let userEncryptedKey: String?    // base64: user's iCloud Keychain X25519 public key (optional)

    enum CodingKeys: String, CodingKey {
        case sessionId
        case ciphertext
        case nonce
        case tag
        case ephemeralPublicKey
        case sessionHash
        case duration
        case wordCount
        case userEncryptedKey
    }
}

struct SealedWriteResponse: Codable {
    let ok: Bool
    let sessionId: String?
    let sessionHash: String?
    let ankyId: String?
    let isAnky: Bool?
    let solanaTx: String?
}

// MARK: - Relay (.anky session protocol)

struct RelayEncryptedPayload: Codable {
    let ephemeralPublicKey: String  // base64
    let nonce: String              // base64
    let tag: String                // base64
    let ciphertext: String         // base64
    let sessionHash: String        // hex SHA-256 of session string
}

struct RelayRequest: Codable {
    let encrypted: RelayEncryptedPayload
    let writerPubkey: String  // base58 Solana address
}

struct RelayResponse: Codable {
    let hash: String?
    let arweaveTx: String?
    let solanaTx: String?
    let explorerUrl: String?
    let arweaveUrl: String?
}

// MARK: - Now Sessions

enum NowMode: String, Codable {
    case sticker
    case live
}

struct CreateNowRequest: Codable {
    let prompt: String
    let mode: NowMode
    let latitude: Double?
    let longitude: Double?
}

struct CreateNowResponse: Codable {
    let slug: String
    let qrUrl: String
}

struct NowSession: Codable, Identifiable {
    let id: String?
    let sessionId: String?
    let preview: String?
    let wordCount: Int?
    let displayName: String?

    var stableId: String { id ?? sessionId ?? UUID().uuidString }
}

struct NowRoom: Codable {
    let slug: String
    let prompt: String
    let mode: NowMode
    let started: Bool?
    let startsAt: String?
    let presenceCount: Int?
    let promptImageUrl: String?
    let promptImageStatus: String?
    let sessions: [NowSession]?
    let latitude: Double?
    let longitude: Double?
}

struct NowJoinResponse: Codable {
    let ok: Bool
    let presenceCount: Int?
}

struct NowStartResponse: Codable {
    let ok: Bool
    let startsAt: String?
}

struct NowHeartbeatResponse: Codable {
    let ok: Bool
    let presenceCount: Int?
}
