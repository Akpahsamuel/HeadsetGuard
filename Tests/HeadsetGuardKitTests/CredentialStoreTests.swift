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
