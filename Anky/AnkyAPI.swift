//
//  AnkyAPI.swift
//  Anky
//

import Foundation

final class AnkyAPI {
    static let shared = AnkyAPI()

    private let baseURL: URL
    private let webBaseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        baseURL: URL = URL(string: "https://anky.app/swift/v2")!,
        webBaseURL: URL? = nil,
        session: URLSession = .shared
    ) {
        let normalizedBaseURL = baseURL.appendingPathComponent("")
        self.baseURL = normalizedBaseURL
        if let webBaseURL {
            self.webBaseURL = webBaseURL.appendingPathComponent("")
        } else {
            var components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false)
            components?.path = "/"
            components?.query = nil
            components?.fragment = nil
            self.webBaseURL = components?.url?.appendingPathComponent("") ?? URL(string: "https://anky.app/")!
        }
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

    func chatQuick(writing: String, message: String, history: [ChatHistoryItem]) async throws -> String {
        let request = QuickChatRequest(writing: writing, message: message, history: history)
        let response: QuickChatResponse = try await post(
            "/api/chat-quick",
            body: request,
            requiresAuth: false,
            baseURLOverride: webBaseURL
        )
        return response.response
    }

    func getWritingStatus(sessionId: String) async throws -> WritingStatusResponse {
        try await get("/writing/\(sessionId)/status")
    }

    func getPrompt(id: String) async throws -> PromptResponse {
        try await get("/prompt/\(id)", requiresAuth: false)
    }

    func altar() async throws -> AltarState {
        try await get("/api/altar", requiresAuth: false, baseURLOverride: webBaseURL)
    }

    func createAltarPaymentIntent(amountCents: Int) async throws -> AltarPaymentIntentResponse {
        try await post(
            "/api/altar/payment-intent",
            body: AltarPaymentIntentRequest(amountCents: amountCents),
            requiresAuth: false,
            baseURLOverride: webBaseURL
        )
    }

    func recordApplePayBurn(
        paymentIntentId: String,
        solanaAddress: String,
        displayName: String?
    ) async throws -> AltarState {
        try await post(
            "/api/altar/apple-pay",
            body: RecordApplePayBurnRequest(
                paymentIntentId: paymentIntentId,
                solanaAddress: solanaAddress,
                displayName: displayName
            ),
            requiresAuth: false,
            baseURLOverride: webBaseURL
        )
    }

    func sealQRChallenge(
        token: String,
        signature: String,
        solanaAddress: String
    ) async throws -> QRSealResponse {
        try await post(
            "/api/auth/qr/seal",
            body: QRSealRequest(token: token, signature: signature, solanaAddress: solanaAddress),
            requiresAuth: false,
            baseURLOverride: webBaseURL
        )
    }

    func createChild(_ request: CreateChildRequest) async throws -> ChildProfile {
        try await post("/children", body: request)
    }

    func getChildren() async throws -> [ChildProfile] {
        try await get("/children")
    }

    func getCuentacuentosReady(childId: String?) async throws -> Cuentacuentos? {
        try await get(cuentacuentosPath("/cuentacuentos/ready", childId: childId))
    }

    func getCuentacuentosHistory(childId: String?) async throws -> [Cuentacuentos] {
        try await get(cuentacuentosPath("/cuentacuentos/history", childId: childId))
    }

    func completeCuentacuentos(id: String) async throws {
        let _: EmptyResponse = try await post("/cuentacuentos/\(id)/complete", body: EmptyRequest())
    }

    // MARK: - Voice Recordings

    /// Step 1: Create a recording via multipart POST and get a presigned R2 upload URL.
    func createRecording(
        storyId: String,
        audioData: Data,
        language: String,
        durationSeconds: Double
    ) async throws -> VoiceRecordingCreateResponse {
        let boundary = UUID().uuidString
        let url = try resolveURL(for: "/stories/\(storyId)/recordings")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let token = sessionToken, !token.isEmpty else {
            throw AnkyError.missingSession
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body = Data()
        // audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        // language
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(language)\r\n".data(using: .utf8)!)
        // duration_seconds
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"duration_seconds\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(durationSeconds)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

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

        if httpResponse.statusCode == 429 {
            throw AnkyError.api("Maximum recordings reached for this story.")
        }

        if httpResponse.statusCode >= 400 {
            let errorMessage = (try? decoder.decode(ErrorResponse.self, from: data))?.error
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AnkyError.api(errorMessage)
        }

        do {
            return try decoder.decode(VoiceRecordingCreateResponse.self, from: data)
        } catch {
            throw AnkyError.transport("Unable to decode the server response.")
        }
    }

    /// Step 2: PUT the raw audio data to the presigned R2 URL.
    func uploadAudioToR2(uploadUrl: String, audioData: Data) async throws {
        guard let url = URL(string: uploadUrl) else {
            throw AnkyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AnkyError.transport("Failed to upload audio to storage.")
        }
    }

    func getRecordings(storyId: String) async throws -> [VoiceRecording] {
        try await get("/stories/\(storyId)/recordings")
    }

    /// Uses Accept-Language header for language matching.
    func getStoryVoice(storyId: String, language: String) async throws -> StoryVoice {
        let url = try resolveURL(for: "/stories/\(storyId)/voice")

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(language, forHTTPHeaderField: "Accept-Language")

        guard let token = sessionToken, !token.isEmpty else {
            throw AnkyError.missingSession
        }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
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
            let errorMessage = (try? decoder.decode(ErrorResponse.self, from: data))?.error
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AnkyError.api(errorMessage)
        }

        do {
            return try decoder.decode(StoryVoice.self, from: data)
        } catch {
            throw AnkyError.transport("Unable to decode the server response.")
        }
    }

    func markListenComplete(storyId: String, recordingId: String) async throws {
        let _: EmptyResponse = try await post(
            "/stories/\(storyId)/recordings/\(recordingId)/complete",
            body: EmptyRequest()
        )
    }

    // MARK: - Sealed Sessions

    func sealSession(_ sealed: SealedSession) async throws -> SealSessionResponse {
        try await post("/api/sessions/seal", body: sealed, baseURLOverride: webBaseURL)
    }

    // MARK: - Mirror (Solana cNFT, backend-driven)

    func mintMirror(writingSessionId: String, recipient: String) async throws -> MirrorMintResponse {
        try await post("/mirror/mint", body: MirrorMintRequest(writingSessionId: writingSessionId, recipient: recipient))
    }

    func getUserItems() async throws -> UserItemsResponse {
        try await get("/you/items")
    }

    // MARK: - Settings

    func getSettings() async throws -> UserSettingsResponse {
        try await get("/settings")
    }

    func patchSettings(_ update: UserSettingsUpdate) async throws -> UserSettingsResponse {
        try await patch("/settings", body: update)
    }

    // MARK: - Device / Push

    func registerDevice(token: String, platform: String) async throws {
        let _: EmptyResponse = try await post("/devices", body: DeviceRegistration(token: token, platform: platform))
    }

    func unregisterDevice(platform: String) async throws {
        let _: EmptyResponse = try await delete("/devices?platform=\(platform)")
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

    func get<T: Decodable>(
        _ path: String,
        requiresAuth: Bool = true,
        baseURLOverride: URL
    ) async throws -> T {
        try await request("GET", path: path, bodyData: nil, requiresAuth: requiresAuth, baseURLOverride: baseURLOverride)
    }

    func post<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        requiresAuth: Bool = true,
        baseURLOverride: URL? = nil
    ) async throws -> T {
        let bodyData = try encoder.encode(body)
        return try await request(
            "POST",
            path: path,
            bodyData: bodyData,
            requiresAuth: requiresAuth,
            baseURLOverride: baseURLOverride
        )
    }

    func patch<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        requiresAuth: Bool = true
    ) async throws -> T {
        let bodyData = try encoder.encode(body)
        return try await request("PATCH", path: path, bodyData: bodyData, requiresAuth: requiresAuth)
    }

    func delete<T: Decodable>(_ path: String, requiresAuth: Bool = true) async throws -> T {
        try await request("DELETE", path: path, bodyData: nil, requiresAuth: requiresAuth)
    }

    private func request<T: Decodable>(
        _ method: String,
        path: String,
        bodyData: Data?,
        requiresAuth: Bool,
        baseURLOverride: URL? = nil
    ) async throws -> T {
        let url = try resolveURL(for: path, relativeTo: baseURLOverride ?? baseURL)

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
        try resolveURL(for: path, relativeTo: baseURL)
    }

    private func resolveURL(for path: String, relativeTo baseURL: URL) throws -> URL {
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

    private func cuentacuentosPath(_ path: String, childId: String?) -> String {
        guard let childId,
              let encodedChildID = childId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return path
        }

        return "\(path)?childId=\(encodedChildID)"
    }
}

private struct EmptyRequest: Encodable {}
