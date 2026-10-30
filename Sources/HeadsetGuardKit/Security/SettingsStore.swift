import Foundation

public protocol SettingsStore: AnyObject {
    func bool(forKey key: String, defaultValue: Bool) -> Bool
    func setBool(_ value: Bool, forKey key: String)
    func integer(forKey key: String, defaultValue: Int) -> Int
    func setInteger(_ value: Int, forKey key: String)
    func stringArray(forKey key: String) -> [String]
    func setStringArray(_ value: [String], forKey key: String)
    func string(forKey key: String) -> String?
    func data(forKey key: String) -> Data?
    func removeObject(forKey key: String)
}

public final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard let val = defaults.object(forKey: key) else { return defaultValue }
        return (val as? NSNumber)?.boolValue ?? defaultValue
    }

    public func setBool(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func integer(forKey key: String, defaultValue: Int) -> Int {
        guard let val = defaults.object(forKey: key) else { return defaultValue }
        return (val as? NSNumber)?.intValue ?? defaultValue
    }

    public func setInteger(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func stringArray(forKey key: String) -> [String] {
        return defaults.stringArray(forKey: key) ?? []
    }

    public func setStringArray(_ value: [String], forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func string(forKey key: String) -> String? {
        return defaults.string(forKey: key)
    }

    public func data(forKey key: String) -> Data? {
        return defaults.data(forKey: key)
    }

    public func removeObject(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

public final class InMemorySettingsStore: SettingsStore {
    private var storage: [String: Any] = [:]

    public init(initial: [String: Any] = [:]) {
        self.storage = initial
    }

    public func bool(forKey key: String, defaultValue: Bool) -> Bool {
        return (storage[key] as? Bool) ?? defaultValue
    }

    public func setBool(_ value: Bool, forKey key: String) {
        storage[key] = value
    }

    public func integer(forKey key: String, defaultValue: Int) -> Int {
        return (storage[key] as? Int) ?? defaultValue
    }

    public func setInteger(_ value: Int, forKey key: String) {
        storage[key] = value
    }

    public func stringArray(forKey key: String) -> [String] {
        return (storage[key] as? [String]) ?? []
    }

    public func setStringArray(_ value: [String], forKey key: String) {
        storage[key] = value
    }

    public func string(forKey key: String) -> String? {
        return storage[key] as? String
    }

    public func data(forKey key: String) -> Data? {
        return storage[key] as? Data
    }

    public func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
    }
}
