//
//  EthereumSeedIdentityCrypto.swift
//  Anky
//

import CommonCrypto
import CryptoKit
import Foundation
import Security

enum SeedIdentityCrypto {
    // This is the shipped mobile seed path. Do not change it without an
    // explicit migration plan and updated mnemonic/path/address/signature vectors.
    static let canonicalDerivationPath = "m/44'/60'/0'/0/0"

    private static let wordlist = MnemonicWordList_English
    private static let wordIndexLookup = Dictionary(uniqueKeysWithValues: wordlist.enumerated().map { ($1, $0) })
    private static let derivationPath: [UInt32] = [
        hardened(44),
        hardened(60),
        hardened(0),
        0,
        0,
    ]

    static func generateMnemonic() throws -> String {
        var entropy = Data(count: 32)
        let status = entropy.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 32, baseAddress)
        }

        guard status == errSecSuccess else {
            throw SeedIdentityError.entropyFailure
        }

        return try mnemonic(fromEntropy: entropy)
    }

    static func normalizedMnemonic(from phrase: String) throws -> String {
        let words = phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard words.count == 24 else {
            throw SeedIdentityError.invalidWordCount
        }

        let indexes = try words.map { word -> Int in
            guard let index = wordIndexLookup[word] else {
                throw SeedIdentityError.invalidWords
            }
            return index
        }

        var bits: [UInt8] = []
        bits.reserveCapacity(indexes.count * 11)
        for index in indexes {
            for shift in stride(from: 10, through: 0, by: -1) {
                bits.append(UInt8((index >> shift) & 1))
            }
        }

        let entropyBits = Array(bits.prefix(256))
        let checksumBits = Array(bits.suffix(8))
        let entropy = data(fromBits: entropyBits)
        let hashFirstByte = Data(SHA256.hash(data: entropy)).first ?? 0
        let expectedChecksum = (0..<8).map { shift in
            UInt8((hashFirstByte >> (7 - shift)) & 1)
        }

        guard checksumBits == expectedChecksum else {
            throw SeedIdentityError.invalidChecksum
        }

        return words.joined(separator: " ")
    }

    static func derivedPrivateKey(from mnemonic: String) throws -> Data {
        let normalizedMnemonic = try normalizedMnemonic(from: mnemonic)
        let seed = try mnemonicSeed(from: normalizedMnemonic)
        return try derivedPrivateKey(fromSeed: seed)
    }

    static func walletAddress(fromPrivateKey privateKeyData: Data) throws -> String {
        let publicKey = try uncompressedPublicKey(fromPrivateKey: privateKeyData)
        let addressData = keccak256(publicKey.dropFirst()).suffix(20)
        return checksumAddress(for: Data(addressData).hexString)
    }

    static func sign(message: Data, privateKeyData: Data) throws -> Data {
        let digest = personalMessageHash(message)
        return try signDigest(digest, privateKeyData: privateKeyData)
    }

    static func recoverWalletAddress(message: Data, signatureData: Data) throws -> String {
        let digest = personalMessageHash(message)
        return try recoverWalletAddress(digest: digest, signatureData: signatureData)
    }

    static func mnemonic(fromEntropy entropy: Data) throws -> String {
        let checksumByte = Data(SHA256.hash(data: entropy)).first ?? 0
        let checksumBits = entropy.count / 4
        var bits = entropy.flatMap { byte in
            (0..<8).map { shift in UInt8((byte >> (7 - shift)) & 1) }
        }
        bits.append(contentsOf: (0..<checksumBits).map { shift in
            UInt8((checksumByte >> (7 - shift)) & 1)
        })

        let words = stride(from: 0, to: bits.count, by: 11).map { offset -> String in
            let index = bits[offset..<(offset + 11)].reduce(0) { partial, bit in
                (partial << 1) | Int(bit)
            }
            return wordlist[index]
        }

        guard words.count == 24 else {
            throw SeedIdentityError.entropyFailure
        }

        return words.joined(separator: " ")
    }

    static func mnemonicSeed(from mnemonic: String) throws -> Data {
        let password = mnemonic.decomposedStringWithCompatibilityMapping
        let salt = "mnemonic".decomposedStringWithCompatibilityMapping

        guard let passwordData = password.data(using: .utf8), let saltData = salt.data(using: .utf8) else {
            throw SeedIdentityError.invalidWords
        }

        var derivedKey = Data(count: 64)
        let status = derivedKey.withUnsafeMutableBytes { derivedBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                saltData.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                        2048,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        64
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw SeedIdentityError.derivationFailure
        }

        return derivedKey
    }

    private static func derivedPrivateKey(fromSeed seed: Data) throws -> Data {
        let master = hmacSHA512(key: Data("Bitcoin seed".utf8), data: seed)
        var privateKey = Data(master.prefix(32))
        var chainCode = Data(master.suffix(32))

        guard try isValidPrivateKey(privateKey) else {
            throw SeedIdentityError.derivationFailure
        }

        for index in derivationPath {
            let derived = try deriveChildPrivateKey(parentPrivateKey: privateKey, parentChainCode: chainCode, index: index)
            privateKey = derived.privateKey
            chainCode = derived.chainCode
        }

        return privateKey
    }

    private static func deriveChildPrivateKey(
        parentPrivateKey: Data,
        parentChainCode: Data,
        index: UInt32
    ) throws -> (privateKey: Data, chainCode: Data) {
        var data = Data()
        if isHardened(index) {
            data.append(0x00)
            data.append(parentPrivateKey)
        } else {
            data.append(try compressedPublicKey(fromPrivateKey: parentPrivateKey))
        }
        data.append(contentsOf: index.bigEndianBytes)

        let output = hmacSHA512(key: parentChainCode, data: data)
        let tweak = Data(output.prefix(32))
        let chainCode = Data(output.suffix(32))
        let privateKey = try tweakedPrivateKey(parentPrivateKey: parentPrivateKey, tweak: tweak)
        return (privateKey, chainCode)
    }

    private static func tweakedPrivateKey(parentPrivateKey: Data, tweak: Data) throws -> Data {
        try withSecpContext { context in
            var childKey = [UInt8](parentPrivateKey)
            let tweakBytes = [UInt8](tweak)
            let didTweak = childKey.withUnsafeMutableBufferPointer { childBuffer in
                tweakBytes.withUnsafeBufferPointer { tweakBuffer in
                    secp256k1_ec_privkey_tweak_add(context, childBuffer.baseAddress!, tweakBuffer.baseAddress!)
                }
            }
            guard didTweak == 1 else {
                throw SeedIdentityError.derivationFailure
            }
            return Data(childKey)
        }
    }

    static func compressedPublicKey(fromPrivateKey privateKeyData: Data) throws -> Data {
        try serializePublicKey(fromPrivateKey: privateKeyData, compressed: true)
    }

    static func uncompressedPublicKey(fromPrivateKey privateKeyData: Data) throws -> Data {
        try serializePublicKey(fromPrivateKey: privateKeyData, compressed: false)
    }

    private static func serializePublicKey(fromPrivateKey privateKeyData: Data, compressed: Bool) throws -> Data {
        try withSecpContext { context in
            let secretKey = [UInt8](privateKeyData)
            let isValid = secretKey.withUnsafeBufferPointer { secretKeyBuffer in
                secp256k1_ec_seckey_verify(context, secretKeyBuffer.baseAddress!)
            }
            guard isValid == 1 else {
                throw SeedIdentityError.derivationFailure
            }

            var publicKey = secp256k1_pubkey()
            let didCreate = secretKey.withUnsafeBufferPointer { secretKeyBuffer in
                secp256k1_ec_pubkey_create(context, &publicKey, secretKeyBuffer.baseAddress!)
            }
            guard didCreate == 1 else {
                throw SeedIdentityError.derivationFailure
            }

            var outputLength = compressed ? 33 : 65
            var output = [UInt8](repeating: 0, count: outputLength)
            let flags = compressed ? UInt32(SECP256K1_EC_COMPRESSED) : UInt32(SECP256K1_EC_UNCOMPRESSED)
            let didSerialize = output.withUnsafeMutableBufferPointer { outputBuffer in
                secp256k1_ec_pubkey_serialize(context, outputBuffer.baseAddress!, &outputLength, &publicKey, flags)
            }
            guard didSerialize == 1 else {
                throw SeedIdentityError.derivationFailure
            }

            return Data(output.prefix(outputLength))
        }
    }

    private static func signDigest(_ digest: Data, privateKeyData: Data) throws -> Data {
        guard digest.count == 32 else {
            throw SeedIdentityError.signingFailure
        }

        return try withSecpContext { context in
            var signature = secp256k1_ecdsa_recoverable_signature()
            let secretKey = [UInt8](privateKeyData)
            let messageHash = [UInt8](digest)
            let didSign = messageHash.withUnsafeBufferPointer { messageHashBuffer in
                secretKey.withUnsafeBufferPointer { secretKeyBuffer in
                    secp256k1_ecdsa_sign_recoverable(
                        context,
                        &signature,
                        messageHashBuffer.baseAddress!,
                        secretKeyBuffer.baseAddress!,
                        nil,
                        nil
                    )
                }
            }
            guard didSign == 1 else {
                throw SeedIdentityError.signingFailure
            }

            var compact = [UInt8](repeating: 0, count: 64)
            var recoveryID: Int32 = 0
            let didSerialize = compact.withUnsafeMutableBufferPointer { compactBuffer in
                secp256k1_ecdsa_recoverable_signature_serialize_compact(
                    context,
                    compactBuffer.baseAddress!,
                    &recoveryID,
                    &signature
                )
            }
            guard didSerialize == 1 else {
                throw SeedIdentityError.signingFailure
            }

            compact.append(UInt8(recoveryID + 27))
            return Data(compact)
        }
    }

    private static func recoverWalletAddress(digest: Data, signatureData: Data) throws -> String {
        guard digest.count == 32, signatureData.count == 65 else {
            throw SeedIdentityError.signingFailure
        }

        return try withSecpContext { context in
            let signatureBytes = [UInt8](signatureData)
            let compact = Array(signatureBytes.prefix(64))
            let rawRecovery = Int32(signatureBytes[64] >= 27 ? signatureBytes[64] - 27 : signatureBytes[64])
            guard (0...3).contains(rawRecovery) else {
                throw SeedIdentityError.signingFailure
            }

            var signature = secp256k1_ecdsa_recoverable_signature()
            let didParse = compact.withUnsafeBufferPointer { compactBuffer in
                secp256k1_ecdsa_recoverable_signature_parse_compact(
                    context,
                    &signature,
                    compactBuffer.baseAddress!,
                    rawRecovery
                )
            }
            guard didParse == 1 else {
                throw SeedIdentityError.signingFailure
            }

            var publicKey = secp256k1_pubkey()
            let digestBytes = [UInt8](digest)
            let didRecover = digestBytes.withUnsafeBufferPointer { digestBuffer in
                secp256k1_ecdsa_recover(context, &publicKey, &signature, digestBuffer.baseAddress!)
            }
            guard didRecover == 1 else {
                throw SeedIdentityError.signingFailure
            }

            var outputLength = 65
            var output = [UInt8](repeating: 0, count: outputLength)
            let didSerialize = output.withUnsafeMutableBufferPointer { outputBuffer in
                secp256k1_ec_pubkey_serialize(
                    context,
                    outputBuffer.baseAddress!,
                    &outputLength,
                    &publicKey,
                    UInt32(SECP256K1_EC_UNCOMPRESSED)
                )
            }
            guard didSerialize == 1 else {
                throw SeedIdentityError.signingFailure
            }

            let addressData = keccak256(output.dropFirst()).suffix(20)
            return checksumAddress(for: Data(addressData).hexString)
        }
    }

    private static func personalMessageHash(_ message: Data) -> Data {
        let prefix = "\u{19}Ethereum Signed Message:\n\(message.count)"
        return keccak256(Data(prefix.utf8) + message)
    }

    private static func checksumAddress(for lowercaseHexAddress: String) -> String {
        let normalized = lowercaseHexAddress.lowercased()
        let hash = keccak256(Data(normalized.utf8)).hexString
        var checksummed = ""
        checksummed.reserveCapacity(normalized.count)

        for (index, character) in normalized.enumerated() {
            if character.isNumber {
                checksummed.append(character)
                continue
            }

            let hashIndex = hash.index(hash.startIndex, offsetBy: index)
            let nibble = Int(String(hash[hashIndex]), radix: 16) ?? 0
            checksummed.append(nibble >= 8 ? Character(String(character).uppercased()) : character)
        }

        return "0x" + checksummed
    }

    private static func keccak256(_ data: some DataProtocol) -> Data {
        var input = Array(data)
        var output = [UInt8](repeating: 0, count: 32)
        let inputCount = input.count
        let outputCount = output.count

        input.withUnsafeMutableBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                _ = keccak_256(
                    outputBuffer.baseAddress,
                    outputCount,
                    inputBuffer.baseAddress,
                    inputCount
                )
            }
        }

        return Data(output)
    }

    private static func isValidPrivateKey(_ privateKey: Data) throws -> Bool {
        try withSecpContext { context in
            let secretKey = [UInt8](privateKey)
            return secretKey.withUnsafeBufferPointer { secretKeyBuffer in
                secp256k1_ec_seckey_verify(context, secretKeyBuffer.baseAddress!) == 1
            }
        }
    }

    private static func withSecpContext<T>(_ block: (OpaquePointer) throws -> T) throws -> T {
        guard let context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY)) else {
            throw SeedIdentityError.derivationFailure
        }

        defer {
            secp256k1_context_destroy(context)
        }

        return try block(context)
    }

    private static func hmacSHA512(key: some DataProtocol, data: some DataProtocol) -> Data {
        let symmetricKey = SymmetricKey(data: Data(key))
        let authenticationCode = HMAC<SHA512>.authenticationCode(for: Data(data), using: symmetricKey)
        return Data(authenticationCode)
    }

    private static func data(fromBits bits: [UInt8]) -> Data {
        var bytes = Data(capacity: bits.count / 8)
        for offset in stride(from: 0, to: bits.count, by: 8) {
            let byte = bits[offset..<(offset + 8)].reduce(0) { partial, bit in
                (partial << 1) | bit
            }
            bytes.append(byte)
        }
        return bytes
    }

    private static func hardened(_ value: UInt32) -> UInt32 {
        0x8000_0000 | value
    }

    private static func isHardened(_ value: UInt32) -> Bool {
        value & 0x8000_0000 != 0
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    var hexStringPrefixed: String {
        "0x" + hexString
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        var value = bigEndian
        return withUnsafeBytes(of: &value) { Array($0) }
    }
}
