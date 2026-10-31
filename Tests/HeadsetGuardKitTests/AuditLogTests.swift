import Foundation
import Testing
@testable import HeadsetGuardKit

@Suite("Audit Log Tests")
struct AuditLogTests {
    @Test("Audit log keeps at most limit entries newest-first")
    func testLogLimitAndOrdering() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("audit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let log = AuditLog(fileURL: fileURL, limit: 100)
        for i in 1...150 {
            log.append(event: "Event \(i)", details: "Details \(i)", type: "test")
        }

        let recent = log.recent()
        #expect(recent.count == 100)
        #expect(recent.first?["event"] == "Event 150")
        #expect(recent.last?["event"] == "Event 51")
    }

    @Test("Corrupt JSON file yields empty recent logs and recovers on append")
    func testCorruptLogRecovery() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("audit_corrupt_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // Write corrupt JSON
        try? "not a valid json {{{".data(using: .utf8)?.write(to: fileURL)

        let log = AuditLog(fileURL: fileURL, limit: 100)
        #expect(log.recent().isEmpty)

        log.append(event: "Recovered", details: "Works after corruption", type: "recovery")
        let recent = log.recent()
        #expect(recent.count == 1)
        #expect(recent.first?["event"] == "Recovered")
    }

    private func signedLog() -> (AuditLog, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audit_signed_\(UUID().uuidString).json")
        return (AuditLog(fileURL: url, hmacKey: Data(repeating: 9, count: 32)), url)
    }

    @Test("Signed log verifies and detects edits, deletions and stripped signatures")
    func testIntegrityChain() throws {
        let (log, url) = signedLog()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(log.verify() == .unsigned)
        for i in 1...4 { log.append(event: "E\(i)", details: "d\(i)", type: "t") }
        #expect(log.verify() == .valid)

        func rewrite(_ mutate: (inout [[String: String]]) -> Void) throws {
            var entries = log.recent()
            mutate(&entries)
            try JSONSerialization.data(withJSONObject: entries).write(to: url)
        }
        let pristine = try Data(contentsOf: url)

        try rewrite { $0[2]["details"] = "edited" }
        #expect(log.verify() != .valid)

        try pristine.write(to: url)
        try rewrite { $0.remove(at: 1) }
        #expect(log.verify() != .valid)

        try pristine.write(to: url)
        try rewrite { $0[0].removeValue(forKey: "hash"); $0[0].removeValue(forKey: "prev") }
        #expect(log.verify() != .valid)
    }

    @Test("A different key cannot forge a valid log")
    func testWrongKeyRejected() {
        let (log, url) = signedLog()
        defer { try? FileManager.default.removeItem(at: url) }
        log.append(event: "A", details: "a", type: "t")
        let attacker = AuditLog(fileURL: url, hmacKey: Data(repeating: 1, count: 32))
        #expect(attacker.verify() != .valid)
    }
}
