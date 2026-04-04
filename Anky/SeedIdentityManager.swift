//
//  SeedIdentityManager.swift
//  Anky
//

import Foundation

struct SeedIdentitySnapshot: Equatable {
    let mnemonic: String
    let walletAddress: String
}

struct SeedIdentityStatus {
    let hasIdentity: Bool
    let hasCompletedBackup: Bool
    let pendingMnemonic: String?
}

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
            return "Enter all 12 words from your recovery phrase."
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

final class SeedIdentityManager {
    static let shared = SeedIdentityManager()

    private enum Keys {
        static let privateKey = "anky.seed.private-key"
        static let backupCompleted = "anky.seed.backup-completed"
        static let pendingMnemonic = "anky.seed.pending-mnemonic"
    }

    private init() {}

    func status() -> SeedIdentityStatus {
        SeedIdentityStatus(
            hasIdentity: KeychainHelper.getData(Keys.privateKey, synchronizable: true) != nil,
            hasCompletedBackup: KeychainHelper.get(Keys.backupCompleted, synchronizable: true) == "true",
            pendingMnemonic: KeychainHelper.get(Keys.pendingMnemonic, synchronizable: true)
        )
    }

    func generateIdentity() throws -> SeedIdentitySnapshot {
        let mnemonic = try SeedIdentityCrypto.generateMnemonic()
        return try persistIdentity(mnemonic: mnemonic, markAsBackedUp: false, keepPendingPhrase: true)
    }

    func importIdentity(from phrase: String) throws -> SeedIdentitySnapshot {
        let normalized = try SeedIdentityCrypto.normalizedMnemonic(from: phrase)
        return try persistIdentity(mnemonic: normalized, markAsBackedUp: true, keepPendingPhrase: false)
    }

    func markBackupCompleted() {
        _ = KeychainHelper.set("true", for: Keys.backupCompleted, synchronizable: true)
        KeychainHelper.delete(Keys.pendingMnemonic)
    }

    func walletAddress() throws -> String {
        let privateKey = try loadPrivateKey()
        return try SeedIdentityCrypto.walletAddress(fromPrivateKey: privateKey)
    }

    func solanaAddress() throws -> String {
        try walletAddress()
    }

    func sign(message: Data) throws -> Data {
        let privateKey = try loadPrivateKey()
        return try SeedIdentityCrypto.sign(message: message, privateKeyData: privateKey)
    }

    /// Returns the raw 32-byte Ed25519 public key.
    func publicKey() throws -> Data {
        let privateKey = try loadPrivateKey()
        return try SeedIdentityCrypto.publicKey(fromPrivateKey: privateKey)
    }

    func wipeIdentity() {
        KeychainHelper.delete(Keys.privateKey)
        KeychainHelper.delete(Keys.backupCompleted)
        KeychainHelper.delete(Keys.pendingMnemonic)
    }

    private func persistIdentity(
        mnemonic: String,
        markAsBackedUp: Bool,
        keepPendingPhrase: Bool
    ) throws -> SeedIdentitySnapshot {
        let privateKey = try SeedIdentityCrypto.derivedPrivateKey(from: mnemonic)
        guard KeychainHelper.set(privateKey, for: Keys.privateKey, synchronizable: true) else {
            throw SeedIdentityError.keychainFailure
        }

        guard KeychainHelper.set(markAsBackedUp ? "true" : "false", for: Keys.backupCompleted, synchronizable: true) else {
            throw SeedIdentityError.keychainFailure
        }

        if keepPendingPhrase {
            guard KeychainHelper.set(mnemonic, for: Keys.pendingMnemonic, synchronizable: true) else {
                throw SeedIdentityError.keychainFailure
            }
        } else {
            KeychainHelper.delete(Keys.pendingMnemonic)
        }

        return SeedIdentitySnapshot(
            mnemonic: mnemonic,
            walletAddress: try SeedIdentityCrypto.walletAddress(fromPrivateKey: privateKey)
        )
    }

    private func loadPrivateKey() throws -> Data {
        guard let data = KeychainHelper.getData(Keys.privateKey, synchronizable: true) else {
            throw SeedIdentityError.missingIdentity
        }
        return data
    }
}
