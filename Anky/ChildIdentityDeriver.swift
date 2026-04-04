import CryptoKit
import Foundation

enum ChildIdentityDeriver {
    private static let parentPrivateKeyKey = "anky.seed.private-key"

    static func deriveWalletAddress(
        parentWalletAddress: String,
        name: String,
        birthdate: String
    ) throws -> String {
        let parentPrivateKey = try loadParentPrivateKey()
        let saltInput = Data("\(parentWalletAddress)\(name)\(birthdate)".utf8)
        let salt = Data(SHA256.hash(data: saltInput))

        // XOR parent key with salt to derive a deterministic child seed
        var childSeed = Data(count: 32)
        for i in 0..<32 {
            childSeed[i] = parentPrivateKey[i] ^ salt[i]
        }

        // Hash to ensure uniform distribution
        let childKey = Data(SHA256.hash(data: childSeed))
        return try SeedIdentityCrypto.walletAddress(fromPrivateKey: childKey)
    }

    private static func loadParentPrivateKey() throws -> Data {
        guard let privateKey = KeychainHelper.getData(parentPrivateKeyKey, synchronizable: true) else {
            throw SeedIdentityError.missingIdentity
        }

        return privateKey
    }
}
