import Foundation
import LocalAuthentication
import Security

public let kSecuritySettingAutoLockOnConnect          = "AutoLockOnConnect"
public let kSecuritySettingLockOnSleep                = "LockOnSleep"
public let kSecuritySettingBiometricsEnabled          = "BiometricsEnabled"
public let kSecuritySettingMaxFailedAttempts          = "MaxFailedAttempts"
public let kSecuritySettingAutoDisconnectOnFailure    = "AutoDisconnectOnFailure"
public let kSecuritySettingProtectAllBluetooth        = "ProtectAllBluetooth"
public let kSecuritySettingProtectedDevices           = "ProtectedDevices"

private let kCredentialConfiguredKey = "CredentialConfigured"
private let kAuditKeyKey = "AuditHMACKey"
private let kFailedAttemptsKey = "FailedAttemptsCount"
private let kLockoutUntilKey = "LockoutUntilEpoch"

private let kLegacyMasterPasswordHashKey = "MasterPasswordHash"
private let kLegacyMasterPasswordSaltKey = "MasterPasswordSalt"

@objc(SecurityManager)
public final class SecurityManager: NSObject {

    @objc(sharedManager)
    public static let shared = SecurityManager()

    private let store: CredentialStore
    private let settings: SettingsStore
    private let auditLog: AuditLog

    public static let minimumPasswordLength = 6
    private static let baseLockoutSeconds = 30
    private static let maxLockoutSeconds = 3600

    private let stateLock = NSLock()

    /// Persisted so reconnecting the headset or relaunching the app cannot reset it.
    @objc public var failedAttemptsCount: Int {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return settings.integer(forKey: kFailedAttemptsKey, defaultValue: 0)
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            settings.setInteger(newValue, forKey: kFailedAttemptsKey)
        }
    }

    /// Configured attempt limit, clamped so a tampered value can't disable lockout.
    public var maxFailedAttempts: Int {
        let v = settings.integer(forKey: kSecuritySettingMaxFailedAttempts, defaultValue: 3)
        return min(max(v, 1), 10)
    }

    /// Seconds left in the current cooldown (0 when not locked out).
    @objc public func lockoutRemaining() -> TimeInterval {
        stateLock.lock()
        defer { stateLock.unlock() }
        let until = settings.integer(forKey: kLockoutUntilKey, defaultValue: 0)
        // Cap at the maximum cooldown so a clock change or planted value can't lock the owner
        // out for longer than the policy allows.
        return min(max(0, TimeInterval(until) - Date().timeIntervalSince1970), TimeInterval(Self.maxLockoutSeconds))
    }

    private func registerFailure() {
        stateLock.lock()
        defer { stateLock.unlock() }
        let count = settings.integer(forKey: kFailedAttemptsKey, defaultValue: 0) + 1
        settings.setInteger(count, forKey: kFailedAttemptsKey)
        let limit = min(max(settings.integer(forKey: kSecuritySettingMaxFailedAttempts, defaultValue: 3), 1), 10)
        if count >= limit {
            // Exponential cooldown: 30s, 60s, 120s ... capped at 1h.
            let exp = min(count - limit, 7)
            let delay = min(Self.baseLockoutSeconds << exp, Self.maxLockoutSeconds)
            settings.setInteger(Int(Date().timeIntervalSince1970) + delay, forKey: kLockoutUntilKey)
        }
    }

    private func clearFailures() {
        stateLock.lock()
        defer { stateLock.unlock() }
        settings.setInteger(0, forKey: kFailedAttemptsKey)
        settings.setInteger(0, forKey: kLockoutUntilKey)
    }

    @objc public var isPasswordConfigured: Bool {
        do {
            guard let creds = try store.load() else {
                // A PIN was set before but the stored credential is gone: someone removed it.
                // Stay configured (fail closed) so first-run setup can't be used to take over;
                // the owner can recover with resetPasswordWithOwnerAuth.
                if settings.bool(forKey: kCredentialConfiguredKey, defaultValue: false) {
                    NSLog("[SecurityManager] Credential missing from Keychain but previously configured. Failing closed.")
                    return true
                }
                return false
            }
            return !creds.hash.isEmpty && !creds.salt.isEmpty
        } catch {
            // Keychain read error: FAIL CLOSED.
            // Returning true ensures the unlock window treats the system as secured
            // and does not allow unauthorized first-time password overwrite!
            NSLog("[SecurityManager] Error loading credentials from Keychain: \(error). Failing closed as configured.")
            return true
        }
    }

    @objc public var biometricsAvailable: Bool {
        guard settings.bool(forKey: kSecuritySettingBiometricsEnabled, defaultValue: true) else {
            return false
        }
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// `legacy` is where pre-Keychain credentials may still sit (UserDefaults); defaults to `settings`.
    public init(store: CredentialStore, settings: SettingsStore, log: AuditLog, legacy: SettingsStore? = nil) {
        self.store = store
        self.settings = settings
        self.auditLog = log
        super.init()
        migrateLegacyCredentialsIfNeeded(from: legacy ?? settings)
        recordCredentialMarkerIfNeeded()
    }

    public convenience override init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("HeadsetGuard")
        let fileURL = dir.appendingPathComponent("audit_logs.json")

        // Settings (including lockout counters) live in the Keychain, not UserDefaults.
        let secure = SecureSettingsStore(backend: KeychainBlobBackend(), legacyDefaults: .standard)

        var auditKey = secure.data(forKey: kAuditKeyKey)
        if auditKey == nil, let fresh = PasswordHasher.makeSalt() {
            // Stored as base64 text because the settings blob is JSON.
            secure.setString(fresh.base64EncodedString(), forKey: kAuditKeyKey)
            auditKey = fresh
        }

        self.init(store: KeychainCredentialStore(),
                  settings: secure,
                  log: AuditLog(fileURL: fileURL, hmacKey: auditKey, headStore: secure),
                  legacy: UserDefaultsSettingsStore())
    }

    private func recordCredentialMarkerIfNeeded() {
        if !settings.bool(forKey: kCredentialConfiguredKey, defaultValue: false),
           let creds = try? store.load(), !creds.hash.isEmpty {
            settings.setBool(true, forKey: kCredentialConfiguredKey)
        }
    }

    private func migrateLegacyCredentialsIfNeeded(from legacy: SettingsStore) {
        // Never let UserDefaults values replace a credential already in the store,
        // and don't migrate if the store can't be read (fail closed).
        let existing: (hash: String, salt: Data)?
        do {
            existing = try store.load()
        } catch {
            return
        }
        if existing != nil {
            legacy.removeObject(forKey: kLegacyMasterPasswordHashKey)
            legacy.removeObject(forKey: kLegacyMasterPasswordSaltKey)
            return
        }
        // A cleared credential for an installation that was already configured must not be
        // silently replaced by planted legacy values.
        if settings.bool(forKey: kCredentialConfiguredKey, defaultValue: false) { return }
        if let legacyHash = legacy.string(forKey: kLegacyMasterPasswordHashKey),
           let legacySalt = legacy.data(forKey: kLegacyMasterPasswordSaltKey),
           !legacyHash.isEmpty, !legacySalt.isEmpty {
            if store.save(hash: legacyHash, salt: legacySalt) {
                legacy.removeObject(forKey: kLegacyMasterPasswordHashKey)
                legacy.removeObject(forKey: kLegacyMasterPasswordSaltKey)
            }
        }
    }

    // MARK: - Password Management

    @objc public func setupMasterPassword(_ password: String) throws {
        if password.count < Self.minimumPasswordLength {
            throw NSError(domain: "HeadsetGuard",
                          code: 1001,
                          userInfo: [NSLocalizedDescriptionKey: "Password must be at least \(Self.minimumPasswordLength) characters long."])
        }

        guard let salt = PasswordHasher.makeSalt() else {
            throw NSError(domain: "HeadsetGuard",
                          code: 1003,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to generate security salt."])
        }

        let hash = PasswordHasher.hash(password, salt: salt)
        guard !hash.isEmpty, store.save(hash: hash, salt: salt) else {
            throw NSError(domain: "HeadsetGuard",
                          code: 1003,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to save credentials to macOS Keychain."])
        }

        settings.setBool(true, forKey: kCredentialConfiguredKey)
        clearFailures()
        logEvent("Password Set", details: "New master password configured in Keychain", type: "security")
    }

    @objc public func changePassword(from oldPassword: String, to newPassword: String) throws {
        if !verifyPassword(oldPassword) {
            throw NSError(domain: "HeadsetGuard",
                          code: 1002,
                          userInfo: [NSLocalizedDescriptionKey: "Current password is incorrect."])
        }
        try setupMasterPassword(newPassword)
    }

    /// Recovery path for a lost or removed PIN: the Mac's owner (login password / Touch ID /
    /// Apple Watch) authorizes setting a new one. Works even if the stored credential is gone.
    @objc public func resetPasswordWithOwnerAuth(to newPassword: String,
                                                 reason: String,
                                                 completion: @escaping (Bool, Error?) -> Void) {
        if newPassword.count < Self.minimumPasswordLength {
            completion(false, NSError(domain: "HeadsetGuard", code: 1001,
                                      userInfo: [NSLocalizedDescriptionKey: "Password must be at least \(Self.minimumPasswordLength) characters long."]))
            return
        }
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            completion(false, authError)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                guard success else {
                    self.logEvent("PIN Reset Denied", details: "Owner authentication failed or cancelled", type: "auth_failure")
                    completion(false, error)
                    return
                }
                do {
                    try self.setupMasterPassword(newPassword)
                    self.logEvent("PIN Reset", details: "Master PIN reset using Mac owner authentication", type: "security")
                    completion(true, nil)
                } catch {
                    completion(false, error)
                }
            }
        }
    }

    private func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        guard let aData = a.data(using: .utf8), let bData = b.data(using: .utf8) else { return false }
        guard aData.count == bData.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(aData, bData) {
            diff |= (x ^ y)
        }
        return diff == 0
    }

    @objc public func verifyPassword(_ password: String) -> Bool {
        if lockoutRemaining() > 0 {
            logEvent("Password Rejected", details: "Attempt during cooldown", type: "auth_failure")
            return false
        }

        let creds: (hash: String, salt: Data)?
        do {
            creds = try store.load()
        } catch {
            NSLog("[SecurityManager] Keychain error during verification: \(error)")
            registerFailure()
            logEvent("Password Failed", details: "Keychain read error: \(error.localizedDescription)", type: "auth_failure")
            return false
        }

        guard let creds = creds, !creds.hash.isEmpty, !creds.salt.isEmpty else {
            return false
        }

        let testHash = PasswordHasher.hash(password, salt: creds.salt)
        let valid = !testHash.isEmpty && constantTimeCompare(testHash, creds.hash)

        if valid {
            clearFailures()
            logEvent("Password Verified", details: "Authentication successful", type: "auth_success")
        } else {
            registerFailure()
            logEvent("Password Failed", details: "Attempt \(failedAttemptsCount) failed", type: "auth_failure")
        }
        return valid
    }

    // MARK: - Biometrics

    @objc(authenticateWithBiometricsWithReason:completion:)
    public func authenticateWithBiometrics(reason: String, completion: @escaping (Bool, Error?) -> Void) {
        guard settings.bool(forKey: kSecuritySettingBiometricsEnabled, defaultValue: true) else {
            DispatchQueue.main.async { completion(false, nil) }
            return
        }

        let context = LAContext()
        // Biometrics only: an empty fallback title hides the "Enter Password" button so the
        // Mac login password can't stand in for the master PIN.
        context.localizedFallbackTitle = ""

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            DispatchQueue.main.async { completion(false, authError) }
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.clearFailures()
                    self.logEvent("Biometrics Success", details: "Unlocked via Touch ID / Mac Auth", type: "auth_success")
                } else if let error = error {
                    self.logEvent("Biometrics Cancelled/Failed", details: error.localizedDescription, type: "auth_failure")
                }
                completion(success, error)
            }
        }
    }

    public func authenticateWithBiometrics(withReason reason: String, completion: @escaping (Bool, Error?) -> Void) {
        authenticateWithBiometrics(reason: reason, completion: completion)
    }

    // MARK: - Settings

    @objc(boolSetting:defaultValue:)
    public func boolSetting(_ key: String, defaultValue: Bool) -> Bool {
        return settings.bool(forKey: key, defaultValue: defaultValue)
    }

    @objc(setBoolSetting:value:)
    public func setBoolSetting(_ key: String, value: Bool) {
        settings.setBool(value, forKey: key)
    }

    @objc(integerSetting:defaultValue:)
    public func integerSetting(_ key: String, defaultValue: Int) -> Int {
        return settings.integer(forKey: key, defaultValue: defaultValue)
    }

    @objc(setIntegerSetting:value:)
    public func setIntegerSetting(_ key: String, value: Int) {
        settings.setInteger(value, forKey: key)
    }

    @objc public func protectedDevices() -> [String] {
        return settings.stringArray(forKey: kSecuritySettingProtectedDevices)
    }

    @objc public func setProtectedDevices(_ devices: [String]) {
        settings.setStringArray(devices, forKey: kSecuritySettingProtectedDevices)
    }

    @objc public func isDeviceProtected(_ deviceName: String?) -> Bool {
        if boolSetting(kSecuritySettingProtectAllBluetooth, defaultValue: true) {
            return true
        }
        guard let deviceName = deviceName, !deviceName.isEmpty else { return false }
        let devices = protectedDevices()
        for d in devices {
            if deviceName.localizedCaseInsensitiveContains(d) || d.localizedCaseInsensitiveContains(deviceName) {
                return true
            }
        }
        return false
    }

    // MARK: - Audit Logs

    @objc public func logEvent(_ event: String, details: String, type: String) {
        auditLog.append(event: event, details: details, type: type)
    }

    public func auditIntegrity() -> AuditLog.Integrity {
        return auditLog.verify()
    }

    @objc public func recentLogs() -> [[String: Any]] {
        return auditLog.recent()
    }

    @objc public func clearLogs() {
        auditLog.clear()
    }
}
