import Foundation
import Testing
@testable import HeadsetGuardKit

@Suite("Security Manager Tests")
struct SecurityManagerTests {
    @Test("Legacy credentials in defaults migrate to store and are deleted from defaults")
    func testLegacyCredentialMigration() throws {
        let store = InMemoryCredentialStore()
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let log = AuditLog(fileURL: fileURL)

        // Seed legacy credentials
        let testSalt = Data(0..<32)
        let testHash = "legacyHashedPassword"
        let seededSettings = InMemorySettingsStore(initial: [
            "MasterPasswordHash": testHash,
            "MasterPasswordSalt": testSalt,
            kSecuritySettingMaxFailedAttempts: 3
        ])

        let manager = SecurityManager(store: store, settings: seededSettings, log: log)
        #expect(manager.isPasswordConfigured)
        #expect(try store.load()?.hash == testHash)
        #expect(try store.load()?.salt == testSalt)

        // Defaults should have them removed
        #expect(seededSettings.string(forKey: "MasterPasswordHash") == nil)
        #expect(seededSettings.data(forKey: "MasterPasswordSalt") == nil)
    }

    @Test("Legacy defaults never overwrite an existing stored credential")
    func testLegacyMigrationDoesNotOverwriteExisting() throws {
        let realSalt = Data(repeating: 7, count: 32)
        let store = InMemoryCredentialStore(stored: ("realHash", realSalt))
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let planted = InMemorySettingsStore(initial: [
            "MasterPasswordHash": "attackerHash",
            "MasterPasswordSalt": Data(0..<32)
        ])

        _ = SecurityManager(store: store, settings: planted, log: AuditLog(fileURL: fileURL))

        #expect(try store.load()?.hash == "realHash")
        #expect(try store.load()?.salt == realSalt)
        #expect(planted.string(forKey: "MasterPasswordHash") == nil)
    }

    @Test("Password verification updates failedAttemptsCount properly")
    func testFailedAttemptsCount() throws {
        let store = InMemoryCredentialStore()
        let settings = InMemorySettingsStore()
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let log = AuditLog(fileURL: fileURL)

        let manager = SecurityManager(store: store, settings: settings, log: log)
        #expect(!manager.isPasswordConfigured)

        try manager.setupMasterPassword("superSecret123")
        #expect(manager.isPasswordConfigured)
        #expect(manager.failedAttemptsCount == 0)

        #expect(!manager.verifyPassword("wrong1"))
        #expect(manager.failedAttemptsCount == 1)

        #expect(!manager.verifyPassword("wrong2"))
        #expect(manager.failedAttemptsCount == 2)

        #expect(manager.verifyPassword("superSecret123"))
        #expect(manager.failedAttemptsCount == 0)
    }

    @Test("Setup password rejects passwords shorter than the minimum length")
    func testPasswordLengthValidation() {
        let store = InMemoryCredentialStore()
        let settings = InMemorySettingsStore()
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let log = AuditLog(fileURL: fileURL)

        let manager = SecurityManager(store: store, settings: settings, log: log)
        #expect(throws: NSError.self) {
            try manager.setupMasterPassword("12345")
        }
    }

    @Test("Change password requires valid current password")
    func testChangePasswordValidation() throws {
        let store = InMemoryCredentialStore()
        let settings = InMemorySettingsStore()
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let log = AuditLog(fileURL: fileURL)

        let manager = SecurityManager(store: store, settings: settings, log: log)
        try manager.setupMasterPassword("oldPass")

        #expect(throws: NSError.self) {
            try manager.changePassword(from: "wrongOldPass", to: "newPass")
        }

        try manager.changePassword(from: "oldPass", to: "newPass")
        #expect(manager.verifyPassword("newPass"))
        #expect(!manager.verifyPassword("oldPass"))
    }

    @Test("Reaching the attempt limit starts a cooldown that blocks even the right password")
    func testCooldownAfterMaxFailures() throws {
        let store = InMemoryCredentialStore()
        let settings = InMemorySettingsStore(initial: [kSecuritySettingMaxFailedAttempts: 3])
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let manager = SecurityManager(store: store, settings: settings, log: AuditLog(fileURL: fileURL))
        try manager.setupMasterPassword("correct-pin")

        for _ in 0..<3 { #expect(!manager.verifyPassword("wrong-pin")) }
        #expect(manager.lockoutRemaining() > 0)
        #expect(!manager.verifyPassword("correct-pin"))

        // A fresh manager over the same settings (e.g. app relaunch) is still locked out.
        let relaunched = SecurityManager(store: store, settings: settings, log: AuditLog(fileURL: fileURL))
        #expect(relaunched.lockoutRemaining() > 0)
        #expect(!relaunched.verifyPassword("correct-pin"))
    }

    @Test("Tampered attempt limit is clamped")
    func testAttemptLimitClamped() {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let huge = SecurityManager(store: InMemoryCredentialStore(),
                                   settings: InMemorySettingsStore(initial: [kSecuritySettingMaxFailedAttempts: 1_000_000]),
                                   log: AuditLog(fileURL: fileURL))
        #expect(huge.maxFailedAttempts == 10)
        let zero = SecurityManager(store: InMemoryCredentialStore(),
                                   settings: InMemorySettingsStore(initial: [kSecuritySettingMaxFailedAttempts: 0]),
                                   log: AuditLog(fileURL: fileURL))
        #expect(zero.maxFailedAttempts == 1)
    }

    @Test("A configured install whose credential disappears stays configured and ignores planted legacy values")
    func testMissingCredentialFailsClosed() throws {
        let store = InMemoryCredentialStore()
        let settings = InMemorySettingsStore()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let manager = SecurityManager(store: store, settings: settings, log: AuditLog(fileURL: fileURL))
        try manager.setupMasterPassword("correct-pin")

        store.clear()
        #expect(manager.isPasswordConfigured)
        #expect(!manager.verifyPassword("anything-at-all"))

        let legacy = InMemorySettingsStore(initial: ["MasterPasswordHash": "x", "MasterPasswordSalt": Data(0..<32)])
        let relaunched = SecurityManager(store: store, settings: settings, log: AuditLog(fileURL: fileURL), legacy: legacy)
        #expect(try store.load() == nil)
        #expect(relaunched.isPasswordConfigured)
    }

    @Test("Existing installs get the configured marker on launch")
    func testMarkerBackfill() throws {
        let store = InMemoryCredentialStore(stored: ("h", Data(repeating: 1, count: 32)))
        let settings = InMemorySettingsStore()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        _ = SecurityManager(store: store, settings: settings, log: AuditLog(fileURL: fileURL))
        store.clear()
        #expect(settings.bool(forKey: "CredentialConfigured", defaultValue: false))
    }

    @Test("A planted far-future lockout is capped at the policy maximum")
    func testLockoutCap() {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let far = Int(Date().timeIntervalSince1970) + 10_000_000
        let manager = SecurityManager(store: InMemoryCredentialStore(),
                                      settings: InMemorySettingsStore(initial: ["LockoutUntilEpoch": far]),
                                      log: AuditLog(fileURL: fileURL))
        #expect(manager.lockoutRemaining() <= 3600)
    }

    @Test("Biometric auth is refused when the setting is off")
    func testBiometricsSettingEnforced() async {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let manager = SecurityManager(store: InMemoryCredentialStore(),
                                      settings: InMemorySettingsStore(initial: [kSecuritySettingBiometricsEnabled: false]),
                                      log: AuditLog(fileURL: fileURL))
        let result = await withCheckedContinuation { cont in
            manager.authenticateWithBiometrics(reason: "test") { ok, _ in cont.resume(returning: ok) }
        }
        #expect(result == false)
    }
}
