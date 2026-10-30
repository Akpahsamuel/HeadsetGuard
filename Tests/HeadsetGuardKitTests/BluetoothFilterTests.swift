import Testing
@testable import HeadsetGuardKit

@Suite("Bluetooth Filter Tests")
struct BluetoothFilterTests {
    @Test("Audio/Video major class with audio minor classes returns true")
    func testAudioMajorClassReturnsTrue() {
        // Major class 0x04 is Audio/Video
        // Minor classes: headset (0x01), handsfree (0x02), loudspeaker (0x05), headphones (0x06)
        #expect(BluetoothManager.isAudioDevice(majorClass: 0x04, minorClass: 0x01))
        #expect(BluetoothManager.isAudioDevice(majorClass: 0x04, minorClass: 0x02))
        #expect(BluetoothManager.isAudioDevice(majorClass: 0x04, minorClass: 0x05))
        #expect(BluetoothManager.isAudioDevice(majorClass: 0x04, minorClass: 0x06))
    }

    @Test("Non-audio major classes return false")
    func testNonAudioMajorClassesReturnFalse() {
        // Major class 0x05 (Peripheral / Keyboard / Mouse)
        #expect(!BluetoothManager.isAudioDevice(majorClass: 0x05, minorClass: 0x02))
        // Major class 0x02 (Phone / Cellular)
        #expect(!BluetoothManager.isAudioDevice(majorClass: 0x02, minorClass: 0x01))
        // Major class 0x01 (Computer)
        #expect(!BluetoothManager.isAudioDevice(majorClass: 0x01, minorClass: 0x01))
    }

    @Test("Audio device name heuristics match audio keywords")
    func testAudioNameHeuristics() {
        #expect(BluetoothManager.isAudioDevice(name: "Eugene's AirPods Pro"))
        #expect(BluetoothManager.isAudioDevice(name: "Sony WH-1000XM4"))
        #expect(BluetoothManager.isAudioDevice(name: "Bose QuietComfort 35"))
        #expect(BluetoothManager.isAudioDevice(name: "Galaxy Buds2"))
        #expect(BluetoothManager.isAudioDevice(name: "Wireless Headset"))

        #expect(!BluetoothManager.isAudioDevice(name: "Magic Keyboard"))
        #expect(!BluetoothManager.isAudioDevice(name: "MX Master 3S"))
        #expect(!BluetoothManager.isAudioDevice(name: "iPhone 15"))
    }
}
