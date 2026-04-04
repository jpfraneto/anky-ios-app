import Foundation

enum SeedIdentityError: LocalizedError, Equatable {
    case missingIdentity
    case invalidWordCount
    case invalidWords
    case invalidChecksum
    case keychainFailure
    case entropyFailure
    case derivationFailure
    case signingFailure

    var errorDescription: String? {
        switch self {
        case .missingIdentity:
            return "Your local identity could not be found."
        case .invalidWordCount:
            return "Enter all 12 or 24 words from your recovery phrase."
        case .invalidWords, .invalidChecksum:
            return "That recovery phrase is not valid."
        case .keychainFailure:
            return "Anky could not save your identity securely."
        case .entropyFailure:
            return "Anky could not generate a secure recovery phrase."
        case .derivationFailure:
            return "Anky could not derive your local identity."
        case .signingFailure:
            return "Anky could not use the local identity key."
        }
    }
}

private struct ChallengeResponse: Decodable {
    let ok: Bool
    let challengeId: String
    let message: String
    let expiresAt: String
}

private struct VerifyResponse: Decodable {
    let ok: Bool
    let sessionToken: String
    let userId: String
    let walletAddress: String
}

private struct MeResponse: Decodable {
    let userId: String
    let walletAddress: String?
    let totalWritings: Int
    let totalAnkys: Int
}

private struct WriteResponse: Decodable {
    let ok: Bool
    let sessionId: String
    let isAnky: Bool
    let wordCount: Int
    let flowScore: Double?
    let persisted: Bool?
    let ankyId: String?
    let walletAddress: String?
}

private struct VerifyResult {
    let mnemonic: String
    let walletAddress: String
    let challenge: ChallengeResponse
    let verify: VerifyResponse
    let me: MeResponse
    let shortWrite: WriteResponse
    let shortAppearsInCloudHistory: Bool
    let realWrite: WriteResponse
    let realAppearsInCloudHistory: Bool
}

@main
struct LiveBackendVerifier {
    static func main() async {
        do {
            let result = try await run()
            print("")
            print("SUMMARY")
            print("wallet_address: \(result.walletAddress)")
            print("challenge_id: \(result.challenge.challengeId)")
            print("verify_user_id: \(result.verify.userId)")
            print("me.total_writings: \(result.me.totalWritings)")
            print("me.total_ankys: \(result.me.totalAnkys)")
            print("short.persisted: \(String(describing: result.shortWrite.persisted))")
            print("short.in_cloud_history: \(result.shortAppearsInCloudHistory)")
            print("real.persisted: \(String(describing: result.realWrite.persisted))")
            print("real.in_cloud_history: \(result.realAppearsInCloudHistory)")
            exit(0)
        } catch {
            fputs("VERIFICATION FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws -> VerifyResult {
        let baseURL = URL(string: ProcessInfo.processInfo.environment["ANKY_BASE_URL"] ?? "https://anky.app/swift/v2")!
        let session = URLSession(configuration: .ephemeral)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]

        let mnemonic: String
        if let configuredMnemonic = ProcessInfo.processInfo.environment["ANKY_TEST_MNEMONIC"] {
            mnemonic = configuredMnemonic
        } else {
            mnemonic = try SeedIdentityCrypto.generateMnemonic()
        }
        let normalizedMnemonic = try SeedIdentityCrypto.normalizedMnemonic(from: mnemonic)
        let privateKey = try SeedIdentityCrypto.derivedPrivateKey(from: normalizedMnemonic)
        let walletAddress = try SeedIdentityCrypto.walletAddress(fromPrivateKey: privateKey)

        let restoredPrivateKey = try SeedIdentityCrypto.derivedPrivateKey(from: normalizedMnemonic)
        let restoredWalletAddress = try SeedIdentityCrypto.walletAddress(fromPrivateKey: restoredPrivateKey)
        guard walletAddress == restoredWalletAddress else {
            throw Failure("restore mismatch: \(walletAddress) != \(restoredWalletAddress)")
        }

        let rebootMnemonic = try SeedIdentityCrypto.generateMnemonic()
        let rebootPrivateKey = try SeedIdentityCrypto.derivedPrivateKey(from: rebootMnemonic)
        let rebootWalletAddress = try SeedIdentityCrypto.walletAddress(fromPrivateKey: rebootPrivateKey)
        guard walletAddress != rebootWalletAddress else {
            throw Failure("reboot identity generated the same wallet address: \(walletAddress)")
        }

        print("LOCAL IDENTITY")
        print("mnemonic_word_count: \(normalizedMnemonic.split(separator: " ").count)")
        print("wallet_address: \(walletAddress)")
        print("restore_wallet_address: \(restoredWalletAddress)")
        print("reboot_wallet_address: \(rebootWalletAddress)")
        print("derivation_path: \(SeedIdentityCrypto.canonicalDerivationPath)")

        let challengeBody = ["wallet_address": walletAddress]
        let (challengeData, _) = try await request(
            session: session,
            encoder: encoder,
            method: "POST",
            url: baseURL.appending(path: "auth/challenge"),
            body: challengeBody,
            bearerToken: nil
        )
        let challenge = try decoder.decode(ChallengeResponse.self, from: challengeData)

        let signatureData = try SeedIdentityCrypto.sign(message: Data(challenge.message.utf8), privateKeyData: privateKey)
        let signature = Base58.encode(signatureData)

        let verifyBody = [
            "wallet_address": walletAddress,
            "challenge_id": challenge.challengeId,
            "signature": signature
        ]
        let (verifyData, _) = try await request(
            session: session,
            encoder: encoder,
            method: "POST",
            url: baseURL.appending(path: "auth/verify"),
            body: verifyBody,
            bearerToken: nil
        )
        let verify = try decoder.decode(VerifyResponse.self, from: verifyData)

        let (meData, _) = try await request(
            session: session,
            encoder: encoder,
            method: "GET",
            url: baseURL.appending(path: "me"),
            body: Optional<String>.none,
            bearerToken: verify.sessionToken
        )
        let me = try decoder.decode(MeResponse.self, from: meData)

        let shortMarker = "ios-live-short-\(UUID().uuidString.lowercased())"
        let shortSessionId = "ios-live-short-\(UUID().uuidString.lowercased())"
        let shortText = ([shortMarker, "probe"] + Array(repeating: "word", count: 180)).joined(separator: " ")
        let shortBody: [String: AnyEncodable] = [
            "text": AnyEncodable(shortText),
            "duration": AnyEncodable(120.0),
            "session_id": AnyEncodable(shortSessionId),
            "keystroke_deltas": AnyEncodable([110.0, 80.0, 420.0])
        ]
        let (shortData, _) = try await request(
            session: session,
            encoder: encoder,
            method: "POST",
            url: baseURL.appending(path: "write"),
            body: shortBody,
            bearerToken: verify.sessionToken
        )
        let shortWrite = try decoder.decode(WriteResponse.self, from: shortData)
        let shortAppearsInCloudHistory = try await pollWritingsForMarker(
            session: session,
            encoder: encoder,
            decoder: decoder,
            url: baseURL.appending(path: "writings"),
            bearerToken: verify.sessionToken,
            marker: shortMarker,
            expectedPresence: false
        )

        let realMarker = "ios-live-real-\(UUID().uuidString.lowercased())"
        let realSessionId = "ios-live-real-\(UUID().uuidString.lowercased())"
        let realText = ([realMarker, "probe"] + Array(repeating: "word", count: 320)).joined(separator: " ")
        let realBody: [String: AnyEncodable] = [
            "text": AnyEncodable(realText),
            "duration": AnyEncodable(481.0),
            "session_id": AnyEncodable(realSessionId),
            "keystroke_deltas": AnyEncodable([110.0, 80.0, 420.0, 95.0])
        ]
        let (realData, _) = try await request(
            session: session,
            encoder: encoder,
            method: "POST",
            url: baseURL.appending(path: "write"),
            body: realBody,
            bearerToken: verify.sessionToken
        )
        let realWrite = try decoder.decode(WriteResponse.self, from: realData)
        let realAppearsInCloudHistory = try await pollWritingsForMarker(
            session: session,
            encoder: encoder,
            decoder: decoder,
            url: baseURL.appending(path: "writings"),
            bearerToken: verify.sessionToken,
            marker: realMarker,
            expectedPresence: true
        )

        guard verify.walletAddress.lowercased() == walletAddress.lowercased() else {
            throw Failure("verify wallet mismatch: \(verify.walletAddress) != \(walletAddress)")
        }

        guard me.walletAddress?.lowercased() == walletAddress.lowercased() else {
            throw Failure("me wallet mismatch: \(String(describing: me.walletAddress)) != \(walletAddress)")
        }

        guard shortWrite.persisted == false else {
            throw Failure("short write expected persisted=false, got \(String(describing: shortWrite.persisted))")
        }

        guard !shortAppearsInCloudHistory else {
            throw Failure("short write appeared in cloud history")
        }

        guard realWrite.persisted == true, realWrite.isAnky else {
            throw Failure("real write expected persisted=true and is_anky=true, got persisted=\(String(describing: realWrite.persisted)) is_anky=\(realWrite.isAnky)")
        }

        guard realAppearsInCloudHistory else {
            throw Failure("real write did not appear in cloud history")
        }

        return VerifyResult(
            mnemonic: normalizedMnemonic,
            walletAddress: walletAddress,
            challenge: challenge,
            verify: verify,
            me: me,
            shortWrite: shortWrite,
            shortAppearsInCloudHistory: shortAppearsInCloudHistory,
            realWrite: realWrite,
            realAppearsInCloudHistory: realAppearsInCloudHistory
        )
    }

    private static func request<Body: Encodable>(
        session: URLSession,
        encoder: JSONEncoder,
        method: String,
        url: URL,
        body: Body?,
        bearerToken: String?
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        print("")
        print("REQUEST \(method) \(url.absoluteString)")
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            print(bodyString)
        } else {
            print("(no body)")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Failure("invalid response for \(url.absoluteString)")
        }

        print("RESPONSE \(httpResponse.statusCode) \(url.absoluteString)")
        print(String(data: data, encoding: .utf8) ?? "<non-utf8 body>")

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Failure("HTTP \(httpResponse.statusCode) from \(url.absoluteString)")
        }

        return (data, httpResponse)
    }

    private static func pollWritingsForMarker(
        session: URLSession,
        encoder: JSONEncoder,
        decoder: JSONDecoder,
        url: URL,
        bearerToken: String,
        marker: String,
        expectedPresence: Bool
    ) async throws -> Bool {
        for attempt in 1...6 {
            let (data, _) = try await request(
                session: session,
                encoder: encoder,
                method: "GET",
                url: url,
                body: Optional<String>.none,
                bearerToken: bearerToken
            )

            let appears = writingsContainMarker(data: data, marker: marker)
            print("writings_marker_check[\(attempt)]: marker=\(marker) present=\(appears)")
            if appears == expectedPresence {
                return appears
            }

            try await Task.sleep(nanoseconds: 2_000_000_000)
        }

        return !expectedPresence
    }

    private static func writingsContainMarker(data: Data, marker: String) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }

        guard let rows = json as? [[String: Any]] else {
            return false
        }

        return rows.contains { row in
            for key in ["content", "text", "id", "session_id", "anky_id", "title", "anky_title"] {
                if let value = row[key] as? String, value.localizedCaseInsensitiveContains(marker) {
                    return true
                }
            }
            return false
        }
    }
}

private struct Failure: LocalizedError {
    let errorDescription: String?

    init(_ errorDescription: String) {
        self.errorDescription = errorDescription
    }
}

private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeImpl = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}
