import Foundation
import CommonCrypto
import Security

public enum PasswordHasher {
    public static let iterations: UInt32 = 310_000

    public static func hash(_ password: String, salt: Data) -> String {
        guard let passwordData = password.data(using: .utf8), !salt.isEmpty else { return "" }
        var derivedKey = [UInt8](repeating: 0, count: 32)

        let status = passwordData.withUnsafeBytes { passBytes -> Int32 in
            salt.withUnsafeBytes { saltBytes -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                    passwordData.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &derivedKey,
                    derivedKey.count
                )
            }
        }

        guard status == kCCSuccess else {
            NSLog("[PasswordHasher] CCKeyDerivationPBKDF failed with status: %d", status)
            return ""
        }

        return Data(derivedKey).base64EncodedString()
    }

    public static func makeSalt() -> Data? {
        var salt = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        if status == errSecSuccess {
            return Data(salt)
        }
        return nil
    }
}
