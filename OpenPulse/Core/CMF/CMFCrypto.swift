import Foundation
import CommonCrypto
import CryptoKit

/// Cryptographic building blocks used by the CMF watch protocol:
/// AES-128-CBC with PKCS#7 padding and a fixed IV, and SHA-256 for key derivation.
enum CMFCrypto {
    static let iv: [UInt8] = [0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57,
                              0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x5a]

    enum CryptoError: Error, LocalizedError {
        case cryptorFailed(Int32)
        case badKey

        var errorDescription: String? {
            switch self {
            case .cryptorFailed(let s): return "AES operation failed (status \(s))"
            case .badKey: return "Encryption key must be 16 bytes"
            }
        }
    }

    static func encrypt(_ data: [UInt8], key: [UInt8]) throws -> [UInt8] {
        try aes(CCOperation(kCCEncrypt), data: data, key: key)
    }

    static func decrypt(_ data: [UInt8], key: [UInt8]) throws -> [UInt8] {
        try aes(CCOperation(kCCDecrypt), data: data, key: key)
    }

    private static func aes(_ op: CCOperation, data: [UInt8], key: [UInt8]) throws -> [UInt8] {
        guard key.count == kCCKeySizeAES128 else { throw CryptoError.badKey }
        let outCapacity = data.count + kCCBlockSizeAES128
        var out = [UInt8](repeating: 0, count: outCapacity)
        var moved = 0
        let ivCopy = iv
        let status = CCCrypt(op,
                             CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionPKCS7Padding),
                             key, key.count,
                             ivCopy,
                             data, data.count,
                             &out, outCapacity,
                             &moved)
        guard status == CCCryptorStatus(kCCSuccess) else { throw CryptoError.cryptorFailed(status) }
        return Array(out.prefix(moved))
    }

    static func sha256(_ parts: [UInt8]...) -> [UInt8] {
        var hasher = SHA256()
        for p in parts { hasher.update(data: Data(p)) }
        return Array(hasher.finalize())
    }

    static func randomBytes(_ count: Int) -> [UInt8] {
        var g = SystemRandomNumberGenerator()
        return (0..<count).map { _ in UInt8.random(in: 0...255, using: &g) }
    }
}
