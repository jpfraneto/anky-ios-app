//
//  SolanaSeedIdentityCrypto.swift
//  Anky
//
//  Solana-native Ed25519 wallet derivation via SLIP-0010.
//  BIP39 mnemonic → PBKDF2 seed → SLIP-0010 m/44'/501'/0'/0' → Ed25519 keypair → base58 address.
//  No external dependencies — uses CryptoKit for Ed25519 and HMAC-SHA512.
//

import CommonCrypto
import CryptoKit
import Foundation
import Security

enum SeedIdentityCrypto {
    // Solana derivation path (SLIP-0010 / BIP44).
    // All indices hardened as required by Ed25519 SLIP-0010.
    static let canonicalDerivationPath = "m/44'/501'/0'/0'"

    private static let wordlist = MnemonicWordList_English
    private static let wordIndexLookup = Dictionary(uniqueKeysWithValues: wordlist.enumerated().map { ($1, $0) })
    private static let derivationPath: [UInt32] = [
        hardened(44),
        hardened(501),
        hardened(0),
        hardened(0),
    ]

    // MARK: - BIP39 Mnemonic (chain-agnostic)

    static func generateMnemonic() throws -> String {
        var entropy = Data(count: 16)
        let status = entropy.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 16, baseAddress)
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

        guard words.count == 12 || words.count == 24 else {
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

        let totalBits = words.count * 11
        let checksumLen = words.count == 12 ? 4 : 8
        let entropyLen = totalBits - checksumLen
        let entropyBits = Array(bits.prefix(entropyLen))
        let checksumBits = Array(bits.suffix(checksumLen))
        let entropy = data(fromBits: entropyBits)
        let hashFirstByte = Data(SHA256.hash(data: entropy)).first ?? 0
        let expectedChecksum = (0..<checksumLen).map { shift in
            UInt8((hashFirstByte >> (7 - shift)) & 1)
        }

        guard checksumBits == expectedChecksum else {
            throw SeedIdentityError.invalidChecksum
        }

        return words.joined(separator: " ")
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

        guard words.count == 12 || words.count == 24 else {
            throw SeedIdentityError.entropyFailure
        }

        return words.joined(separator: " ")
    }

    // MARK: - BIP39 Seed

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

    // MARK: - SLIP-0010 Ed25519 Key Derivation

    /// Derives the Ed25519 private key (32 bytes) from a BIP39 mnemonic via SLIP-0010.
    static func derivedPrivateKey(from mnemonic: String) throws -> Data {
        let normalizedMnemonic = try normalizedMnemonic(from: mnemonic)
        let seed = try mnemonicSeed(from: normalizedMnemonic)
        return derivedPrivateKey(fromSeed: seed)
    }

    private static func derivedPrivateKey(fromSeed seed: Data) -> Data {
        // SLIP-0010 master key uses "ed25519 seed" as the HMAC key (not "Bitcoin seed").
        let master = hmacSHA512(key: Data("ed25519 seed".utf8), data: seed)
        var privateKey = Data(master.prefix(32))
        var chainCode = Data(master.suffix(32))

        for index in derivationPath {
            let derived = deriveChildKey(parentKey: privateKey, parentChainCode: chainCode, index: index)
            privateKey = derived.key
            chainCode = derived.chainCode
        }

        return privateKey
    }

    /// SLIP-0010 child key derivation for Ed25519.
    /// Ed25519 only supports hardened derivation: HMAC-SHA512(chainCode, 0x00 || key || index).
    private static func deriveChildKey(
        parentKey: Data,
        parentChainCode: Data,
        index: UInt32
    ) -> (key: Data, chainCode: Data) {
        var data = Data([0x00])
        data.append(parentKey)
        data.append(contentsOf: index.bigEndianBytes)

        let output = hmacSHA512(key: parentChainCode, data: data)
        return (key: Data(output.prefix(32)), chainCode: Data(output.suffix(32)))
    }

    // MARK: - Solana Address (Ed25519 public key as base58)

    /// Returns the Solana address (base58-encoded 32-byte Ed25519 public key).
    static func walletAddress(fromPrivateKey privateKeyData: Data) throws -> String {
        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        let publicKey = signingKey.publicKey.rawRepresentation
        return Base58.encode(Data(publicKey))
    }

    /// Returns the raw 32-byte Ed25519 public key.
    static func publicKey(fromPrivateKey privateKeyData: Data) throws -> Data {
        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        return Data(signingKey.publicKey.rawRepresentation)
    }

    // MARK: - Ed25519 Signing

    /// Signs a message with the Ed25519 private key. Returns a 64-byte signature.
    static func sign(message: Data, privateKeyData: Data) throws -> Data {
        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        return try Data(signingKey.signature(for: message))
    }

    /// Verifies an Ed25519 signature.
    static func verify(message: Data, signature: Data, publicKeyData: Data) throws -> Bool {
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        return publicKey.isValidSignature(signature, for: message)
    }

    // MARK: - Helpers

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
}

// MARK: - Base58 Encoder/Decoder

enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let baseCount = UInt(alphabet.count) // 58

    static func encode(_ data: Data) -> String {
        var bytes = Array(data)
        var result: [Character] = []

        // Count leading zeros
        let leadingZeros = bytes.prefix(while: { $0 == 0 }).count

        // Convert to base58
        while !bytes.isEmpty {
            var carry = UInt(0)
            var newBytes: [UInt8] = []
            for byte in bytes {
                carry = carry * 256 + UInt(byte)
                if !newBytes.isEmpty || carry >= baseCount {
                    newBytes.append(UInt8(carry / baseCount))
                    carry = carry % baseCount
                }
            }
            result.append(alphabet[Int(carry)])
            bytes = newBytes
        }

        // Add leading '1' for each leading zero byte
        let ones = Array(repeating: alphabet[0], count: leadingZeros)
        return String(ones + result.reversed())
    }

    static func decode(_ string: String) -> Data? {
        let inverseAlphabet: [Character: UInt] = Dictionary(
            uniqueKeysWithValues: alphabet.enumerated().map { (Character(String($1)), UInt($0)) }
        )

        var result: [UInt8] = []
        let leadingOnes = string.prefix(while: { $0 == "1" }).count

        for char in string {
            guard let value = inverseAlphabet[char] else { return nil }
            var carry = value
            for i in stride(from: result.count - 1, through: 0, by: -1) {
                carry += UInt(result[i]) * 58
                result[i] = UInt8(carry % 256)
                carry /= 256
            }
            while carry > 0 {
                result.insert(UInt8(carry % 256), at: 0)
                carry /= 256
            }
        }

        let zeros = Array(repeating: UInt8(0), count: leadingOnes)
        return Data(zeros + result)
    }
}

// MARK: - Data Extensions

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
