import Testing
@testable import HeadsetGuardKit

@Suite("Command Parsing Tests")
struct CommandTests {
    @Test("Empty arguments parse as app")
    func testEmptyArgs() {
        #expect(Command.parse([]) == .app)
    }

    @Test("Status flag parses as status")
    func testStatusFlag() {
        #expect(Command.parse(["--status"]) == .status)
    }

    @Test("Help flags parse as help")
    func testHelpFlags() {
        #expect(Command.parse(["--help"]) == .help)
        #expect(Command.parse(["-h"]) == .help)
    }

    @Test("List flag parses as list")
    func testListFlag() {
        #expect(Command.parse(["--list"]) == .list)
    }

    @Test("Lock flag parses as lock")
    func testLockFlag() {
        #expect(Command.parse(["--lock"]) == .lock)
    }

    @Test("Unlock flag parses as unlock")
    func testUnlockFlag() {
        #expect(Command.parse(["--unlock"]) == .unlock)
    }

    @Test("Disconnect flag parses as disconnect")
    func testDisconnectFlag() {
        #expect(Command.parse(["--disconnect"]) == .disconnect)
    }

    @Test("Set password flag parses as setPassword")
    func testSetPasswordFlag() {
        #expect(Command.parse(["--set-password"]) == .setPassword)
    }

    @Test("Logs flag parses as logs")
    func testLogsFlag() {
        #expect(Command.parse(["--logs"]) == .logs)
    }

    @Test("Unknown flag parses as unknown")
    func testUnknownFlag() {
        #expect(Command.parse(["--bogus"]) == .unknown("--bogus"))
    }
}
