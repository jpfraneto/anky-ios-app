//
//  AnkyTests.swift
//  AnkyTests
//
//  Created by kithkui on 07-03-26.
//

import Foundation
import Testing
@testable import Anky

struct AnkyTests {
    private let vectorEntropyHex = "0000000000000000000000000000000000000000000000000000000000000000"
    private let vectorMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
    private let vectorSeedHex = "408b285c123836004f4b8842c89324c1f01382450c0d439af345ba7fc49acf705489c6fc77dbd4e3dc1dd8cc6bc9f043db8ada1e243c4a0eafb290d399480840"
    private let vectorPrivateKeyHex = "1053fae1b3ac64f178bcc21026fd06a3f4544ec2f35338b001f02d1d8efa3d5f"
    private let vectorCompressedPublicKeyHex = "02dc286c821c7490afbe20a79d13123b9f41f3d7ef21e4a9caacd22f5983b28eca"
    private let vectorUncompressedPublicKeyHex = "04dc286c821c7490afbe20a79d13123b9f41f3d7ef21e4a9caacd22f5983b28eca0e4dbd5624505a2c968fec15f25990c7324736890f6d0f74241f98e4259c1d42"
    private let vectorWalletAddress = "0xF278cF59F82eDcf871d630F28EcC8056f25C1cdb"
    private let vectorChallengeMessage = """
anky.app seed identity sign in

wallet address: 0xF278cF59F82eDcf871d630F28EcC8056f25C1cdb
challenge id: 2d3b2f85-b7e1-4495-8f2f-9f3d9b9ed211
nonce: 5f2c4e5d6d4e0d6ff0e4f2ed57fe2c1f9d0c4a7b8f2712bda20f450f9dc22b22

sign this only inside the anky app.
"""
    private let vectorSignatureHex = "ab6d76173e510ed88f93adc2729fabf1de2af03208115665a21a5e8da9cd2e7650203cc71fcb5b68a18008b799e7abc2bd4b939d32a7dba0672134c25a075e4e1b"

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

    @Test("App copy localizes the backup ceremony and tab labels")
    func appCopyLocalizationResolvesCleanly() {
        let spanish = AppCopy(languageCode: "es")
        let fallback = AppCopy(languageCode: "xx")

        #expect(spanish[.backupTitle] == "Tu frase de recuperacion")
        #expect(spanish[.seedTab] == "SEMILLA")
        #expect(fallback[.backupSavedAction] == "I saved it")
    }

    @Test("Canonical EVM derivation path stays frozen")
    func canonicalDerivationPathStaysFrozen() {
        #expect(SeedIdentityCrypto.canonicalDerivationPath == "m/44'/60'/0'/0/0")
    }

    @Test("Seed phrases reject an invalid checksum")
    func seedPhraseValidationRejectsBadChecksum() {
        let invalidMnemonic = vectorMnemonic.replacingOccurrences(of: " art", with: " abandon")

        do {
            _ = try SeedIdentityCrypto.normalizedMnemonic(from: invalidMnemonic)
            Issue.record("Expected an invalid checksum to be rejected.")
        } catch let error as SeedIdentityError {
            #expect(error == .invalidChecksum)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Seed vectors match mnemonic, seed, EVM path, public keys, and address")
    func seedVectorsMatchKnownOutputs() throws {
        let entropy = try #require(Data(hexString: vectorEntropyHex))
        let mnemonic = try SeedIdentityCrypto.mnemonic(fromEntropy: entropy)
        let normalizedMnemonic = try SeedIdentityCrypto.normalizedMnemonic(from: vectorMnemonic.uppercased())
        let seed = try SeedIdentityCrypto.mnemonicSeed(from: vectorMnemonic)
        let privateKeyData = try SeedIdentityCrypto.derivedPrivateKey(from: vectorMnemonic)
        let compressedPublicKey = try SeedIdentityCrypto.compressedPublicKey(fromPrivateKey: privateKeyData)
        let uncompressedPublicKey = try SeedIdentityCrypto.uncompressedPublicKey(fromPrivateKey: privateKeyData)
        let walletAddress = try SeedIdentityCrypto.walletAddress(fromPrivateKey: privateKeyData)

        #expect(mnemonic == vectorMnemonic)
        #expect(normalizedMnemonic == vectorMnemonic)
        #expect(seed.hexString == vectorSeedHex)
        #expect(privateKeyData.hexString == vectorPrivateKeyHex)
        #expect(compressedPublicKey.hexString == vectorCompressedPublicKeyHex)
        #expect(uncompressedPublicKey.hexString == vectorUncompressedPublicKeyHex)
        #expect(walletAddress == vectorWalletAddress)
    }

    @Test("Ethereum challenge signatures match the known vector and recover the wallet address")
    func seedSignatureVectorVerifies() throws {
        let privateKeyData = try SeedIdentityCrypto.derivedPrivateKey(from: vectorMnemonic)
        let signature = try SeedIdentityCrypto.sign(message: Data(vectorChallengeMessage.utf8), privateKeyData: privateKeyData)
        let recoveredWalletAddress = try SeedIdentityCrypto.recoverWalletAddress(
            message: Data(vectorChallengeMessage.utf8),
            signatureData: signature
        )

        #expect(signature.hexString == vectorSignatureHex)
        #expect(recoveredWalletAddress == vectorWalletAddress)
    }

    @Test("Live backend EVM challenge flow can be run when the hosted validator accepts 0x addresses")
    func liveBackendChallengeFlow() async throws {
        guard ProcessInfo.processInfo.environment["ANKY_LIVE_BACKEND"] == "1" else { return }

        let api = AnkyAPI(baseURL: URL(string: "https://anky.app/swift/v2")!)
        let privateKeyData = try SeedIdentityCrypto.derivedPrivateKey(from: vectorMnemonic)
        let walletAddress = try SeedIdentityCrypto.walletAddress(fromPrivateKey: privateKeyData)
        let challenge = try await api.authChallenge(walletAddress: walletAddress)
        let signature = try SeedIdentityCrypto.sign(message: Data(challenge.message.utf8), privateKeyData: privateKeyData)
        let verify = try await api.verifyAuthChallenge(
            walletAddress: walletAddress,
            challengeID: challenge.challengeId,
            signature: signature.hexStringPrefixed
        )

        KeychainHelper.delete(AppState.sessionTokenKey)
        #expect(verify.ok)
        #expect(verify.walletAddress == walletAddress)
    }
}

private extension Data {
    init?(hexString: String) {
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex

        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard nextIndex <= hexString.endIndex else { return nil }
            let byteString = hexString[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
