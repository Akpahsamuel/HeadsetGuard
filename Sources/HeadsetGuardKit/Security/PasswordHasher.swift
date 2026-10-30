import Foundation
import CommonCrypto
import Security

public enum PasswordHasher {
    public static let iterations: UInt32 = 310_000

    public static func hash(_ password: String, salt: Data) -> String {
        guard let passwordData = password.data(using: .utf8) else { return "" }
        var derivedKey = [UInt8](repeating: 0, count: 32)

        _ = passwordData.withUnsafeBytes { passBytes in
            salt.withUnsafeBytes { saltBytes in
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
