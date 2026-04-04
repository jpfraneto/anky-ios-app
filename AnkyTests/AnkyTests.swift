//
//  AnkyTests.swift
//  AnkyTests
//
//  Created by kithkui on 07-03-26.
//

import CryptoKit
import Foundation
import Testing
@testable import Anky

struct AnkyTests {
    // SLIP-0010 test vector: "abandon" x11 + "about" (standard BIP39 12-word test mnemonic)
    private let testMnemonic12 = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

    @Test("API routes stay under /swift/v2")
    func apiRouteResolutionUsesTheV2BasePath() throws {
        let api = AnkyAPI(baseURL: URL(string: "https://anky.app/swift/v2")!)

        #expect(try api.resolveURL(for: "/auth/challenge").absoluteString == "https://anky.app/swift/v2/auth/challenge")
        #expect(try api.resolveURL(for: "auth/verify").absoluteString == "https://anky.app/swift/v2/auth/verify")
        #expect(try api.resolveURL(for: "/write").absoluteString == "https://anky.app/swift/v2/write")
        #expect(try api.resolveURL(for: "https://example.com/health").absoluteString == "https://example.com/health")
    }

    @Test("Anky image paths normalize for history rendering")
    func writingHistoryImagePathsNormalizeCleanly() {
        let relativePathEntry = CachedWritingEntry(
            id: "relative",
            prompt: "",
            content: "content",
            durationSeconds: 480,
            wordCount: 320,
            isAnky: true,
            response: nil,
            ankyId: "anky-1",
            ankyTitle: "An anky",
            ankyImagePath: "images/anky.png",
            createdAt: .now,
            flowScore: 0.9,
            syncState: .synced
        )
        let absolutePathEntry = CachedWritingEntry(
            id: "absolute",
            prompt: "",
            content: "content",
            durationSeconds: 480,
            wordCount: 320,
            isAnky: true,
            response: nil,
            ankyId: "anky-2",
            ankyTitle: "An anky",
            ankyImagePath: "https://cdn.anky.app/anky.png",
            createdAt: .now,
            flowScore: 0.9,
            syncState: .synced
        )

        #expect(relativePathEntry.remoteImageURL?.absoluteString == "https://anky.app/images/anky.png")
        #expect(absolutePathEntry.remoteImageURL?.absoluteString == "https://cdn.anky.app/anky.png")
    }

    @Test("Real ankys require both eight minutes and three hundred words")
    func ankyQualificationUsesDurationAndWordCount() {
        let enoughWords = Array(repeating: "word", count: 300).joined(separator: " ")
        let notEnoughWords = Array(repeating: "word", count: 299).joined(separator: " ")

        #expect(LocalWritingCapture.qualifiesForAnky(text: enoughWords, duration: 480))
        #expect(!LocalWritingCapture.qualifiesForAnky(text: notEnoughWords, duration: 480))
        #expect(!LocalWritingCapture.qualifiesForAnky(text: enoughWords, duration: 479))
    }

    @Test("Legacy short pending writes stay local-only after migration")
    func shortPendingWritesMigrateToLocalOnly() {
        defer { WritingCacheStore.save([]) }

        let shortPending = CachedWritingEntry(
            id: "short-pending",
            prompt: "",
            content: "too short to sync",
            durationSeconds: 90,
            wordCount: 4,
            isAnky: true,
            response: nil,
            ankyId: nil,
            ankyTitle: nil,
            ankyImagePath: nil,
            createdAt: .now,
            flowScore: 0.1,
            syncState: .pending
        )
        let realPending = CachedWritingEntry(
            id: "real-pending",
            prompt: "",
            content: Array(repeating: "word", count: 300).joined(separator: " "),
            durationSeconds: 480,
            wordCount: 300,
            isAnky: true,
            response: nil,
            ankyId: nil,
            ankyTitle: nil,
            ankyImagePath: nil,
            createdAt: .now,
            flowScore: 0.9,
            syncState: .pending
        )

        WritingCacheStore.save([shortPending, realPending])
        let migrated = WritingCacheStore.migrateLegacyShortPendingWrites()

        #expect(migrated.first(where: { $0.id == "short-pending" })?.syncState == .localOnly)
        #expect(migrated.first(where: { $0.id == "short-pending" })?.isAnky == false)
        #expect(migrated.first(where: { $0.id == "real-pending" })?.syncState == .pending)
    }

    @Test("Writing copy resolves supported languages and falls back to English")
    func writingCopyLocalizationResolvesCleanly() {
        let spanish = WritingExperienceStrings(languageCode: "es")
        let fallback = WritingExperienceStrings(languageCode: "xx")

        #expect(spanish[.continueAction] == "Continuar")
        #expect(fallback[.writeNow] == "Write now")
    }

    @Test("App copy resolves the welcome flow copy and tab labels")
    func appCopyLocalizationResolvesCleanly() {
        let spanish = AppCopy(languageCode: "es")
        let fallback = AppCopy(languageCode: "xx")

        #expect(spanish[.youTab] == "Tu")
        #expect(fallback[.welcomeContinueAction] == "Continue")
        #expect(fallback[.unlockAction] == "Unlock")
    }

    @Test("Canonical Solana derivation path stays frozen")
    func canonicalDerivationPathStaysFrozen() {
        #expect(SeedIdentityCrypto.canonicalDerivationPath == "m/44'/501'/0'/0'")
    }

    @Test("Seed phrases reject an invalid checksum")
    func seedPhraseValidationRejectsBadChecksum() {
        let invalidMnemonic = testMnemonic12.replacingOccurrences(of: " about", with: " abandon")

        do {
            _ = try SeedIdentityCrypto.normalizedMnemonic(from: invalidMnemonic)
            Issue.record("Expected an invalid checksum to be rejected.")
        } catch let error as SeedIdentityError {
            #expect(error == .invalidChecksum)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("SLIP-0010 Solana derivation produces a valid Ed25519 keypair and base58 address")
    func solanaSeedDerivationProducesValidKeypair() throws {
        let privateKeyData = try SeedIdentityCrypto.derivedPrivateKey(from: testMnemonic12)
        let publicKeyData = try SeedIdentityCrypto.publicKey(fromPrivateKey: privateKeyData)
        let walletAddress = try SeedIdentityCrypto.walletAddress(fromPrivateKey: privateKeyData)

        // Private key is 32 bytes
        #expect(privateKeyData.count == 32)

        // Public key is 32 bytes (Ed25519)
        #expect(publicKeyData.count == 32)

        // Wallet address is base58-encoded and has reasonable length (32-44 chars)
        #expect(walletAddress.count >= 32)
        #expect(walletAddress.count <= 44)

        // Should not start with 0x (not Ethereum)
        #expect(!walletAddress.hasPrefix("0x"))

        // Base58 round-trip: decode the address and re-encode
        let decoded = Base58.decode(walletAddress)
        #expect(decoded != nil)
        #expect(decoded?.count == 32)
        #expect(Base58.encode(decoded!) == walletAddress)
    }

    @Test("Ed25519 signature is valid and verifiable")
    func ed25519SignatureVerifies() throws {
        let privateKeyData = try SeedIdentityCrypto.derivedPrivateKey(from: testMnemonic12)
        let publicKeyData = try SeedIdentityCrypto.publicKey(fromPrivateKey: privateKeyData)
        let message = Data("anky.app sign-in challenge".utf8)

        let signature = try SeedIdentityCrypto.sign(message: message, privateKeyData: privateKeyData)

        // Ed25519 signature is 64 bytes
        #expect(signature.count == 64)

        // Signature should verify
        let valid = try SeedIdentityCrypto.verify(message: message, signature: signature, publicKeyData: publicKeyData)
        #expect(valid)

        // Tampered message should not verify
        let tampered = Data("tampered message".utf8)
        let invalidVerify = try SeedIdentityCrypto.verify(message: tampered, signature: signature, publicKeyData: publicKeyData)
        #expect(!invalidVerify)
    }

    @Test("Mnemonic round-trip: generate, normalize, derive, and address all work")
    func mnemonicRoundTrip() throws {
        let mnemonic = try SeedIdentityCrypto.generateMnemonic()
        let words = mnemonic.split(separator: " ")
        #expect(words.count == 12)

        // Should normalize without error
        let normalized = try SeedIdentityCrypto.normalizedMnemonic(from: mnemonic)
        #expect(normalized == mnemonic)

        // Should derive a key and address
        let privateKey = try SeedIdentityCrypto.derivedPrivateKey(from: mnemonic)
        #expect(privateKey.count == 32)

        let address = try SeedIdentityCrypto.walletAddress(fromPrivateKey: privateKey)
        #expect(address.count >= 32)

        // Same mnemonic should produce same key
        let privateKey2 = try SeedIdentityCrypto.derivedPrivateKey(from: mnemonic)
        #expect(privateKey == privateKey2)
    }

    @Test("Base58 encoding and decoding are consistent")
    func base58RoundTrip() {
        let testData = Data([1, 2, 3, 4, 5, 100, 200, 255, 0, 0, 42])
        let encoded = Base58.encode(testData)
        let decoded = Base58.decode(encoded)
        #expect(decoded == testData)

        // Leading zeros preserved
        let withLeadingZeros = Data([0, 0, 0, 1, 2, 3])
        let encoded2 = Base58.encode(withLeadingZeros)
        #expect(encoded2.hasPrefix("111")) // Three leading '1's for three zero bytes
        let decoded2 = Base58.decode(encoded2)
        #expect(decoded2 == withLeadingZeros)
    }

    @Test("Kingdom derivation works with Solana base58 addresses")
    func kingdomDerivationFromBase58() throws {
        let privateKey = try SeedIdentityCrypto.derivedPrivateKey(from: testMnemonic12)
        let address = try SeedIdentityCrypto.walletAddress(fromPrivateKey: privateKey)
        let kingdom = Kingdom.from(walletAddress: address)

        // Should produce a valid kingdom (0-7)
        #expect(kingdom.rawValue >= 0 && kingdom.rawValue <= 7)

        // Should be deterministic
        let kingdom2 = Kingdom.from(walletAddress: address)
        #expect(kingdom == kingdom2)
    }

    @Test("AnkyProtocol seals and decrypts a session round-trip")
    func sealAndDecryptRoundTrip() throws {
        // Ensure keypair exists for test
        try AnkyProtocol.ensureKeypair()

        let content = "this is a writing session about consciousness and the nature of reality"
        let metadata = SessionMetadata(
            sessionId: "test-session-1",
            timestamp: Date(),
            durationSeconds: 500,
            kingdom: 3,
            wordCount: 12,
            keystrokeCount: 300,
            walletAddress: "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
        )

        let sealed = try AnkyProtocol.sealSession(content: content, metadata: metadata)

        // Verify sealed session fields are populated
        #expect(!sealed.ciphertext.isEmpty)
        #expect(!sealed.nonce.isEmpty)
        #expect(!sealed.tag.isEmpty)
        #expect(!sealed.userEncryptedKey.isEmpty)
        #expect(!sealed.ankyEncryptedKey.isEmpty)
        #expect(sealed.sessionHash.count == 64) // SHA-256 hex = 64 chars
        #expect(sealed.sessionId == "test-session-1")

        // Decrypt with user's own key
        let decrypted = try AnkyProtocol.decryptOwnSession(sealed: sealed)
        #expect(decrypted == content)
    }

    @Test("AnkyProtocol session hash is SHA-256 of ciphertext, not plaintext")
    func sessionHashMatchesCiphertextSHA256() throws {
        try AnkyProtocol.ensureKeypair()
        let content = "test content for hashing"
        let metadata = SessionMetadata(
            sessionId: "hash-test",
            timestamp: Date(),
            durationSeconds: 60,
            kingdom: 0,
            wordCount: 4,
            keystrokeCount: 24,
            walletAddress: ""
        )

        let sealed = try AnkyProtocol.sealSession(content: content, metadata: metadata)

        // The hash should match SHA256 of the ciphertext, not the plaintext
        let ciphertextData = Data(base64Encoded: sealed.ciphertext)!
        let expectedCiphertextHash = CryptoKit.SHA256.hash(data: ciphertextData)
            .compactMap { String(format: "%02x", $0) }.joined()
        #expect(sealed.sessionHash == expectedCiphertextHash)

        // And it should NOT match the plaintext hash (different because session key is random)
        let plaintextHash = CryptoKit.SHA256.hash(data: Data(content.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
        #expect(sealed.sessionHash != plaintextHash)
    }

    @Test("AnkyProtocol encrypted key packages have correct format")
    func encryptedKeyPackageFormat() throws {
        try AnkyProtocol.ensureKeypair()
        let metadata = SessionMetadata(
            sessionId: "format-test",
            timestamp: Date(),
            durationSeconds: 60,
            kingdom: 0,
            wordCount: 1,
            keystrokeCount: 5,
            walletAddress: ""
        )

        let sealed = try AnkyProtocol.sealSession(content: "hello", metadata: metadata)

        // [32B ephemeral pubkey][12B nonce][32B encrypted key + 16B tag] = 92 bytes
        let userKeyData = Data(base64Encoded: sealed.userEncryptedKey)
        let ankyKeyData = Data(base64Encoded: sealed.ankyEncryptedKey)

        #expect(userKeyData != nil)
        #expect(ankyKeyData != nil)
        #expect(userKeyData?.count == 92)
        #expect(ankyKeyData?.count == 92)
    }

    @Test("AnkyProtocol decryption with wrong key fails")
    func decryptWithWrongKeyFails() throws {
        try AnkyProtocol.ensureKeypair()

        let content = "this is a private writing session that should not be readable by anyone else"
        let metadata = SessionMetadata(
            sessionId: "wrong-key-test",
            timestamp: Date(),
            durationSeconds: 480,
            kingdom: 2,
            wordCount: 14,
            keystrokeCount: 1200,
            walletAddress: ""
        )

        // Seal with the real key
        let sealed = try AnkyProtocol.sealSession(content: content, metadata: metadata)

        // Generate a completely different keypair
        let wrongKey = Curve25519.KeyAgreement.PrivateKey()

        // Attempt to decrypt with the wrong key — this MUST fail
        #expect(throws: (any Error).self) {
            _ = try AnkyProtocol.decryptSession(sealed: sealed, with: wrongKey)
        }

        // Verify the real key still works
        let decrypted = try AnkyProtocol.decryptOwnSession(sealed: sealed)
        #expect(decrypted == content)
    }
}
