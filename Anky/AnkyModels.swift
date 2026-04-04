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

struct MobileWriteRequest: Codable {
    let text: String
    let duration: Double
    let sessionId: String?
    let keystrokeDeltas: [Double]?
    let isCheckpoint: Bool?
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
        createdAt: String
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)

        id = try container.decodeFlexibleString(forKeys: ["id", "anky_id", "session_id"])
        content = try container.decodeFlexibleString(forKeys: ["content", "text"])
        durationSeconds = try container.decodeFlexibleDouble(forKeys: ["duration_seconds", "duration"], defaultValue: 0)
        wordCount = try container.decodeFlexibleInt(forKeys: ["word_count"], defaultValue: LocalWritingCapture.wordCount(in: content))
        isAnky = try container.decodeFlexibleBool(forKeys: ["is_anky"], defaultValue: false)
        response = try container.decodeFlexibleOptionalString(forKeys: ["response", "reflection"])
        ankyId = try container.decodeFlexibleOptionalString(forKeys: ["anky_id"])
        ankyTitle = try container.decodeFlexibleOptionalString(forKeys: ["anky_title", "title"])
        ankyImagePath = try container.decodeFlexibleOptionalString(forKeys: ["anky_image_path", "image_path"])
        createdAt = try container.decodeFlexibleString(forKeys: ["created_at", "updated_at"])
    }
}

enum CachedWritingSyncState: String, Codable {
    case synced
    case pending
    case localOnly
}

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
        syncState: CachedWritingSyncState
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
    }

    init(item: WritingItem, prompt: String = "") {
        self.init(
            id: item.id,
            prompt: prompt,
            content: item.content,
            durationSeconds: item.durationSeconds,
            wordCount: item.wordCount,
            isAnky: item.isAnky,
            response: item.response,
            ankyId: item.ankyId,
            ankyTitle: item.ankyTitle,
            ankyImagePath: item.ankyImagePath,
            createdAt: Self.isoFormatter.date(from: item.createdAt) ?? .now,
            flowScore: nil,
            syncState: .synced
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
        }
        return defaultValue
    }
}

struct LocalWritingCapture: Equatable {
    static let requiredDurationForAnky: Double = 480
    static let requiredWordCountForAnky = 300

    let sessionId: String
    let prompt: String
    let text: String
    let duration: Double
    let wordCount: Int
    let keystrokeDeltas: [Double]
    let finishedAt: Date
    let estimatedFlowScore: Double

    var qualifiesForAnky: Bool {
        Self.qualifiesForAnky(text: text, duration: duration)
    }

    var request: MobileWriteRequest {
        MobileWriteRequest(
            text: text,
            duration: duration,
            sessionId: sessionId,
            keystrokeDeltas: keystrokeDeltas,
            isCheckpoint: nil
        )
    }

    func checkpointRequest(text: String, duration: Double, keystrokeDeltas: [Double]) -> MobileWriteRequest {
        MobileWriteRequest(
            text: text,
            duration: duration,
            sessionId: sessionId,
            keystrokeDeltas: keystrokeDeltas,
            isCheckpoint: true
        )
    }

    static func qualifiesForAnky(text: String, duration: Double) -> Bool {
        duration >= requiredDurationForAnky && wordCount(in: text) >= requiredWordCountForAnky
    }

    static func wordCount(in text: String) -> Int {
        text
            .split { $0.isWhitespace || $0.isNewline }
            .count
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
