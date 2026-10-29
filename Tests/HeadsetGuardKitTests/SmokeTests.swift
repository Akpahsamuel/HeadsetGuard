import Testing
import LegacyCore

@Suite("Smoke Tests")
struct SmokeTests {
    @Test("LegacyCore is reachable")
    func smokeLegacyCoreIsReachable() {
        let manager: SecurityManager? = SecurityManager.shared()
        #expect(manager != nil)
    }
}
