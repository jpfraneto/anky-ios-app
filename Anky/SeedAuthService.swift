//
//  SeedAuthService.swift
//  Anky
//

import Foundation

final class SeedAuthService {
    static let shared = SeedAuthService()

    private init() {}

    func authenticate(using identityManager: SeedIdentityManager) async throws -> UserProfile {
        let walletAddress = try identityManager.walletAddress()
        do {
            return try await performAuth(walletAddress: walletAddress, using: identityManager)
        } catch let error as AnkyError where shouldRetry(error) {
            return try await performAuth(walletAddress: walletAddress, using: identityManager)
        }
    }

    func logout() async {
        _ = try? await AnkyAPI.shared.logout()
        KeychainHelper.delete(AppState.sessionTokenKey)
    }

    private func performAuth(
        walletAddress: String,
        using identityManager: SeedIdentityManager
    ) async throws -> UserProfile {
        let challenge = try await AnkyAPI.shared.authChallenge(walletAddress: walletAddress)
        let signatureData = try identityManager.sign(message: Data(challenge.message.utf8))
        // Ed25519 signatures are sent as base58
        let signature = Base58.encode(signatureData)
        let verified = try await AnkyAPI.shared.verifyAuthChallenge(
            walletAddress: walletAddress,
            challengeID: challenge.challengeId,
            signature: signature
        )

        guard KeychainHelper.set(verified.sessionToken, for: AppState.sessionTokenKey) else {
            throw AnkyError.transport("The session token could not be stored securely.")
        }

        return try await AnkyAPI.shared.me()
    }

    private func shouldRetry(_ error: AnkyError) -> Bool {
        switch error {
        case .api(let message):
            let normalized = message.lowercased()
            return normalized.contains("challenge") || normalized.contains("expired") || normalized.contains("signature")
        case .unauthorized, .missingSession:
            return true
        default:
            return false
        }
    }
}
