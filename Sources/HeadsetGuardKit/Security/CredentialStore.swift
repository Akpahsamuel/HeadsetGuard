import Foundation
import Security

public protocol CredentialStore: AnyObject {
    func load() -> (hash: String, salt: Data)?
    func save(hash: String, salt: Data) -> Bool
    func clear()
}

public final class InMemoryCredentialStore: CredentialStore {
    private var stored: (hash: String, salt: Data)?

    public init(stored: (hash: String, salt: Data)? = nil) {
        self.stored = stored
    }

    public func load() -> (hash: String, salt: Data)? {
        return stored
    }

    public func save(hash: String, salt: Data) -> Bool {
        stored = (hash, salt)
        return true
    }

    public func clear() {
        stored = nil
    }
}

public final class KeychainCredentialStore: CredentialStore {
    public static let service = "com.security.HeadsetGuard"
    public static let account = "MasterPasswordCredentials"

    public init() {}

    public static func parse(data: Data) -> (hash: String, salt: Data)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hash = json["hash"] as? String,
              let saltB64 = json["salt"] as? String,
              let salt = Data(base64Encoded: saltB64) else {
            return nil
        }
        return (hash, salt)
    }

    public static func serialize(hash: String, salt: Data) -> Data? {
        let payload: [String: Any] = [
            "hash": hash,
            "salt": salt.base64EncodedString()
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    public func load() -> (hash: String, salt: Data)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return Self.parse(data: data)
    }

    public func save(hash: String, salt: Data) -> Bool {
        guard let data = Self.serialize(hash: hash, salt: salt) else {
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    public func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
