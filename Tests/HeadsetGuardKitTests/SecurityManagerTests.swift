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

    @Test("Setup password rejects passwords shorter than 4 characters")
    func testPasswordLengthValidation() {
        let store = InMemoryCredentialStore()
        let settings = InMemorySettingsStore()
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let log = AuditLog(fileURL: fileURL)

        let manager = SecurityManager(store: store, settings: settings, log: log)
        #expect(throws: NSError.self) {
            try manager.setupMasterPassword("123")
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
}
