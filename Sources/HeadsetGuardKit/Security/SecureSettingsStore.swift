import Foundation
import Security

/// Where the serialized settings blob lives. Split out so the store logic is testable
/// without touching the real Keychain.
public protocol SettingsBlobBackend: AnyObject {
    /// nil means "no blob stored yet"; a throw means the read failed and must fail closed.
    func load() throws -> Data?
    func save(_ data: Data) -> Bool
}

public final class InMemoryBlobBackend: SettingsBlobBackend {
    public var blob: Data?
    public var shouldThrowError: CredentialStoreError?

    public init(blob: Data? = nil) {
        self.blob = blob
    }

    public func load() throws -> Data? {
        if let err = shouldThrowError { throw err }
        return blob
    }

    public func save(_ data: Data) -> Bool {
        blob = data
        return true
    }
}

public final class KeychainBlobBackend: SettingsBlobBackend {
    public static let service = KeychainCredentialStore.service
    public static let defaultAccount = "SecuritySettings"

    private let account: String

    public init(account: String = KeychainBlobBackend.defaultAccount) {
        self.account = account
    }

    public func load() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            NSLog("[KeychainBlobBackend] SecItemCopyMatching failed with OSStatus: %d", status)
            throw CredentialStoreError.keychainError(status)
        }
        guard let data = result as? Data else { throw CredentialStoreError.corruptData }
        return data
    }

    public func save(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        NSLog("[KeychainBlobBackend] SecItemUpdate failed with OSStatus: %d", updateStatus)
        return false
    }
}

/// Settings kept in a single Keychain item instead of UserDefaults, so editing
/// `defaults` (or the plist) can't switch protections off or reset lockout counters.
///
/// Failure behaviour is fail-closed: an unreadable or corrupt blob yields empty settings, so
/// callers fall back to their (secure) default values, and a failed read never lets a later
/// write overwrite the stored blob with partial data.
public final class SecureSettingsStore: SettingsStore {
    private let backend: SettingsBlobBackend
    private let lock = NSLock()

    /// Keys imported from UserDefaults the first time the secure blob is created.
    public static let importableKeys = [
        "AutoLockOnConnect", "LockOnSleep", "BiometricsEnabled", "MaxFailedAttempts",
        "AutoDisconnectOnFailure", "ProtectAllBluetooth", "ProtectedDevices"
    ]

    public init(backend: SettingsBlobBackend, legacyDefaults: UserDefaults? = nil) {
        self.backend = backend
        guard let defaults = legacyDefaults else { return }
        lock.lock()
        defer { lock.unlock() }
        // Only import when no blob exists yet; a read error imports nothing.
        do {
            guard try backend.load() == nil else { return }
        } catch {
            return
        }
        var imported: [String: Any] = [:]
        for key in Self.importableKeys {
            if let value = defaults.object(forKey: key) { imported[key] = value }
        }
        guard !imported.isEmpty, save(imported) else { return }
        for key in Self.importableKeys { defaults.removeObject(forKey: key) }
    }

    /// The blob is re-read on every access (no cache) so the app and the CLI, which are
    /// separate processes, always see each other's lockout counters and settings.
    /// A failed read returns nil so callers fail closed to their defaults and never write.
    private func read() -> [String: Any]? {
        do {
            guard let data = try backend.load() else { return [:] }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return obj }
            NSLog("[SecureSettingsStore] Stored settings were corrupt; using secure defaults.")
            return [:]
        } catch {
            NSLog("[SecureSettingsStore] Could not read settings (\(error)); failing closed to defaults.")
            return nil
        }
    }

    private func save(_ dict: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return false }
        return backend.save(data)
    }

    private func set(_ value: Any, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var dict = read() else { return }
        dict[key] = value
        _ = save(dict)
    }

    private func get(_ key: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return read()?[key]
    }

    public func bool(forKey key: String, defaultValue: Bool) -> Bool {
        return (get(key) as? NSNumber)?.boolValue ?? defaultValue
    }

    public func setBool(_ value: Bool, forKey key: String) { set(value, forKey: key) }

    public func integer(forKey key: String, defaultValue: Int) -> Int {
        return (get(key) as? NSNumber)?.intValue ?? defaultValue
    }

    public func setInteger(_ value: Int, forKey key: String) { set(value, forKey: key) }

    public func stringArray(forKey key: String) -> [String] {
        return (get(key) as? [String]) ?? []
    }

    public func setStringArray(_ value: [String], forKey key: String) { set(value, forKey: key) }

    public func string(forKey key: String) -> String? { get(key) as? String }

    public func setString(_ value: String, forKey key: String) { set(value, forKey: key) }

    public func data(forKey key: String) -> Data? {
        guard let b64 = get(key) as? String else { return nil }
        return Data(base64Encoded: b64)
    }

    public func removeObject(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var dict = read(), dict.removeValue(forKey: key) != nil else { return }
        _ = save(dict)
    }
}
