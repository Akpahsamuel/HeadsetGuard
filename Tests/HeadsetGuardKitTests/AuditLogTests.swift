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
}
