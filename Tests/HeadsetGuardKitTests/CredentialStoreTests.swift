import Testing
@testable import HeadsetGuardKit

@Suite("Credential Store Tests")
struct CredentialStoreTests {
    @Test("InMemoryCredentialStore round-trips")
    func testInMemoryRoundTrip() {
        let store = InMemoryCredentialStore()
        #expect(store.load() == nil)

        let salt = Data(repeating: 0x42, count: 32)
        let success = store.save(hash: "testHash", salt: salt)
        #expect(success)

        let loaded = store.load()
        #expect(loaded?.hash == "testHash")
        #expect(loaded?.salt == salt)

        store.clear()
        #expect(store.load() == nil)
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
