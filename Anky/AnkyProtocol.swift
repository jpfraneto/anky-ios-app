//
//  AnkyProtocol.swift
//  Anky
//
//  End-to-end encryption for writing sessions.
//  User's X25519 keypair is generated on first launch and stored in the iOS Keychain.
//  Sessions are encrypted with a random AES-256-GCM key, which is then encrypted
//  to both the user (for re-reading) and Anky's enclave (for processing) via ECIES.
//

import CryptoKit
import Foundation
import Security

// MARK: - Types

struct SessionMetadata: Codable {
    let sessionId: String
    let timestamp: Date
    let durationSeconds: Double
    let kingdom: Int
    let wordCount: Int
    let keystrokeCount: Int
    let walletAddress: String
}

struct SealedSession: Codable {
    let sessionId: String
    let ciphertext: String        // base64: AES-GCM encrypted content
    let nonce: String             // base64: 12-byte AES-GCM nonce
    let tag: String               // base64: 16-byte AES-GCM tag
    let userEncryptedKey: String  // base64: [32B ephemeral pubkey][12B nonce][ciphertext+16B tag]
    let ankyEncryptedKey: String  // base64: [32B ephemeral pubkey][12B nonce][ciphertext+16B tag]
    let sessionHash: String       // hex: SHA-256 of ciphertext (not plaintext — no content fingerprint leaks)
    let metadata: SessionMetadata
}

struct SealSessionResponse: Codable {
    let ok: Bool
    let sessionId: String?
    let error: String?
}

// MARK: - Errors

enum AnkyProtocolError: LocalizedError {
    case keypairGenerationFailed
    case keychainStoreFailed
    case keychainLoadFailed
    case invalidPublicKey
    case encryptionFailed
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .keypairGenerationFailed: return "Could not generate encryption keypair."
        case .keychainStoreFailed:     return "Could not store encryption key securely."
        case .keychainLoadFailed:      return "Could not load encryption key."
        case .invalidPublicKey:        return "Invalid public key format."
        case .encryptionFailed:        return "Session encryption failed."
        case .decryptionFailed:        return "Session decryption failed."
        }
    }
}

// MARK: - AnkyProtocol

enum AnkyProtocol {

    // Keychain keys
    private static let encryptionPrivateKeyKey = "anky.encryption.x25519-private"
    private static let migrationDoneKey = "anky.encryption.icloud-migrated"

    // Anky's enclave public key (X25519, base64)
    // Fetched dynamically from GET /api/anky/public-key; hardcoded value is fallback only
    private static let hardcodedAnkyPublicKeyBase64 = "NPx+MwUCYs1WlZ4RcJwsEoMsVY0kHdcQnUGKmsBU1jg="

    // Dynamically fetched enclave public key (takes precedence over hardcoded)
    private static var cachedEnclavePublicKeyBase64: String?

    // HKDF shared info for ECIES key wrapping
    private static let eciesSharedInfo = "anky-session-key-encryption"

    // MARK: - Keypair Management

    /// Ensures a user X25519 keypair exists. Creates one on first call.
    /// The key is stored in iCloud Keychain so it survives device loss and syncs across devices.
    @discardableResult
    static func ensureKeypair() throws -> Curve25519.KeyAgreement.PublicKey {
        // Migrate any existing device-only key to iCloud Keychain
        migrateToICloudKeychainIfNeeded()

        if let existingKey = loadPrivateKey() {
            return existingKey.publicKey
        }
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        guard KeychainHelper.set(
            Data(privateKey.rawRepresentation),
            for: encryptionPrivateKeyKey,
            synchronizable: true
        ) else {
            throw AnkyProtocolError.keychainStoreFailed
        }
        return privateKey.publicKey
    }

    /// One-time migration: promotes a device-only key to iCloud Keychain.
    private static func migrateToICloudKeychainIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationDoneKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migrationDoneKey) }

        // Check for existing device-only key
        guard let localData = KeychainHelper.getData(encryptionPrivateKeyKey, synchronizable: false) else {
            return // No local key — fresh install, nothing to migrate
        }

        // Write to iCloud Keychain
        guard KeychainHelper.set(localData, for: encryptionPrivateKeyKey, synchronizable: true) else {
            print("[AnkyProtocol] iCloud Keychain migration failed — keeping device-only key")
            return
        }

        // Remove the old device-only entry
        // (delete uses kSecAttrSynchronizableAny so we need a targeted delete)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.jpfraneto.Anky",
            kSecAttrAccount as String: encryptionPrivateKeyKey,
            kSecAttrSynchronizable as String: false
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        print("[AnkyProtocol] Migrated encryption key to iCloud Keychain")
    }

    /// Returns the user's X25519 public key (base64).
    static func userPublicKeyBase64() throws -> String {
        let publicKey = try ensureKeypair()
        return Data(publicKey.rawRepresentation).base64EncodedString()
    }

    // MARK: - Seal

    /// Encrypts a writing session for both the user and Anky's enclave.
    static func sealSession(content: String, metadata: SessionMetadata) throws -> SealedSession {
        let plaintext = Data(content.utf8)

        // 1. Generate random AES-256-GCM session key
        let sessionKey = SymmetricKey(size: .bits256)

        // 2. Encrypt content with session key
        let contentNonce = AES.GCM.Nonce()
        let sealedContent = try AES.GCM.seal(plaintext, using: sessionKey, nonce: contentNonce)

        // 3. Encrypt session key to USER's public key
        let userPrivateKey = try requirePrivateKey()
        let userEncryptedKey = try eciesEncrypt(
            sessionKey: sessionKey,
            recipientPublicKey: userPrivateKey.publicKey
        )

        // 4. Encrypt session key to ANKY's public key
        let ankyPublicKey = try loadAnkyPublicKey()
        let ankyEncryptedKey = try eciesEncrypt(
            sessionKey: sessionKey,
            recipientPublicKey: ankyPublicKey
        )

        // 5. SHA-256 hash of ciphertext (not plaintext — avoids leaking content fingerprint)
        let hash = SHA256.hash(data: sealedContent.ciphertext)
        let hashHex = hash.compactMap { String(format: "%02x", $0) }.joined()

        return SealedSession(
            sessionId: metadata.sessionId,
            ciphertext: sealedContent.ciphertext.base64EncodedString(),
            nonce: Data(contentNonce).base64EncodedString(),
            tag: Data(sealedContent.tag).base64EncodedString(),
            userEncryptedKey: userEncryptedKey.base64EncodedString(),
            ankyEncryptedKey: ankyEncryptedKey.base64EncodedString(),
            sessionHash: hashHex,
            metadata: metadata
        )
    }

    // MARK: - Decrypt (user's own sessions)

    /// Decrypts a sealed session using the user's private key.
    static func decryptOwnSession(sealed: SealedSession) throws -> String {
        let userPrivateKey = try requirePrivateKey()

        // 1. Decrypt the session key from userEncryptedKey
        guard let encryptedKeyData = Data(base64Encoded: sealed.userEncryptedKey) else {
            throw AnkyProtocolError.decryptionFailed
        }
        let sessionKey = try eciesDecrypt(
            encryptedKeyPackage: encryptedKeyData,
            recipientPrivateKey: userPrivateKey
        )

        // 2. Decrypt the content
        guard let ciphertextData = Data(base64Encoded: sealed.ciphertext),
              let nonceData = Data(base64Encoded: sealed.nonce),
              let tagData = Data(base64Encoded: sealed.tag) else {
            throw AnkyProtocolError.decryptionFailed
        }

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
        let plaintext = try AES.GCM.open(sealedBox, using: sessionKey)

        guard let text = String(data: plaintext, encoding: .utf8) else {
            throw AnkyProtocolError.decryptionFailed
        }

        return text
    }

    /// Decrypts a sealed session using an explicit private key (for testing wrong-key rejection).
    static func decryptSession(
        sealed: SealedSession,
        with privateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> String {
        guard let encryptedKeyData = Data(base64Encoded: sealed.userEncryptedKey) else {
            throw AnkyProtocolError.decryptionFailed
        }
        let sessionKey = try eciesDecrypt(
            encryptedKeyPackage: encryptedKeyData,
            recipientPrivateKey: privateKey
        )

        guard let ciphertextData = Data(base64Encoded: sealed.ciphertext),
              let nonceData = Data(base64Encoded: sealed.nonce),
              let tagData = Data(base64Encoded: sealed.tag) else {
            throw AnkyProtocolError.decryptionFailed
        }

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
        let plaintext = try AES.GCM.open(sealedBox, using: sessionKey)

        guard let text = String(data: plaintext, encoding: .utf8) else {
            throw AnkyProtocolError.decryptionFailed
        }
        return text
    }

    // MARK: - ECIES (Ephemeral X25519 + HKDF-SHA256 + AES-GCM)

    /// Encrypts a session key to a recipient's X25519 public key.
    /// Returns: [32B ephemeral pubkey][12B nonce][ciphertext + 16B tag]
    private static func eciesEncrypt(
        sessionKey: SymmetricKey,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> Data {
        // Generate ephemeral keypair
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublicKeyData = Data(ephemeral.publicKey.rawRepresentation)

        // ECDH shared secret
        let sharedSecret = try ephemeral.sharedSecretFromKeyAgreement(with: recipientPublicKey)

        // Derive wrapping key via HKDF
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(eciesSharedInfo.utf8),
            outputByteCount: 32
        )

        // Encrypt session key bytes with wrapping key
        let sessionKeyData = sessionKey.withUnsafeBytes { Data($0) }
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(sessionKeyData, using: wrappingKey, nonce: nonce)

        // Pack: [ephemeral pubkey 32B][nonce 12B][ciphertext + tag]
        var package = Data()
        package.append(ephemeralPublicKeyData)           // 32 bytes
        package.append(Data(nonce))                       // 12 bytes
        package.append(sealed.ciphertext)                 // 32 bytes (session key)
        package.append(Data(sealed.tag))                  // 16 bytes
        return package
    }

    /// Decrypts a session key from an ECIES package using the recipient's private key.
    private static func eciesDecrypt(
        encryptedKeyPackage: Data,
        recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> SymmetricKey {
        // Unpack: [ephemeral pubkey 32B][nonce 12B][ciphertext 32B][tag 16B]
        guard encryptedKeyPackage.count >= 32 + 12 + 32 + 16 else {
            throw AnkyProtocolError.decryptionFailed
        }

        let ephemeralPubKeyData = encryptedKeyPackage.prefix(32)
        let nonceData = encryptedKeyPackage[32..<44]
        let ciphertextData = encryptedKeyPackage[44..<(encryptedKeyPackage.count - 16)]
        let tagData = encryptedKeyPackage.suffix(16)

        let ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralPubKeyData)

        // ECDH
        let sharedSecret = try recipientPrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)

        // Derive wrapping key
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(eciesSharedInfo.utf8),
            outputByteCount: 32
        )

        // Decrypt
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
        let sessionKeyData = try AES.GCM.open(sealedBox, using: wrappingKey)

        return SymmetricKey(data: sessionKeyData)
    }

    // MARK: - Key Loading

    private static func loadPrivateKey() -> Curve25519.KeyAgreement.PrivateKey? {
        guard let data = KeychainHelper.getData(encryptionPrivateKeyKey, synchronizable: true) else {
            return nil
        }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    private static func requirePrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        guard let key = loadPrivateKey() else {
            // Try to create one if missing
            _ = try ensureKeypair()
            guard let key = loadPrivateKey() else {
                throw AnkyProtocolError.keychainLoadFailed
            }
            return key
        }
        return key
    }

    private static func loadAnkyPublicKey() throws -> Curve25519.KeyAgreement.PublicKey {
        guard let data = Data(base64Encoded: hardcodedAnkyPublicKeyBase64), data.count == 32 else {
            throw AnkyProtocolError.invalidPublicKey
        }
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
    }

    // MARK: - Relay Encryption (ECIES: ephemeral X25519 + AES-256-GCM)

    /// Encrypts a session string for the relay endpoint.
    /// Scheme: ephemeral X25519 → HKDF-SHA256(sharedSecret, salt="", info="anky-relay") → AES-256-GCM.
    /// Returns all components needed for the relay payload.
    static func relayEncrypt(plaintext: String) throws -> (ephemeralPublicKey: Data, nonce: Data, tag: Data, ciphertext: Data) {
        let enclavePublicKey = try loadAnkyPublicKey()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()

        let sharedSecret = try ephemeral.sharedSecretFromKeyAgreement(with: enclavePublicKey)

        let aesKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("anky-relay".utf8),
            outputByteCount: 32
        )

        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: aesKey, nonce: nonce)

        return (
            ephemeralPublicKey: Data(ephemeral.publicKey.rawRepresentation),
            nonce: Data(nonce),
            tag: Data(sealed.tag),
            ciphertext: sealed.ciphertext
        )
    }

    // MARK: - Sealed Write Encryption

    /// Sets the dynamically fetched enclave public key. Call after fetching from /api/anky/public-key.
    static func setEnclavePublicKey(_ base64Key: String) {
        cachedEnclavePublicKeyBase64 = base64Key
    }

    /// Encrypts a writing session for the new POST /api/sealed-write endpoint.
    /// Scheme: ephemeral X25519 → ECDH → SHA256(shared_secret) → AES-256-GCM.
    /// sessionHash = hex(SHA256(plaintext_writing)).
    /// The ephemeral private key is discarded after use.
    static func sealForWrite(
        content: String,
        sessionId: String,
        duration: Double,
        wordCount: Int
    ) throws -> SealedWriteRequest {
        let plaintext = Data(content.utf8)

        // 1. Load enclave public key (prefer dynamically fetched, fall back to hardcoded)
        let enclavePublicKey = try loadEnclavePublicKeyForSealedWrite()

        // 2. Generate ephemeral X25519 keypair
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()

        // 3. ECDH: shared_secret = ephemeral_private × enclave_public
        let sharedSecret = try ephemeral.sharedSecretFromKeyAgreement(with: enclavePublicKey)

        // 4. Derive AES key: aes_key = SHA256(shared_secret)
        let sharedSecretData = sharedSecret.withUnsafeBytes { Data($0) }
        let aesKeyHash = SHA256.hash(data: sharedSecretData)
        let aesKey = SymmetricKey(data: Data(aesKeyHash))

        // 5. Generate random 12-byte nonce
        let nonce = AES.GCM.Nonce()

        // 6. Encrypt: AES-256-GCM(aes_key, nonce, plaintext) → (ciphertext, tag)
        let sealed = try AES.GCM.seal(plaintext, using: aesKey, nonce: nonce)

        // 7. sessionHash = hex(SHA256(plaintext_writing))
        let plaintextHash = SHA256.hash(data: plaintext)
        let sessionHash = plaintextHash.compactMap { String(format: "%02x", $0) }.joined()

        // 8. User's public key for optional re-read capability
        let userPubKeyBase64 = try? userPublicKeyBase64()

        // Ephemeral private key goes out of scope and is discarded here
        return SealedWriteRequest(
            sessionId: sessionId,
            ciphertext: sealed.ciphertext.base64EncodedString(),
            nonce: Data(nonce).base64EncodedString(),
            tag: Data(sealed.tag).base64EncodedString(),
            ephemeralPublicKey: Data(ephemeral.publicKey.rawRepresentation).base64EncodedString(),
            sessionHash: sessionHash,
            duration: duration,
            wordCount: wordCount,
            userEncryptedKey: userPubKeyBase64
        )
    }

    /// Loads the enclave public key for sealed-write encryption.
    /// Prefers dynamically fetched key; falls back to hardcoded.
    private static func loadEnclavePublicKeyForSealedWrite() throws -> Curve25519.KeyAgreement.PublicKey {
        let base64 = cachedEnclavePublicKeyBase64 ?? hardcodedAnkyPublicKeyBase64
        guard let data = Data(base64Encoded: base64), data.count == 32 else {
            throw AnkyProtocolError.invalidPublicKey
        }
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
    }

    // MARK: - Wipe

    static func wipeKeypair() {
        KeychainHelper.delete(encryptionPrivateKeyKey)
    }
}

// MARK: - Sealed Session Local Store

enum SealedSessionStore {
    private static let cacheKey = "anky.sealed.sessions"
    private static let pendingKey = "anky.sealed.pending"
    private static let encoder = JSONEncoder()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func save(_ session: SealedSession) {
        var sessions = loadAll()
        sessions.removeAll { $0.sessionId == session.sessionId }
        sessions.insert(session, at: 0)
        if sessions.count > 100 { sessions = Array(sessions.prefix(100)) }
        guard let data = try? encoder.encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    static func loadAll() -> [SealedSession] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return [] }
        return (try? decoder.decode([SealedSession].self, from: data)) ?? []
    }

    static func find(sessionId: String) -> SealedSession? {
        loadAll().first { $0.sessionId == sessionId }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    // MARK: - Pending Retry Queue

    /// Mark a sealed session as needing retry (server didn't receive it).
    static func markPending(_ sessionId: String) {
        var pending = loadPendingIds()
        if !pending.contains(sessionId) {
            pending.append(sessionId)
            savePendingIds(pending)
        }
    }

    /// Remove a session from the pending queue (server confirmed receipt).
    static func clearPending(_ sessionId: String) {
        var pending = loadPendingIds()
        pending.removeAll { $0 == sessionId }
        savePendingIds(pending)
    }

    /// Returns all sealed sessions that still need to be sent to the server.
    static func pendingSessions() -> [SealedSession] {
        let ids = Set(loadPendingIds())
        guard !ids.isEmpty else { return [] }
        return loadAll().filter { ids.contains($0.sessionId) }
    }

    /// Retry sending all pending sealed sessions. Returns count of successfully sent.
    static func retryPending(using api: AnkyAPI) async -> Int {
        let pending = pendingSessions()
        guard !pending.isEmpty else { return 0 }
        var sent = 0
        for session in pending {
            do {
                _ = try await api.sealSession(session)
                clearPending(session.sessionId)
                sent += 1
            } catch {
                // Keep in queue for next retry
            }
        }
        return sent
    }

    private static func loadPendingIds() -> [String] {
        UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
    }

    private static func savePendingIds(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: pendingKey)
    }
}

// MARK: - Nonce Data Init

private extension Data {
    init(_ nonce: AES.GCM.Nonce) {
        self = nonce.withUnsafeBytes { Data($0) }
    }
}
