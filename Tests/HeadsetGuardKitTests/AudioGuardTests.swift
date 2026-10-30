import Testing
import CoreAudio
@testable import HeadsetGuardKit

final class FakeAudioHAL: AudioHAL {
    var devices: [AudioDeviceInfo] = []
    var currentDefault: UInt32 = 0
    var volumes: [UInt32: Float32] = [:]
    var mutes: [UInt32: Bool] = [:]
    var failReads: Bool = false

    func outputDevices() -> [AudioDeviceInfo] {
        return devices
    }

    func defaultOutputID() -> UInt32 {
        return currentDefault
    }

    func setDefaultOutput(_ id: UInt32) -> Bool {
        currentDefault = id
        return true
    }

    func volume(_ id: UInt32) -> Float32? {
        if failReads { return nil }
        return volumes[id] ?? 0.5
    }

    func setVolume(_ v: Float32, _ id: UInt32) -> Bool {
        volumes[id] = v
        return true
    }

    func isMuted(_ id: UInt32) -> Bool? {
        if failReads { return nil }
        return mutes[id] ?? false
    }

    func setMuted(_ m: Bool, _ id: UInt32) -> Bool {
        mutes[id] = m
        return true
    }
}

final class TestAudioGuardDelegate: AudioGuardDelegate {
    var tamperCount = 0
    var lastTamperedDevice: AudioDeviceID?

    func audioGuardDidInterceptVolumeTamper(onDevice deviceID: AudioDeviceID) {
        tamperCount += 1
        lastTamperedDevice = deviceID
    }
}

@Suite("AudioGuard Tests")
struct AudioGuardTests {
    @Test("lockDevice sets volume 0, mute true, and marks isLocked")
    func testLockDevice() {
        let fake = FakeAudioHAL()
        fake.devices = [
            AudioDeviceInfo(id: 101, name: "AirPods Max", isBluetooth: true, isBuiltIn: false)
        ]
        fake.volumes[101] = 0.8
        fake.mutes[101] = false

        let guardObj = AudioGuard(hal: fake)
        #expect(!guardObj.isLocked)

        let success = guardObj.lockDevice(101)
        #expect(success)
        #expect(guardObj.isLocked)
        #expect(guardObj.lockedDeviceID == 101)
        #expect(fake.volumes[101] == 0.0)
        #expect(fake.mutes[101] == true)

        // unlockCurrentDevice restores volume and unmutes
        let unlockSuccess = guardObj.unlockCurrentDevice()
        #expect(unlockSuccess)
        #expect(!guardObj.isLocked)
        #expect(fake.volumes[101] == 0.8)
        #expect(fake.mutes[101] == false)
    }

    @Test("Tamper check resets volume and fires delegate")
    func testTamperReset() {
        let fake = FakeAudioHAL()
        fake.devices = [
            AudioDeviceInfo(id: 202, name: "Sony WH-1000XM4", isBluetooth: true, isBuiltIn: false)
        ]
        fake.volumes[202] = 0.5
        fake.mutes[202] = false

        let guardObj = AudioGuard(hal: fake)
        let delegate = TestAudioGuardDelegate()
        guardObj.delegate = delegate

        _ = guardObj.lockDevice(202)
        #expect(fake.volumes[202] == 0.0)
        #expect(fake.mutes[202] == true)

        // Simulate external physical volume up on headset
        fake.volumes[202] = 0.7
        fake.mutes[202] = false

        // Run tamper enforcement tick
        guardObj.enforceMuteTick()

        DispatchQueue.main.sync {}

        #expect(fake.volumes[202] == 0.0)
        #expect(fake.mutes[202] == true)
        #expect(guardObj.isLocked)
        #expect(delegate.tamperCount == 1)
        #expect(delegate.lastTamperedDevice == 202)
    }

    @Test("Vanished device with nil HAL read keeps isLocked and does not crash")
    func testVanishedDeviceDoesNotCrash() {
        let fake = FakeAudioHAL()
        fake.devices = [
            AudioDeviceInfo(id: 303, name: "Disappearing Headset", isBluetooth: true, isBuiltIn: false)
        ]
        fake.volumes[303] = 0.6
        fake.mutes[303] = false

        let guardObj = AudioGuard(hal: fake)
        _ = guardObj.lockDevice(303)
        #expect(guardObj.isLocked)

        // Simulate device vanishing mid-enforcement
        fake.failReads = true

        guardObj.enforceMuteTick()
        #expect(guardObj.isLocked)
    }

    @Test("routeAudioToBuiltIn picks built-in device and fails when none exists")
    func testRouteAudioToBuiltIn() {
        let fake = FakeAudioHAL()
        fake.devices = [
            AudioDeviceInfo(id: 401, name: "Bluetooth Buds", isBluetooth: true, isBuiltIn: false),
            AudioDeviceInfo(id: 402, name: "MacBook Pro Speakers", isBluetooth: false, isBuiltIn: true)
        ]
        fake.currentDefault = 401

        let guardObj = AudioGuard(hal: fake)
        let routed = guardObj.routeAudioToBuiltIn()
        #expect(routed)
        #expect(fake.currentDefault == 402)

        // Test failure when no built-in device exists
        fake.devices = [
            AudioDeviceInfo(id: 401, name: "Bluetooth Buds", isBluetooth: true, isBuiltIn: false)
        ]
        let routedNone = guardObj.routeAudioToBuiltIn()
        #expect(!routedNone)
    }

    @Test("allBluetoothOutputDevices excludes non-Bluetooth devices")
    func testAllBluetoothOutputDevices() {
        let fake = FakeAudioHAL()
        fake.devices = [
            AudioDeviceInfo(id: 1, name: "Internal Speakers", isBluetooth: false, isBuiltIn: true),
            AudioDeviceInfo(id: 2, name: "AirPods", isBluetooth: true, isBuiltIn: false),
            AudioDeviceInfo(id: 3, name: "USB DAC", isBluetooth: false, isBuiltIn: false)
        ]

        let guardObj = AudioGuard(hal: fake)
        let btDevs = guardObj.allBluetoothOutputDevices()
        #expect(btDevs.count == 1)
        let firstID = btDevs.first?["id"] as? UInt32
        #expect(firstID == 2)
        let firstName = btDevs.first?["name"] as? String
        #expect(firstName == "AirPods")
    }
}
