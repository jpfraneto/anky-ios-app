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

struct MobileWriteRequest: Codable {
    let text: String
    let duration: Double
    let sessionId: String?
    let keystrokeDeltas: [Double]?
}

struct MobileWriteResponse: Codable {
    let ok: Bool
    let sessionId: String
    let isAnky: Bool
    let wordCount: Int
    let flowScore: Double?
    let persisted: Bool?
    let response: String?
    let ankyId: String?
    let walletAddress: String?
    let error: String?
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
            keystrokeDeltas: keystrokeDeltas
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

// MARK: - Guidance

enum GuidancePhaseKind: String {
    case narration
    case breathing
    case hold
    case rest
    case bodyScan = "body_scan"
    case visualization
}

struct GuidancePhase: Codable, Hashable, Identifiable {
    let name: String
    let phaseType: String
    let durationSeconds: Int
    let narration: String
    let inhaleSeconds: Double?
    let exhaleSeconds: Double?
    let holdSeconds: Double?
    let reps: Int?

    var id: String {
        "\(name)-\(durationSeconds)-\(phaseType)"
    }

    var kind: GuidancePhaseKind {
        GuidancePhaseKind(rawValue: phaseType) ?? .narration
    }
}

struct GuidanceSession: Codable, Equatable, Identifiable {
    let id: String?
    let style: String?
    let title: String
    let description: String
    let durationSeconds: Int
    let backgroundBeatBpm: Int
    let phases: [GuidancePhase]
}

struct ReadyResponse: Codable, Equatable {
    let status: String
    let session: GuidanceSession?
    let style: String?
}

struct MeditationStartRequest: Codable {
    let durationMinutes: Int
}

struct MeditationStartResponse: Codable {
    let sessionId: String
    let durationTarget: Int
}

struct MeditationCompleteRequest: Codable {
    let sessionId: String
    let actualSeconds: Int
    let completed: Bool
}

struct MeditationCompleteResponse: Codable {
    let ok: Bool
    let totalMeditations: Int
    let currentStreak: Int
}

struct MeditationHistoryItem: Codable, Identifiable {
    let id: String
    let durationTarget: Int
    let durationActual: Int?
    let completed: Bool
    let createdAt: String
}

struct BreathworkCompleteRequest: Codable {
    let sessionId: String
    let notes: String?
}

struct BreathworkHistoryItem: Codable, Identifiable {
    let id: String
    let sessionId: String
    let style: String
    let completedAt: String
}

struct BreathworkHistoryResponse: Codable {
    let history: [BreathworkHistoryItem]
}

// MARK: - Sadhana

struct SadhanaCommitmentRequest: Codable {
    let title: String
    let description: String?
    let frequency: String
    let durationMinutes: Int
    let targetDays: Int
}

struct SadhanaCommitment: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let frequency: String
    let durationMinutes: Int
    let targetDays: Int
    let startDate: String
    let isActive: Bool
    let createdAt: String
    let totalCheckins: Int
    let completedCheckins: Int
}

struct SadhanaCheckinRequest: Codable {
    let completed: Bool
    let notes: String?
    let date: String?
}

struct SadhanaCheckin: Codable, Identifiable {
    let id: String
    let date: String
    let completed: Bool
    let notes: String?
    let createdAt: String
}

struct SadhanaDetail: Codable {
    let id: String
    let title: String
    let description: String?
    let frequency: String
    let durationMinutes: Int
    let targetDays: Int
    let startDate: String
    let isActive: Bool
    let createdAt: String
    let checkins: [SadhanaCheckin]
}

// MARK: - Facilitators

struct Facilitator: Codable, Identifiable {
    let id: String
    let name: String
    let bio: String
    let specialties: [String]
    let approach: String?
    let sessionRateUsd: Double
    let bookingUrl: String?
    let contactMethod: String?
    let profileImageUrl: String?
    let location: String?
    let languages: [String]
    let status: String
    let avgRating: Double
    let totalReviews: Int
    let totalSessions: Int
    let matchReason: String?
}

struct FacilitatorRecommendationResponse: Codable {
    let facilitators: [Facilitator]
    let message: String?
}

struct FacilitatorReview: Codable, Identifiable {
    let id: String
    let rating: Int
    let reviewText: String?
    let createdAt: String
}

struct FacilitatorDetail: Codable, Identifiable {
    let id: String
    let name: String
    let bio: String
    let specialties: [String]
    let approach: String?
    let sessionRateUsd: Double
    let bookingUrl: String?
    let contactMethod: String?
    let profileImageUrl: String?
    let location: String?
    let languages: [String]
    let status: String
    let avgRating: Double
    let totalReviews: Int
    let totalSessions: Int
    let matchReason: String?
    let reviews: [FacilitatorReview]
}

struct FacilitatorApplicationRequest: Codable {
    let name: String
    let bio: String
    let specialties: [String]
    let approach: String?
    let sessionRateUsd: Double
    let bookingUrl: String?
    let contactMethod: String?
    let profileImageUrl: String?
    let location: String?
    let languages: [String]
}

struct FacilitatorApplicationResponse: Codable {
    let ok: Bool
    let id: String
    let status: String
    let message: String
}

struct FacilitatorReviewRequest: Codable {
    let rating: Int
    let reviewText: String?
}

struct FacilitatorBookingRequest: Codable {
    let paymentTxHash: String?
    let stripePaymentId: String?
    let shareContext: Bool
}

struct FacilitatorBookingResponse: Codable {
    let ok: Bool
    let bookingId: String
    let facilitatorName: String
    let amountUsd: Double
    let platformFeeUsd: Double
    let facilitatorReceivesUsd: Double
    let bookingUrl: String?
    let contactMethod: String?
}
