import Foundation

public protocol AudioControlling: AnyObject {
    var isLocked: Bool { get }
    func lockDevice(_ id: UInt32) -> Bool
    func unlockCurrentDevice() -> Bool
    func routeAudioToBuiltIn() -> Bool
}

public protocol Authenticating: AnyObject {
    func requestUnlock(deviceName: String, completion: @escaping (Bool) -> Void)
    func dismiss()
}

public extension Authenticating {
    func dismiss() {}
}

public protocol LinkDropping: AnyObject {
    func disconnect(deviceNamed: String) -> Bool
}

// Protocol conformances
extension AudioGuard: AudioControlling {}

extension BluetoothManager: LinkDropping {
    public func disconnect(deviceNamed: String) -> Bool {
        return self.disconnectDevice(named: deviceNamed)
    }
}

public final class UnlockWindowAdapter: Authenticating {
    public init() {}

    public func requestUnlock(deviceName: String, completion: @escaping (Bool) -> Void) {
        UnlockWindowController.shared.present(for: deviceName, completion: completion)
    }

    public func dismiss() {
        UnlockWindowController.shared.dismissWindow()
    }
}

public final class LockCoordinator {
    public let audio: AudioControlling
    public let auth: Authenticating
    public let link: LinkDropping

    public private(set) var isPromptActive: Bool = false
    public private(set) var activeDeviceID: UInt32 = 0
    public private(set) var activeDeviceName: String = ""

    private var activeCompletion: ((Bool) -> Void)?

    /// Called once whenever a prompt resolves (unlock, rejection, or disconnect), after the
    /// coordinator has updated its own state. Lets the app react without touching the
    /// window controller's completion, which the coordinator owns.
    public var onPromptResolved: ((Bool) -> Void)?

    public init(audio: AudioControlling, auth: Authenticating, link: LinkDropping) {
        self.audio = audio
        self.auth = auth
        self.link = link
    }

    public func deviceConnected(id: UInt32, name: String) {
        activeDeviceID = id
        activeDeviceName = name

        if !audio.isLocked {
            _ = audio.lockDevice(id)
        }

        if isPromptActive {
            return
        }

        beginPrompt(name: name)
    }

    private func beginPrompt(name: String) {
        isPromptActive = true
        activeCompletion = { [weak self] unlocked in
            guard let self = self else { return }
            self.isPromptActive = false
            self.activeCompletion = nil
            if unlocked {
                _ = self.audio.unlockCurrentDevice()
            }
            self.onPromptResolved?(unlocked)
        }

        auth.requestUnlock(deviceName: name) { [weak self] unlocked in
            self?.activeCompletion?(unlocked)
        }
    }

    public func systemWoke() {
        if audio.isLocked && !isPromptActive {
            let name = activeDeviceName.isEmpty ? "Bluetooth Headset" : activeDeviceName
            beginPrompt(name: name)
        }
    }

    public func defaultOutputChanged(id: UInt32, name: String, isBluetooth: Bool) {
        if isBluetooth {
            if !audio.isLocked && !isPromptActive {
                deviceConnected(id: id, name: name)
            }
        }
    }

    public func deviceDisconnected(id: UInt32, name: String) {
        activeDeviceID = 0
        activeDeviceName = ""

        if isPromptActive {
            isPromptActive = false
            let comp = activeCompletion
            // Clear first so the window's own dismissal callback can't resolve the prompt twice.
            activeCompletion = nil
            auth.dismiss()
            comp?(false)
        }
    }
}
