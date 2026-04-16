//
//  AnkyAPI.swift
//  Anky
//

import CryptoKit
import Foundation

struct AnkySubmitStreamFailure: LocalizedError, Equatable {
    let stage: String
    let retryable: Bool

    var errorDescription: String? {
        "Anky submit failed during \(stage)."
    }
}

final class AnkyAPI {
    static let shared = AnkyAPI()

    private let baseURL: URL
    private let webBaseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private static let submitDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

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

    func connectedDevices() async throws -> [ConnectedDevice] {
        let response: ConnectedDevicesResponse = try await get("/auth/sessions")
        return response.items
    }

    func revokeConnectedDevice(id: String) async throws {
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: EmptyResponse = try await delete("/auth/sessions/\(encodedID)")
    }

    func writings() async throws -> [WritingItem] {
        try await get("/writings")
    }

    /// Legacy `/swift/v2/write` submit path kept for compatibility with older surfaces.
    func submitWriting(_ request: MobileWriteRequest) async throws -> MobileWriteResponse {
        try await post("/write", body: request)
    }

    func submitWriting(_ capture: LocalWritingCapture, kingdom: Kingdom) async throws -> MobileWriteResponse {
        let result = try await submitAnkyCaptureUntilStored(capture, kingdom: kingdom)
        return MobileWriteResponse(
            ok: true,
            sessionId: capture.sessionId,
            outcome: "anky",
            wordCount: capture.wordCount,
            durationSeconds: capture.duration,
            flowScore: capture.estimatedFlowScore,
            persisted: true,
            spawned: SpawnedArtifacts(
                ankyId: result.ankyId,
                feedback: nil,
                meditation: nil,
                breathwork: nil,
                cuentacuentos: nil
            ),
            walletAddress: nil,
            statusUrl: nil,
            ankyResponse: result.reflection.isEmpty ? nil : result.reflection,
            nextPrompt: nil,
            mood: nil,
            error: nil
        )
    }

    func submitAnkyCaptureUntilStored(
        _ capture: LocalWritingCapture,
        kingdom: Kingdom
    ) async throws -> AnkySubmitStreamResult {
        var result = AnkySubmitStreamResult()

        for try await event in streamAnkySubmit(capture: capture, kingdom: kingdom) {
            switch event {
            case .accepted(let ankyId):
                result.ankyId = ankyId
            case .title(let title):
                result.title = title
            case .reflectionChunk(let chunk):
                result.reflection += chunk
            case .reflectionComplete(let reflection):
                result.reflection = reflection
            case .imageURL(let imageURL):
                result.imageURL = imageURL
            case .solana(let signature):
                result.solanaSignature = signature
            case .done(let ankyId):
                result.ankyId = result.ankyId ?? ankyId
                result.didReachDone = true
                return result
            case .error(let stage, let retryable):
                if (stage == "solana" || stage == "image"), result.ankyId != nil {
                    return result
                }
                throw AnkySubmitStreamFailure(stage: stage, retryable: retryable)
            }
        }

        if result.ankyId != nil {
            return result
        }

        throw AnkyError.transport("The submit stream ended before the session was stored.")
    }

    func streamAnkySubmit(
        capture: LocalWritingCapture,
        kingdom: Kingdom
    ) -> AsyncThrowingStream<AnkySubmitStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let submitRequest = try self.makeAnkySubmitRequest(capture: capture, kingdom: kingdom)
                    let url = try self.resolveURL(for: "/api/anky/submit", relativeTo: self.webBaseURL)

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(submitRequest.sessionHash, forHTTPHeaderField: "Idempotency-Key")
                    request.setValue(submitRequest.sessionHash, forHTTPHeaderField: "X-Anky-Session-Hash")

                    guard let token = self.sessionToken, !token.isEmpty else {
                        throw AnkyError.missingSession
                    }
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try self.encoder.encode(submitRequest)

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AnkyError.invalidResponse
                    }

                    if httpResponse.statusCode == 401 {
                        KeychainHelper.delete(AppState.sessionTokenKey)
                        throw AnkyError.unauthorized
                    }

                    if httpResponse.statusCode >= 400 {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                        }
                        let errorMessage = (try? self.decoder.decode(ErrorResponse.self, from: data))?.error
                            ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                        throw AnkyError.api(errorMessage)
                    }

                    var currentEvent: String?
                    var currentDataLines: [String] = []

                    func emitCurrentEvent() throws {
                        guard let currentEvent else { return }
                        let rawData = currentDataLines.joined(separator: "\n")
                        guard let event = try Self.parseAnkySubmitEvent(named: currentEvent, rawData: rawData) else {
                            return
                        }
                        continuation.yield(event)
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            break
                        }

                        if line.isEmpty {
                            try emitCurrentEvent()
                            currentEvent = nil
                            currentDataLines = []
                            continue
                        }

                        if line.hasPrefix("event:") {
                            currentEvent = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                            continue
                        }

                        if line.hasPrefix("data:") {
                            currentDataLines.append(
                                String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                            )
                        }
                    }

                    try emitCurrentEvent()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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

    func continueAnkyConversation(ankyId: String, text: String) async throws -> AnkyConversationResponse {
        try await post(
            "/api/anky/\(ankyId)/conversation",
            body: AnkyConversationRequest(text: text),
            baseURLOverride: webBaseURL
        )
    }

    /// Legacy `/swift/v2/writing/{sessionId}/status` compatibility path.
    /// Canonical runtime uses `/api/anky/sessions/{session_hash}` and `/proof`.
    func getWritingStatus(sessionId: String) async throws -> WritingStatusResponse {
        try await get("/writing/\(sessionId)/status")
    }

    func getCanonicalSessionSnapshot(sessionHash: String) async throws -> CanonicalProcessorStatusResponse {
        let encodedHash = sessionHash.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionHash
        return try await get("/api/anky/sessions/\(encodedHash)", baseURLOverride: webBaseURL)
    }

    func getCanonicalSessionProof(sessionHash: String) async throws -> CanonicalProofResponse {
        let encodedHash = sessionHash.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionHash
        return try await get("/api/anky/sessions/\(encodedHash)/proof", baseURLOverride: webBaseURL)
    }

    func getPrompt(id: String) async throws -> PromptResponse {
        try await get("/prompt/\(id)", requiresAuth: false)
    }

    func generateAnky(writing: String, aspectRatio: String = "1:1") async throws -> GenerateAnkyResponse {
        try await post(
            "/api/v1/generate",
            body: GenerateAnkyRequest(model: "flux", writing: writing, aspectRatio: aspectRatio),
            requiresAuth: false,
            baseURLOverride: webBaseURL
        )
    }

    func getGeneratedAnky(id: String) async throws -> GeneratedAnky {
        try await get("/api/v1/anky/\(id)", requiresAuth: false, baseURLOverride: webBaseURL)
    }

    func generatedAnkyGallery(origin: String = "generated") async throws -> [GeneratedAnky] {
        let encodedOrigin = origin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? origin
        let response: GeneratedAnkyListResponse = try await get(
            "/api/ankys?origin=\(encodedOrigin)",
            requiresAuth: false,
            baseURLOverride: webBaseURL
        )
        return response.ankys
    }

    func myGeneratedAnkys() async throws -> [GeneratedAnky] {
        try await get("/api/my-ankys", baseURLOverride: webBaseURL)
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

    // MARK: - Relay (.anky session protocol)

    /// Legacy proof/archive path. The locked core proof contract is
    /// `AnkyProofMetadata` on the session-bundle submit flow.
    func relaySession(_ request: RelayRequest) async throws -> RelayResponse {
        try await post("/api/v1/relay", body: request, requiresAuth: false, baseURLOverride: webBaseURL)
    }

    // MARK: - Sealed Sessions

    /// Legacy non-canonical proof path kept for older surfaces.
    func sealSession(_ sealed: SealedSession) async throws -> SealSessionResponse {
        try await post("/api/sessions/seal", body: sealed, baseURLOverride: webBaseURL)
    }

    // MARK: - Sealed Write (enclave endpoint, replaces plaintext for authenticated users)

    /// Fetch the enclave X25519 public key dynamically.
    func fetchEnclavePublicKey() async throws -> String {
        let response: EnclavePublicKeyResponse = try await get(
            "/api/anky/public-key",
            requiresAuth: false,
            baseURLOverride: webBaseURL
        )
        return response.encryptionPublicKey
    }

    /// Submit an encrypted writing session to the sealed-write endpoint.
    /// Uses a camelCase encoder since this endpoint expects camelCase JSON keys.
    /// This is a legacy/non-canonical submit path.
    func submitSealedWrite(_ request: SealedWriteRequest) async throws -> SealedWriteResponse {
        let camelEncoder = JSONEncoder()
        let bodyData = try camelEncoder.encode(request)

        let url = try resolveURL(for: "api/sealed-write", relativeTo: webBaseURL)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let token = sessionToken, !token.isEmpty else {
            throw AnkyError.missingSession
        }
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
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
            return try decoder.decode(SealedWriteResponse.self, from: data)
        } catch {
            throw AnkyError.transport("Unable to decode the server response.")
        }
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

    private func makeAnkySubmitRequest(
        capture: LocalWritingCapture,
        kingdom: Kingdom
    ) throws -> AnkySubmitRequest {
        let sessionBundle = capture.canonicalSessionBundle
        let sessionData: Data
        if let ankyFilePath = capture.ankyFilePath, !ankyFilePath.isEmpty {
            sessionData = try Data(contentsOf: URL(fileURLWithPath: ankyFilePath))
        } else if let session = capture.ankySessionString, !session.isEmpty {
            sessionData = Data(session.utf8)
        } else {
            throw AnkyError.transport("The writing session payload is missing.")
        }

        guard let session = String(data: sessionData, encoding: .utf8), !session.isEmpty else {
            throw AnkyError.transport("The writing session payload was not valid UTF-8.")
        }

        let sessionHash: String
        if let existingHash = sessionBundle.sessionHash, !existingHash.isEmpty {
            sessionHash = existingHash
        } else {
            sessionHash = AnkySessionFileStore.sha256Hex(of: sessionData)
        }

        let messageData = Data(hexString: sessionHash) ?? Data(sessionHash.utf8)
        let signature = try SeedIdentityManager.shared.sign(message: messageData)
        _ = try SeedIdentityManager.shared.solanaAddress()

        return AnkySubmitRequest(
            sessionHash: sessionHash,
            durationSeconds: max(Int(sessionBundle.durationSeconds.rounded()), 0),
            wordCount: sessionBundle.wordCount,
            kingdom: kingdom.sealingSlug,
            startedAt: Self.submitDateFormatter.string(from: sessionBundle.startedAt),
            walletSignature: Base58.encode(signature),
            session: session
        )
    }

    private nonisolated static func parseAnkySubmitEvent(
        named eventName: String,
        rawData: String
    ) throws -> AnkySubmitStreamEvent? {
        let normalizedName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }

        let data = Data(rawData.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            throw AnkyError.transport("The submit stream payload was malformed.")
        }

        switch normalizedName {
        case "accepted":
            guard let ankyId = payload["anky_id"] as? String else {
                throw AnkyError.transport("The accepted event was missing an anky_id.")
            }
            return .accepted(ankyId: ankyId)
        case "title":
            guard let title = payload["title"] as? String else {
                throw AnkyError.transport("The title event was missing a title.")
            }
            return .title(title)
        case "reflection_chunk":
            guard let text = payload["text"] as? String else {
                throw AnkyError.transport("The reflection chunk event was missing text.")
            }
            return .reflectionChunk(text)
        case "reflection_complete":
            guard let reflection = payload["reflection"] as? String else {
                throw AnkyError.transport("The reflection complete event was missing reflection text.")
            }
            return .reflectionComplete(reflection)
        case "image_url":
            guard let imageURL = payload["image_url"] as? String else {
                throw AnkyError.transport("The image event was missing an image_url.")
            }
            return .imageURL(imageURL)
        case "solana":
            guard let signature = payload["signature"] as? String else {
                throw AnkyError.transport("The solana event was missing a signature.")
            }
            return .solana(signature: signature)
        case "done":
            guard let ankyId = payload["anky_id"] as? String else {
                throw AnkyError.transport("The done event was missing an anky_id.")
            }
            return .done(ankyId: ankyId)
        case "error":
            guard let stage = payload["stage"] as? String else {
                throw AnkyError.transport("The error event was missing a stage.")
            }
            let retryable = payload["retryable"] as? Bool ?? false
            return .error(stage: stage, retryable: retryable)
        default:
            return nil
        }
    }

    // MARK: - Now Sessions

    func createNow(_ request: CreateNowRequest) async throws -> CreateNowResponse {
        try await post("/api/v1/now", body: request, baseURLOverride: webBaseURL)
    }

    func getNowRoom(slug: String) async throws -> NowRoom {
        try await get("/api/v1/now/\(slug)", requiresAuth: false, baseURLOverride: webBaseURL)
    }

    func joinNow(slug: String) async throws -> NowJoinResponse {
        try await post("/api/v1/now/\(slug)/join", body: EmptyRequest(), baseURLOverride: webBaseURL)
    }

    func startNow(slug: String) async throws -> NowStartResponse {
        try await post("/api/v1/now/\(slug)/start", body: EmptyRequest(), baseURLOverride: webBaseURL)
    }

    func heartbeatNow(slug: String) async throws -> NowHeartbeatResponse {
        try await post("/api/v1/now/\(slug)/heartbeat", body: EmptyRequest(), baseURLOverride: webBaseURL)
    }
}

struct EmptyRequest: Encodable {}

private extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count.isMultiple(of: 2) else { return nil }

        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard nextIndex <= hex.endIndex,
                  let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
