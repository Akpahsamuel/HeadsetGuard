import Testing
@testable import HeadsetGuardKit

final class FakeAudioController: AudioControlling {
    var isLocked: Bool = false
    var lockCount: Int = 0
    var unlockCount: Int = 0
    var routeBuiltInCount: Int = 0

    func lockDevice(_ id: UInt32) -> Bool {
        lockCount += 1
        isLocked = true
        return true
    }

    func unlockCurrentDevice() -> Bool {
        unlockCount += 1
        isLocked = false
        return true
    }

    func routeAudioToBuiltIn() -> Bool {
        routeBuiltInCount += 1
        return true
    }
}

final class FakeAuthenticator: Authenticating {
    var promptCount: Int = 0
    var lastDeviceName: String?
    var pendingCompletion: ((Bool) -> Void)?

    func requestUnlock(deviceName: String, completion: @escaping (Bool) -> Void) {
        promptCount += 1
        lastDeviceName = deviceName
        pendingCompletion = completion
    }

    func dismiss() {
        if let completion = pendingCompletion {
            pendingCompletion = nil
            completion(false)
        }
    }
}

final class FakeLinkDropper: LinkDropping {
    var disconnectCount: Int = 0
    var lastDisconnectedName: String?

    func disconnect(deviceNamed: String) -> Bool {
        disconnectCount += 1
        lastDisconnectedName = deviceNamed
        return true
    }
}

@Suite("Lock Coordinator Tests")
struct LockCoordinatorTests {
    @Test("deviceConnected locks and presents exactly one prompt")
    func testDeviceConnectedLocksAndPromptsOnce() {
        let audio = FakeAudioController()
        let auth = FakeAuthenticator()
        let link = FakeLinkDropper()
        let coordinator = LockCoordinator(audio: audio, auth: auth, link: link)

        coordinator.deviceConnected(id: 42, name: "AirPods Pro")

        #expect(audio.lockCount == 1)
        #expect(audio.isLocked == true)
        #expect(auth.promptCount == 1)
        #expect(coordinator.isPromptActive == true)
    }

    @Test("systemWoke and defaultOutputChanged while prompt active present no second prompt")
    func testNoDuplicatePromptsOnWakeOrOutputChange() {
        let audio = FakeAudioController()
        let auth = FakeAuthenticator()
        let link = FakeLinkDropper()
        let coordinator = LockCoordinator(audio: audio, auth: auth, link: link)

        coordinator.deviceConnected(id: 42, name: "AirPods Pro")
        #expect(auth.promptCount == 1)

        coordinator.systemWoke()
        #expect(auth.promptCount == 1)

        coordinator.defaultOutputChanged(id: 42, name: "AirPods Pro", isBluetooth: true)
        #expect(auth.promptCount == 1)
    }

    @Test("Successful auth calls unlockCurrentDevice once; failed auth leaves it locked")
    func testAuthSuccessAndFailure() {
        let audio = FakeAudioController()
        let auth = FakeAuthenticator()
        let link = FakeLinkDropper()
        let coordinator = LockCoordinator(audio: audio, auth: auth, link: link)

        // Test failure first
        coordinator.deviceConnected(id: 42, name: "AirPods Pro")
        auth.pendingCompletion?(false)

        #expect(audio.unlockCount == 0)
        #expect(audio.isLocked == true)
        #expect(coordinator.isPromptActive == false)

        // Test success
        coordinator.deviceConnected(id: 42, name: "AirPods Pro")
        auth.pendingCompletion?(true)

        #expect(audio.unlockCount == 1)
        #expect(audio.isLocked == false)
        #expect(coordinator.isPromptActive == false)
    }

    @Test("deviceDisconnected while prompting dismisses and resolves completion once")
    func testDeviceDisconnectedWhilePrompting() {
        let audio = FakeAudioController()
        let auth = FakeAuthenticator()
        let link = FakeLinkDropper()
        let coordinator = LockCoordinator(audio: audio, auth: auth, link: link)

        var completionCalls = 0
        coordinator.deviceConnected(id: 42, name: "AirPods Pro")

        let originalCompletion = auth.pendingCompletion
        auth.pendingCompletion = { unlocked in
            completionCalls += 1
            originalCompletion?(unlocked)
        }

        coordinator.deviceDisconnected(id: 42, name: "AirPods Pro")

        #expect(coordinator.isPromptActive == false)
        #expect(completionCalls == 1)
    }

    @Test("Already locked device is not locked twice")
    func testAlreadyLockedDeviceNotLockedTwice() {
        let audio = FakeAudioController()
        let auth = FakeAuthenticator()
        let link = FakeLinkDropper()
        let coordinator = LockCoordinator(audio: audio, auth: auth, link: link)

        coordinator.deviceConnected(id: 42, name: "AirPods Pro")
        #expect(audio.lockCount == 1)

        // Second connection notification for the same already-locked device
        coordinator.deviceConnected(id: 42, name: "AirPods Pro")
        #expect(audio.lockCount == 1)
    }
}
