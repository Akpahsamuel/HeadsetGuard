import Foundation
import Security
import Testing
@testable import HeadsetGuardKit

@Suite("Credential Store Tests")
struct CredentialStoreTests {
    @Test("InMemoryCredentialStore round-trips")
    func testInMemoryRoundTrip() throws {
        let store = InMemoryCredentialStore()
        #expect(try store.load() == nil)

        let salt = Data(repeating: 0x42, count: 32)
        let success = store.save(hash: "testHash", salt: salt)
        #expect(success)

        let loaded = try store.load()
        #expect(loaded?.hash == "testHash")
        #expect(loaded?.salt == salt)

        store.clear()
        #expect(try store.load() == nil)
    }

    @Test("Keychain read error fails closed in SecurityManager")
    func testKeychainErrorFailsClosed() {
        let store = InMemoryCredentialStore()
        store.shouldThrowError = .keychainError(errSecAuthFailed)

        let settings = InMemorySettingsStore()
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("audit_err_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let log = AuditLog(fileURL: fileURL)

        let sm = SecurityManager(store: store, settings: settings, log: log)
        // Must fail closed: treat as configured so attacker cannot trigger first-time setup
        #expect(sm.isPasswordConfigured == true)
        // Must reject any verification
        #expect(sm.verifyPassword("anyPassword") == false)
        #expect(sm.failedAttemptsCount == 1)
    }

    @Test("KeychainCredentialStore JSON decode round-trips and malformed blob returns nil")
    func testKeychainJSONSerialization() {
        let salt = Data(0..<32)
        let hash = "sampleHashString"

        guard let serialized = KeychainCredentialStore.serialize(hash: hash, salt: salt) else {
            Issue.record("Serialization failed")
            return
        }

        let parsed = KeychainCredentialStore.parse(data: serialized)
        #expect(parsed?.hash == hash)
        #expect(parsed?.salt == salt)

        // Corrupt / malformed tests
        let corruptData = "not valid json".data(using: .utf8)!
        #expect(KeychainCredentialStore.parse(data: corruptData) == nil)

        let missingSalt = "{\"hash\":\"abc\"}".data(using: .utf8)!
        #expect(KeychainCredentialStore.parse(data: missingSalt) == nil)

        let invalidBase64Salt = "{\"hash\":\"abc\",\"salt\":\"!!invalid-base64!!\"}".data(using: .utf8)!
        #expect(KeychainCredentialStore.parse(data: invalidBase64Salt) == nil)
    }
}

@Suite("Secure Settings Store Tests")
struct SecureSettingsStoreTests {
    @Test("Values round-trip through the blob backend and survive a reload")
    func testPersistence() {
        let backend = InMemoryBlobBackend()
        let store = SecureSettingsStore(backend: backend)
        store.setBool(false, forKey: "AutoLockOnConnect")
        store.setInteger(5, forKey: "MaxFailedAttempts")
        store.setStringArray(["Buds"], forKey: "ProtectedDevices")

        let reloaded = SecureSettingsStore(backend: backend)
        #expect(reloaded.bool(forKey: "AutoLockOnConnect", defaultValue: true) == false)
        #expect(reloaded.integer(forKey: "MaxFailedAttempts", defaultValue: 3) == 5)
        #expect(reloaded.stringArray(forKey: "ProtectedDevices") == ["Buds"])
    }

    @Test("Legacy UserDefaults values import once and are removed from defaults")
    func testLegacyImport() {
        let suite = "SecureSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "LockOnSleep")

        let backend = InMemoryBlobBackend()
        let store = SecureSettingsStore(backend: backend, legacyDefaults: defaults)
        #expect(store.bool(forKey: "LockOnSleep", defaultValue: true) == false)
        #expect(defaults.object(forKey: "LockOnSleep") == nil)

        // Later edits to defaults are ignored: the blob already exists.
        defaults.set(true, forKey: "LockOnSleep")
        let again = SecureSettingsStore(backend: backend, legacyDefaults: defaults)
        #expect(again.bool(forKey: "LockOnSleep", defaultValue: true) == false)
    }

    @Test("Read failure falls back to defaults and never overwrites the stored blob")
    func testFailClosedOnReadError() {
        let backend = InMemoryBlobBackend()
        SecureSettingsStore(backend: backend).setBool(false, forKey: "AutoLockOnConnect")
        let original = backend.blob

        backend.shouldThrowError = .keychainError(errSecAuthFailed)
        let failing = SecureSettingsStore(backend: backend)
        #expect(failing.bool(forKey: "AutoLockOnConnect", defaultValue: true) == true)
        failing.setBool(false, forKey: "LockOnSleep")
        #expect(backend.blob == original)
    }

    @Test("Corrupt blob yields secure defaults")
    func testCorruptBlob() {
        let store = SecureSettingsStore(backend: InMemoryBlobBackend(blob: Data("garbage".utf8)))
        #expect(store.bool(forKey: "ProtectAllBluetooth", defaultValue: true) == true)
    }

    @Test("Two stores over one backend see each other's writes (app and CLI processes)")
    func testNoStaleCache() {
        let backend = InMemoryBlobBackend()
        let app = SecureSettingsStore(backend: backend)
        let cli = SecureSettingsStore(backend: backend)
        cli.setInteger(2, forKey: "FailedAttemptsCount")
        #expect(app.integer(forKey: "FailedAttemptsCount", defaultValue: 0) == 2)
        app.setBool(true, forKey: "CredentialConfigured")
        cli.setInteger(3, forKey: "FailedAttemptsCount")
        #expect(app.bool(forKey: "CredentialConfigured", defaultValue: false))
    }
}
