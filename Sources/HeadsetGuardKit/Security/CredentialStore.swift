import Foundation
import Security

public enum CredentialStoreError: Error, Equatable {
    case keychainError(OSStatus)
    case corruptData
}

public protocol CredentialStore: AnyObject {
    func load() throws -> (hash: String, salt: Data)?
    func save(hash: String, salt: Data) -> Bool
    func clear()
}

public final class InMemoryCredentialStore: CredentialStore {
    private var stored: (hash: String, salt: Data)?
    public var shouldThrowError: CredentialStoreError?

    public init(stored: (hash: String, salt: Data)? = nil) {
        self.stored = stored
    }

    public func load() throws -> (hash: String, salt: Data)? {
        if let err = shouldThrowError {
            throw err
        }
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

    public func load() throws -> (hash: String, salt: Data)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            NSLog("[KeychainCredentialStore] SecItemCopyMatching failed with OSStatus: %d", status)
            throw CredentialStoreError.keychainError(status)
        }

        guard let data = result as? Data, let parsed = Self.parse(data: data) else {
            NSLog("[KeychainCredentialStore] Failed to parse Keychain JSON data.")
            throw CredentialStoreError.corruptData
        }

        return parsed
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

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        // Try updating existing item in-place first (atomic - old password is NOT deleted)
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        // If item did not exist yet, add it
        if updateStatus == errSecItemNotFound {
            var addAttributes = query
            addAttributes[kSecValueData as String] = data
            addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
            return addStatus == errSecSuccess
        }

        NSLog("[KeychainCredentialStore] SecItemUpdate failed with OSStatus: %d", updateStatus)
        return false
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
