import Testing
import HeadsetGuardKit

@Suite("Smoke Tests")
struct SmokeTests {
    @Test("SecurityManager is reachable")
    func smokeKitIsReachable() {
        let manager: SecurityManager? = SecurityManager.shared
        #expect(manager != nil)
    }
}
