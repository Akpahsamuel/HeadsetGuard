import Foundation
import CoreAudio

public struct AudioDeviceInfo: Equatable {
    public let id: UInt32
    public let name: String
    public let isBluetooth: Bool
    public let isBuiltIn: Bool

    public init(id: UInt32, name: String, isBluetooth: Bool, isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.isBluetooth = isBluetooth
        self.isBuiltIn = isBuiltIn
    }
}

public protocol AudioHAL: AnyObject {
    func outputDevices() -> [AudioDeviceInfo]
    func defaultOutputID() -> UInt32
    func setDefaultOutput(_ id: UInt32) -> Bool
    func volume(_ id: UInt32) -> Float32?
    func setVolume(_ v: Float32, _ id: UInt32) -> Bool
    func isMuted(_ id: UInt32) -> Bool?
    func setMuted(_ m: Bool, _ id: UInt32) -> Bool
    func deviceName(_ id: UInt32) -> String?
    func isBluetoothDevice(_ id: UInt32) -> Bool
}

public extension AudioHAL {
    func deviceName(_ id: UInt32) -> String? {
        return outputDevices().first { $0.id == id }?.name
    }

    func isBluetoothDevice(_ id: UInt32) -> Bool {
        return outputDevices().first { $0.id == id }?.isBluetooth ?? false
    }
}

public final class CoreAudioHAL: AudioHAL {
    public init() {}

    public func outputDevices() -> [AudioDeviceInfo] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        guard status == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        let deviceIDs = Array<AudioDeviceID>(unsafeUninitializedCapacity: count) { buffer, initializedCount in
            var readSize = size
            let readStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &readSize, buffer.baseAddress!)
            if readStatus == noErr {
                initializedCount = count
            } else {
                initializedCount = 0
            }
        }

        var results: [AudioDeviceInfo] = []
        for devID in deviceIDs {
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(devID, &streamAddr, 0, nil, &streamSize)
            guard streamSize > 0 else { continue }

            let name = deviceName(devID) ?? "Unknown Device"
            let isBT = isBluetoothDevice(devID)
            let isBuiltIn = isBuiltInDevice(devID)

            results.append(AudioDeviceInfo(id: devID, name: name, isBluetooth: isBT, isBuiltIn: isBuiltIn))
        }
        return results
    }

    public func defaultOutputID() -> UInt32 {
        var devID: AudioDeviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID)
        return (status == noErr) ? devID : AudioObjectID(kAudioObjectUnknown)
    }

    public func setDefaultOutput(_ id: UInt32) -> Bool {
        var devID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &devID)
        return (status == noErr)
    }

    public func volume(_ id: UInt32) -> Float32? {
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &vol) == noErr {
            return vol
        }
        addr.mElement = 1
        if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &vol) == noErr {
            return vol
        }
        return nil
    }

    public func setVolume(_ v: Float32, _ id: UInt32) -> Bool {
        var vol = v
        let size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &vol)
        if status == noErr { return true }
        addr.mElement = 1
        _ = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &vol)
        addr.mElement = 2
        _ = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &vol)
        return status == noErr
    }

    public func isMuted(_ id: UInt32) -> Bool? {
        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &mute) == noErr {
            return mute != 0
        }
        addr.mElement = 1
        if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &mute) == noErr {
            return mute != 0
        }
        return nil
    }

    public func setMuted(_ m: Bool, _ id: UInt32) -> Bool {
        var muteVal: UInt32 = m ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &muteVal)
        if status != noErr {
            addr.mElement = 1
            _ = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &muteVal)
            addr.mElement = 2
            _ = AudioObjectSetPropertyData(id, &addr, 0, nil, size, &muteVal)
        }
        return status == noErr
    }

    public func deviceName(_ id: UInt32) -> String? {
        var nameRef: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &nameRef)
        if status == noErr, let name = nameRef?.takeRetainedValue() as String? {
            return name
        }
        return nil
    }

    public func isBluetoothDevice(_ id: UInt32) -> Bool {
        var transport: UInt32 = 0
        var transSize = UInt32(MemoryLayout<UInt32>.size)
        var transAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(id, &transAddr, 0, nil, &transSize, &transport)
        if status == noErr {
            if transport == kAudioDeviceTransportTypeBluetooth ||
               transport == kAudioDeviceTransportTypeBluetoothLE ||
               transport == 0x626c7565 || // 'blue'
               transport == 0x626c6561 {  // 'blea'
                return true
            }
        }

        // Secondary check: UID containing "Bluetooth" or "bt_"
        var uidRef: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(id, &uidAddr, 0, nil, &uidSize, &uidRef) == noErr,
           let uidStr = uidRef?.takeRetainedValue() as String? {
            let lower = uidStr.lowercased()
            if lower.contains("bluetooth") || lower.contains("bt_") {
                return true
            }
        }
        return false
    }

    public func isBuiltInDevice(_ id: UInt32) -> Bool {
        var transport: UInt32 = 0
        var transSize = UInt32(MemoryLayout<UInt32>.size)
        var transAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(id, &transAddr, 0, nil, &transSize, &transport)
        if status == noErr {
            if transport == kAudioDeviceTransportTypeBuiltIn || transport == 0x626c746e { // 'bltn'
                return true
            }
        }
        return false
    }
}
