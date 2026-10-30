import Foundation
import CoreAudio

@objc public protocol AudioGuardDelegate: AnyObject {
    @objc optional func audioGuardDidDetectBluetoothDeviceConnected(_ deviceID: AudioDeviceID, name: String)
    @objc optional func audioGuardDidDetectBluetoothDeviceDisconnected(_ deviceID: AudioDeviceID, name: String)
    @objc optional func audioGuardDidDetectDefaultOutputChanged(_ deviceID: AudioDeviceID, name: String, isBluetooth: Bool)
    @objc optional func audioGuardDidInterceptVolumeTamper(onDevice deviceID: AudioDeviceID)
}

private let devicesListener: AudioObjectPropertyListenerProc = { _, _, _, clientData in
    guard let clientData = clientData else { return noErr }
    let guardObj = Unmanaged<AudioGuard>.fromOpaque(clientData).takeUnretainedValue()
    DispatchQueue.main.async {
        guardObj.handleDevicesChanged()
    }
    return noErr
}

private let defaultListener: AudioObjectPropertyListenerProc = { _, _, _, clientData in
    guard let clientData = clientData else { return noErr }
    let guardObj = Unmanaged<AudioGuard>.fromOpaque(clientData).takeUnretainedValue()
    DispatchQueue.main.async {
        guardObj.handleDefaultOutputChanged()
    }
    return noErr
}

@objc(AudioGuard)
public final class AudioGuard: NSObject {

    @objc(sharedGuard)
    public static let shared = AudioGuard()

    public static func sharedGuard() -> AudioGuard {
        return shared
    }

    @objc public weak var delegate: AudioGuardDelegate?

    private let hal: AudioHAL
    private let guardQueue = DispatchQueue(label: "com.security.HeadsetGuard.guardQueue")
    private var enforceTimer: DispatchSourceTimer?

    private var _isMonitoring: Bool = false
    private var devicesListenerRegistered: Bool = false
    private var defaultListenerRegistered: Bool = false

    private var _isLocked: Bool = false
    private var _lockedDeviceID: AudioDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var _lockedDeviceName: String?

    private var savedVolume: Float32 = 0.5
    private var savedMute: Bool = false
    private var knownBluetoothDevices: Set<AudioDeviceID> = []

    @objc public var strictMuteEnforcement: Bool = true

    @objc public var isLocked: Bool {
        get { guardQueue.sync { _isLocked } }
        set { guardQueue.sync { _isLocked = newValue } }
    }

    @objc public var lockedDeviceID: AudioDeviceID {
        get { guardQueue.sync { _lockedDeviceID } }
        set { guardQueue.sync { _lockedDeviceID = newValue } }
    }

    @objc public var lockedDeviceName: String? {
        get { guardQueue.sync { _lockedDeviceName } }
        set { guardQueue.sync { _lockedDeviceName = newValue } }
    }

    public init(hal: AudioHAL = CoreAudioHAL()) {
        self.hal = hal
        super.init()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring Lifecycle

    @discardableResult
    @objc public func startMonitoring() -> Bool {
        guard !_isMonitoring else { return true }

        let btDevs = allBluetoothOutputDevices()
        knownBluetoothDevices = Set(btDevs.compactMap { $0["id"] as? AudioDeviceID })

        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let clientData = Unmanaged.passUnretained(self).toOpaque()
        let status1 = AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &devicesAddr, devicesListener, clientData)
        devicesListenerRegistered = (status1 == noErr)

        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status2 = AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, defaultListener, clientData)
        defaultListenerRegistered = (status2 == noErr)

        _isMonitoring = (devicesListenerRegistered && defaultListenerRegistered)
        return _isMonitoring
    }

    @objc public func stopMonitoring() {
        let clientData = Unmanaged.passUnretained(self).toOpaque()
        if devicesListenerRegistered {
            var devicesAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &devicesAddr, devicesListener, clientData)
            devicesListenerRegistered = false
        }

        if defaultListenerRegistered {
            var defaultAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, defaultListener, clientData)
            defaultListenerRegistered = false
        }

        stopEnforceTimer()
        _isMonitoring = false
    }

    // MARK: - Device Queries

    @objc public func allOutputDevices() -> [[String: Any]] {
        return hal.outputDevices().map { dev in
            [
                "id": dev.id,
                "name": dev.name,
                "isBluetooth": dev.isBluetooth
            ]
        }
    }

    @objc public func allBluetoothOutputDevices() -> [[String: Any]] {
        return allOutputDevices().filter { ($0["isBluetooth"] as? Bool) == true }
    }

    @objc public func defaultOutputDeviceID() -> AudioDeviceID {
        return hal.defaultOutputID()
    }

    @objc(setDefaultOutputDevice:)
    public func setDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        return hal.setDefaultOutput(deviceID)
    }

    @objc(deviceNameForID:)
    public func deviceName(forID deviceID: AudioDeviceID) -> String {
        return hal.deviceName(deviceID) ?? ""
    }

    @objc(isBluetoothDevice:)
    public func isBluetoothDevice(_ deviceID: AudioDeviceID) -> Bool {
        return hal.isBluetoothDevice(deviceID)
    }

    @objc(isDeviceMuted:)
    public func isDeviceMuted(_ deviceID: AudioDeviceID) -> Bool {
        return hal.isMuted(deviceID) ?? false
    }

    @objc(setDeviceMute:muted:)
    public func setDeviceMute(_ deviceID: AudioDeviceID, muted: Bool) -> Bool {
        return hal.setMuted(muted, deviceID)
    }

    @objc(deviceVolume:)
    public func deviceVolume(_ deviceID: AudioDeviceID) -> Float32 {
        return hal.volume(deviceID) ?? 0.0
    }

    @objc(setDeviceVolume:volume:)
    public func setDeviceVolume(_ deviceID: AudioDeviceID, volume: Float32) -> Bool {
        return hal.setVolume(volume, deviceID)
    }

    // MARK: - Built-in Audio Fallback

    @objc public func findBuiltInOutputDeviceID() -> AudioDeviceID {
        return hal.outputDevices().first { $0.isBuiltIn }?.id ?? AudioObjectID(kAudioObjectUnknown)
    }

    @discardableResult
    @objc public func routeAudioToBuiltIn() -> Bool {
        let builtIn = findBuiltInOutputDeviceID()
        if builtIn != AudioObjectID(kAudioObjectUnknown) {
            return hal.setDefaultOutput(builtIn)
        }
        return false
    }

    // MARK: - Lock / Unlock Operations

    @discardableResult
    @objc(lockDevice:)
    public func lockDevice(_ deviceID: AudioDeviceID) -> Bool {
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else { return false }

        let name = hal.deviceName(deviceID) ?? "Unknown Device"
        NSLog("[AudioGuard] Locking audio device: '%@' (ID: %u)", name, deviceID)

        guardQueue.sync {
            if !_isLocked {
                let currentVol = hal.volume(deviceID) ?? 0.5
                savedVolume = (currentVol < 0.05) ? 0.5 : currentVol
                savedMute = hal.isMuted(deviceID) ?? false
            }

            _lockedDeviceID = deviceID
            _lockedDeviceName = name
            _isLocked = true
        }

        _ = hal.setMuted(true, deviceID)
        _ = hal.setVolume(0.0, deviceID)

        startEnforceTimer()
        return true
    }

    @discardableResult
    @objc public func lockDefaultIfBluetooth() -> Bool {
        let defID = defaultOutputDeviceID()
        if defID != AudioObjectID(kAudioObjectUnknown) && isBluetoothDevice(defID) {
            return lockDevice(defID)
        }
        return false
    }

    @discardableResult
    @objc(unlockCurrentDevice)
    public func unlockCurrentDevice() -> Bool {
        var devID: AudioDeviceID = AudioObjectID(kAudioObjectUnknown)
        var restoreVol: Float32 = 0.5

        guardQueue.sync {
            if !_isLocked || _lockedDeviceID == AudioObjectID(kAudioObjectUnknown) {
                _isLocked = false
                _lockedDeviceID = AudioObjectID(kAudioObjectUnknown)
                _lockedDeviceName = nil
                return
            }

            devID = _lockedDeviceID
            restoreVol = savedVolume
            let name = _lockedDeviceName ?? "Unknown Device"
            NSLog("[AudioGuard] Unlocking audio device: '%@' (ID: %u)", name, devID)

            _isLocked = false
            _lockedDeviceID = AudioObjectID(kAudioObjectUnknown)
            _lockedDeviceName = nil
        }

        stopEnforceTimer()

        if devID != AudioObjectID(kAudioObjectUnknown) {
            _ = hal.setMuted(false, devID)
            _ = hal.setVolume(restoreVol, devID)
        }

        return true
    }

    // MARK: - Mute Enforcement Timer

    internal func enforceMuteTick() {
        var devID: AudioDeviceID = AudioObjectID(kAudioObjectUnknown)
        guardQueue.sync {
            guard _isLocked, _lockedDeviceID != AudioObjectID(kAudioObjectUnknown) else { return }
            devID = _lockedDeviceID
        }
        guard devID != AudioObjectID(kAudioObjectUnknown) else { return }

        let isMuted = hal.isMuted(devID) ?? true
        let vol = hal.volume(devID) ?? 0.0

        if !isMuted || vol > 0.001 {
            NSLog("[AudioGuard] Tamper detected! Headset tried to unmute (Mute: %d, Vol: %.2f). Re-muting.", isMuted ? 1 : 0, vol)
            _ = hal.setMuted(true, devID)
            _ = hal.setVolume(0.0, devID)

            let d = self.delegate
            if Thread.isMainThread {
                d?.audioGuardDidInterceptVolumeTamper?(onDevice: devID)
            } else {
                DispatchQueue.main.async {
                    d?.audioGuardDidInterceptVolumeTamper?(onDevice: devID)
                }
            }
        }
    }

    private func startEnforceTimer() {
        stopEnforceTimer()

        let timer = DispatchSource.makeTimerSource(queue: guardQueue)
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.enforceMuteTick()
        }
        enforceTimer = timer
        timer.resume()
    }

    private func stopEnforceTimer() {
        if let timer = enforceTimer {
            timer.cancel()
            enforceTimer = nil
        }
    }

    // MARK: - Event Handlers

    internal func handleDevicesChanged() {
        let btDevs = allBluetoothOutputDevices()
        let currentSet = Set(btDevs.compactMap { $0["id"] as? AudioDeviceID })

        let added = currentSet.subtracting(knownBluetoothDevices)
        let removed = knownBluetoothDevices.subtracting(currentSet)
        knownBluetoothDevices = currentSet

        let d = self.delegate

        for devID in added {
            let name = deviceName(forID: devID)
            let resolvedName = name.isEmpty ? "Bluetooth Headset" : name
            NSLog("[AudioGuard] Bluetooth audio device CONNECTED: '%@' (ID: %u)", resolvedName, devID)
            d?.audioGuardDidDetectBluetoothDeviceConnected?(devID, name: resolvedName)
        }

        for devID in removed {
            var wasLocked = false
            guardQueue.sync {
                if devID == _lockedDeviceID {
                    wasLocked = true
                    _isLocked = false
                    _lockedDeviceID = AudioObjectID(kAudioObjectUnknown)
                    _lockedDeviceName = nil
                }
            }
            if wasLocked {
                NSLog("[AudioGuard] Currently locked device disconnected.")
                stopEnforceTimer()
            }
            d?.audioGuardDidDetectBluetoothDeviceDisconnected?(devID, name: "Bluetooth Headset")
        }
    }

    internal func handleDefaultOutputChanged() {
        let defID = defaultOutputDeviceID()
        let name = deviceName(forID: defID)
        let isBT = isBluetoothDevice(defID)

        let resolvedName = name.isEmpty ? "Unknown" : name
        NSLog("[AudioGuard] Default output changed to '%@' (ID: %u, Bluetooth: %@)", resolvedName, defID, isBT ? "YES" : "NO")

        delegate?.audioGuardDidDetectDefaultOutputChanged?(defID, name: resolvedName, isBluetooth: isBT)
    }
}
