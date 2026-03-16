//
//  AnkyAPI.swift
//  Anky
//

import Foundation

final class AnkyAPI {
    static let shared = AnkyAPI()

    private let baseURL: URL
    private let legacyBaseURL = URL(string: "https://anky.app/swift/v1")!
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        baseURL: URL = URL(string: "https://anky.app/swift/v2")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL.appendingPathComponent("")
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    var sessionToken: String? {
        KeychainHelper.get(AppState.sessionTokenKey)
    }

    func authChallenge(walletAddress: String) async throws -> SeedAuthChallengeResponse {
        try await post(
            "/auth/challenge",
            body: SeedAuthChallengeRequest(walletAddress: walletAddress),
            requiresAuth: false
        )
    }

    func verifyAuthChallenge(
        walletAddress: String,
        challengeID: String,
        signature: String
    ) async throws -> SeedAuthVerifyResponse {
        try await post(
            "/auth/verify",
            body: SeedAuthVerifyRequest(walletAddress: walletAddress, challengeId: challengeID, signature: signature),
            requiresAuth: false
        )
    }

    func me() async throws -> UserProfile {
        try await get("/me")
    }

    func logout() async throws -> EmptyResponse {
        try await delete("/auth/session")
    }

    func writings() async throws -> [WritingItem] {
        try await get("/writings")
    }

    func submitWriting(_ request: MobileWriteRequest) async throws -> MobileWriteResponse {
        try await post("/write", body: request)
    }

    // Legacy surfaces remain available in code, but the new product flow does not route into them.
    func meditationReady() async throws -> ReadyResponse {
        try await legacyGet("/meditation/ready")
    }

    func meditationHistory() async throws -> [MeditationHistoryItem] {
        try await legacyGet("/meditation/history")
    }

    func startMeditation(minutes: Int) async throws -> MeditationStartResponse {
        try await legacyPost("/meditation/start", body: MeditationStartRequest(durationMinutes: minutes))
    }

    func completeMeditation(_ request: MeditationCompleteRequest) async throws -> MeditationCompleteResponse {
        try await legacyPost("/meditation/complete", body: request)
    }

    func breathworkReady() async throws -> ReadyResponse {
        try await legacyGet("/breathwork/ready")
    }

    func breathworkSession(style: String) async throws -> GuidanceSession {
        let encodedStyle = style.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? style
        return try await legacyGet("/breathwork/session?style=\(encodedStyle)")
    }

    func completeBreathwork(_ request: BreathworkCompleteRequest) async throws -> EmptyResponse {
        try await legacyPost("/breathwork/complete", body: request)
    }

    func breathworkHistory() async throws -> BreathworkHistoryResponse {
        try await legacyGet("/breathwork/history")
    }

    func sadhanaCommitments() async throws -> [SadhanaCommitment] {
        try await legacyGet("/sadhana")
    }

    func createSadhana(_ request: SadhanaCommitmentRequest) async throws -> SadhanaCommitment {
        try await legacyPost("/sadhana", body: request)
    }

    func sadhanaDetail(id: String) async throws -> SadhanaDetail {
        try await legacyGet("/sadhana/\(id)")
    }

    func checkInSadhana(id: String, request: SadhanaCheckinRequest) async throws -> SadhanaCheckin {
        try await legacyPost("/sadhana/\(id)/checkin", body: request)
    }

    func facilitators() async throws -> [Facilitator] {
        try await legacyGet("/facilitators")
    }

    func recommendedFacilitators() async throws -> FacilitatorRecommendationResponse {
        try await legacyGet("/facilitators/recommended")
    }

    func facilitator(id: String) async throws -> FacilitatorDetail {
        try await legacyGet("/facilitators/\(id)", requiresAuth: false)
    }

    func applyAsFacilitator(_ request: FacilitatorApplicationRequest) async throws -> FacilitatorApplicationResponse {
        try await legacyPost("/facilitators/apply", body: request)
    }

    func reviewFacilitator(id: String, request: FacilitatorReviewRequest) async throws -> EmptyResponse {
        try await legacyPost("/facilitators/\(id)/review", body: request)
    }

    func bookFacilitator(id: String, request: FacilitatorBookingRequest) async throws -> FacilitatorBookingResponse {
        try await legacyPost("/facilitators/\(id)/book", body: request)
    }

    func send(_ pendingAction: PendingAction) async throws {
        _ = try await request(
            pendingAction.method,
            path: pendingAction.path,
            bodyData: pendingAction.bodyData,
            requiresAuth: true
        ) as EmptyResponse
    }

    func get<T: Decodable>(_ path: String, requiresAuth: Bool = true) async throws -> T {
        try await request("GET", path: path, bodyData: nil, requiresAuth: requiresAuth)
    }

    func post<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        requiresAuth: Bool = true
    ) async throws -> T {
        let bodyData = try encoder.encode(body)
        return try await request("POST", path: path, bodyData: bodyData, requiresAuth: requiresAuth)
    }

    func delete<T: Decodable>(_ path: String, requiresAuth: Bool = true) async throws -> T {
        try await request("DELETE", path: path, bodyData: nil, requiresAuth: requiresAuth)
    }

    private func legacyGet<T: Decodable>(_ path: String, requiresAuth: Bool = true) async throws -> T {
        try await request("GET", path: legacyURLString(for: path), bodyData: nil, requiresAuth: requiresAuth)
    }

    private func legacyPost<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        requiresAuth: Bool = true
    ) async throws -> T {
        let bodyData = try encoder.encode(body)
        return try await request("POST", path: legacyURLString(for: path), bodyData: bodyData, requiresAuth: requiresAuth)
    }

    private func request<T: Decodable>(
        _ method: String,
        path: String,
        bodyData: Data?,
        requiresAuth: Bool
    ) async throws -> T {
        let url = try resolveURL(for: path)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if requiresAuth {
            guard let token = sessionToken, !token.isEmpty else {
                throw AnkyError.missingSession
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnkyError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            KeychainHelper.delete(AppState.sessionTokenKey)
            throw AnkyError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            let errorMessage = (try? decoder.decode(ErrorResponse.self, from: data))?.error ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AnkyError.api(errorMessage)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AnkyError.transport("Unable to decode the server response.")
        }
    }

    private func mapTransportError(_ error: Error) -> AnkyError {
        if let urlError = error as? URLError {
            return .transport(urlError.localizedDescription)
        }

        return .transport(error.localizedDescription)
    }

    func resolveURL(for path: String) throws -> URL {
        if path.hasPrefix("http") {
            guard let externalURL = URL(string: path) else {
                throw AnkyError.invalidURL
            }
            return externalURL
        }

        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let relativeURL = URL(string: normalizedPath, relativeTo: baseURL) else {
            throw AnkyError.invalidURL
        }

        return relativeURL.absoluteURL
    }

    private func legacyURLString(for path: String) -> String {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return legacyBaseURL.appendingPathComponent(normalizedPath).absoluteString
    }
}
