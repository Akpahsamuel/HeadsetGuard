import Foundation
import IOBluetooth

@objc public protocol BluetoothManagerDelegate: AnyObject {
    @objc optional func bluetoothManagerDidDetectDeviceConnected(_ device: IOBluetoothDevice)
}

@objc(BluetoothManager)
public final class BluetoothManager: NSObject {

    public static let shared = BluetoothManager()

    @objc public weak var delegate: BluetoothManagerDelegate?

    private var connectNotification: IOBluetoothUserNotification?

    public override init() {
        super.init()
    }

    @objc public func startMonitoring() {
        if connectNotification != nil { return }

        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnectedNotification(_:device:)))
        NSLog("[BluetoothManager] Started listening for Bluetooth connect notifications.")
    }

    @objc public func stopMonitoring() {
        if let note = connectNotification {
            note.unregister()
            connectNotification = nil
        }
    }

    @objc private func deviceConnectedNotification(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        NSLog("[BluetoothManager] IOBluetooth notification: connected to '%@' (%@)", device.nameOrAddress ?? "", device.addressString ?? "")
        guard isAudioDevice(device) else { return }

        guard let d = delegate else { return }
        DispatchQueue.main.async {
            d.bluetoothManagerDidDetectDeviceConnected?(device)
        }
    }

    // MARK: - Audio Device Identification

    public static func isAudioDevice(majorClass: UInt, minorClass: UInt) -> Bool {
        return majorClass == 0x04
    }

    public static func isAudioDevice(name: String) -> Bool {
        let lower = name.lowercased()
        let keywords = [
            "headset", "headphone", "earphone", "earbud", "airpod",
            "buds", "tws", "sound", "speaker", "wh-", "wf-", "bose", "sony", "audiomaster"
        ]
        return keywords.contains { lower.contains($0) }
    }

    @objc(isAudioDevice:)
    public func isAudioDevice(_ device: IOBluetoothDevice) -> Bool {
        let cod = UInt(device.classOfDevice)
        let majorClass = (cod & 0x1F00) >> 8
        let minorClass = (cod & 0xFC) >> 2
        if Self.isAudioDevice(majorClass: majorClass, minorClass: minorClass) {
            return true
        }

        if let name = device.nameOrAddress {
            return Self.isAudioDevice(name: name)
        }

        return false
    }

    // MARK: - Querying Devices

    @objc public func pairedAudioDevices() -> [IOBluetoothDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        return paired.filter { isAudioDevice($0) }
    }

    @objc public func connectedAudioDevices() -> [IOBluetoothDevice] {
        return pairedAudioDevices().filter { $0.isConnected() }
    }

    @objc(deviceNamed:)
    public func device(named name: String) -> IOBluetoothDevice? {
        guard !name.isEmpty else { return nil }
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }
        for dev in paired {
            guard let devName = dev.nameOrAddress else { continue }
            if devName.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains(devName) {
                return dev
            }
        }
        return nil
    }

    @objc(deviceWithAddress:)
    public func device(withAddress address: String) -> IOBluetoothDevice? {
        guard !address.isEmpty else { return nil }
        return IOBluetoothDevice(addressString: address)
    }

    // MARK: - Disconnection

    @discardableResult
    @objc(disconnectDeviceNamed:)
    public func disconnectDevice(named name: String) -> Bool {
        guard let dev = device(named: name) else { return false }
        return disconnect(dev)
    }

    @discardableResult
    @objc(disconnectDevice:)
    public func disconnect(_ device: IOBluetoothDevice) -> Bool {
        NSLog("[BluetoothManager] Forcing disconnect for device: %@", device.nameOrAddress ?? "")
        let ret = device.closeConnection()
        return (ret == kIOReturnSuccess)
    }
}
