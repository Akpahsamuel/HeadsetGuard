import Testing
import HeadsetGuardKit

@Suite("Smoke Tests")
struct SmokeTests {
    @Test("SecurityManager is reachable")
    func smokeLegacyCoreIsReachable() {
        let manager: SecurityManager? = SecurityManager.shared
        #expect(manager != nil)
    }
}
