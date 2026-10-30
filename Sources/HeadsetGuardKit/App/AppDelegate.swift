import AppKit
import CoreAudio
import IOBluetooth
import LegacyCore

public enum GuardStatus {
    case idle
    case locked
    case authorized
}

@objc(AppDelegate)
public final class AppDelegate: NSObject, NSApplicationDelegate, AudioGuardDelegate, BluetoothManagerDelegate {

    @objc public var statusItem: NSStatusItem!

    private var statusMenu: NSMenu!
    private var headerItem: NSMenuItem!
    private var unlockMenuItem: NSMenuItem!
    private var lockMenuItem: NSMenuItem!
    private var disconnectMenuItem: NSMenuItem!

    private var currentStatus: GuardStatus = .idle
    private var activeHeadsetName: String?
    private var activeDeviceID: AudioDeviceID = kAudioObjectUnknown

    public private(set) var coordinator: LockCoordinator!

    public override init() {
        super.init()
        let audio = AudioGuard.shared()
        let auth = UnlockWindowAdapter()
        let link = BluetoothManager.shared
        self.coordinator = LockCoordinator(audio: audio, auth: auth, link: link)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] HeadsetGuard starting up...")
        currentStatus = .idle
        activeHeadsetName = nil
        activeDeviceID = kAudioObjectUnknown

        setupStatusItem()

        let ag = AudioGuard.shared()
        let bm = BluetoothManager.shared
        ag.delegate = self
        bm.delegate = self

        ag.startMonitoring()
        bm.startMonitoring()

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(workspaceWillSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(workspaceDidWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(sessionDidResignActive(_:)), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)

        checkInitialConnectedHeadsets()

        if !SecurityManager.shared.isPasswordConfigured {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                PreferencesWindowController.shared.showPreferences()
            }
        }

        SecurityManager.shared.logEvent("App Started", details: "HeadsetGuard armed and monitoring", type: "system")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        NSLog("[AppDelegate] HeadsetGuard terminating.")
        if AudioGuard.shared().isLocked {
            AudioGuard.shared().unlockCurrentDevice()
        }
        AudioGuard.shared().stopMonitoring()
        BluetoothManager.shared.stopMonitoring()
    }

    // MARK: - Menu Bar Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusMenu = NSMenu()

        headerItem = NSMenuItem(title: "HeadsetGuard: Armed (No Headset)", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        statusMenu.addItem(headerItem)

        statusMenu.addItem(NSMenuItem.separator())

        unlockMenuItem = NSMenuItem(title: "Authorize & Unlock Audio...", action: #selector(unlockMenuClicked(_:)), keyEquivalent: "u")
        unlockMenuItem.target = self
        statusMenu.addItem(unlockMenuItem)

        lockMenuItem = NSMenuItem(title: "Lock Headset Audio Now", action: #selector(lockMenuClicked(_:)), keyEquivalent: "l")
        lockMenuItem.target = self
        statusMenu.addItem(lockMenuItem)

        statusMenu.addItem(NSMenuItem.separator())

        disconnectMenuItem = NSMenuItem(title: "Disconnect Headset", action: #selector(disconnectMenuClicked(_:)), keyEquivalent: "d")
        disconnectMenuItem.target = self
        statusMenu.addItem(disconnectMenuItem)

        statusMenu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences & Security Dashboard...", action: #selector(preferencesMenuClicked(_:)), keyEquivalent: ",")
        prefsItem.target = self
        statusMenu.addItem(prefsItem)

        let pinItem = NSMenuItem(title: "Change Security Password/PIN...", action: #selector(changePinMenuClicked(_:)), keyEquivalent: "p")
        pinItem.target = self
        statusMenu.addItem(pinItem)

        statusMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit HeadsetGuard", action: #selector(quitMenuClicked(_:)), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)

        statusItem.menu = statusMenu
        updateStatusIcon(.idle)
    }

    public func updateStatusIcon(_ status: GuardStatus) {
        currentStatus = status

        var icon: NSImage?
        var tooltip = "HeadsetGuard"

        switch status {
        case .idle:
            icon = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Idle")
            icon?.isTemplate = true
            tooltip = "HeadsetGuard: Armed (Monitoring)"
        case .locked:
            icon = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
            icon?.isTemplate = false
            tooltip = "HeadsetGuard: LOCKED (\(activeHeadsetName ?? "Headset"))"
        case .authorized:
            icon = NSImage(systemSymbolName: "headphones.circle.fill", accessibilityDescription: "Authorized")
            icon?.isTemplate = false
            tooltip = "HeadsetGuard: Authorized (\(activeHeadsetName ?? "Headset"))"
        }

        statusItem?.button?.image = icon
        statusItem?.button?.toolTip = tooltip

        switch status {
        case .idle:
            headerItem?.title = "HeadsetGuard: Armed (No Headset)"
            unlockMenuItem?.isHidden = true
            lockMenuItem?.isHidden = true
            disconnectMenuItem?.isHidden = true
        case .locked:
            headerItem?.title = "🔒 \(activeHeadsetName ?? "Headset") [LOCKED]"
            unlockMenuItem?.isHidden = false
            lockMenuItem?.isHidden = true
            disconnectMenuItem?.isHidden = false
        case .authorized:
            headerItem?.title = "🔓 \(activeHeadsetName ?? "Headset") [AUTHORIZED]"
            unlockMenuItem?.isHidden = true
            lockMenuItem?.isHidden = false
            disconnectMenuItem?.isHidden = false
        }
    }

    // MARK: - Initial Checks

    private func checkInitialConnectedHeadsets() {
        let ag = AudioGuard.shared()
        let defID = ag.defaultOutputDeviceID()

        if defID != kAudioObjectUnknown && ag.isBluetoothDevice(defID) {
            let name = ag.deviceName(forID: defID)
            NSLog("[AppDelegate] Discovered already active Bluetooth audio device: '%@' (ID: %u)", name, defID)
            handleHeadsetConnected(defID, name: name)
        } else {
            let btDevs = ag.allBluetoothOutputDevices()
            if let first = btDevs.first,
               let devIDNum = first["id"] as? NSNumber,
               let name = first["name"] as? String {
                let devID = devIDNum.uint32Value
                NSLog("[AppDelegate] Discovered connected Bluetooth audio device: '%@' (ID: %u)", name, devID)
                handleHeadsetConnected(devID, name: name)
            }
        }
    }

    // MARK: - Security Enforcement Flow

    private func handleHeadsetConnected(_ deviceID: AudioDeviceID, name: String) {
        activeDeviceID = deviceID
        activeHeadsetName = name.isEmpty ? "Bluetooth Headset" : name

        let sm = SecurityManager.shared

        if !sm.isDeviceProtected(name) {
            NSLog("[AppDelegate] Device '%@' is not in protected list. Skipping lock.", name)
            updateStatusIcon(.authorized)
            return
        }

        if !sm.boolSetting(kSecuritySettingAutoLockOnConnect, defaultValue: true) {
            NSLog("[AppDelegate] Auto-lock on connect disabled. Skipping lock.")
            updateStatusIcon(.authorized)
            return
        }

        NSLog("[AppDelegate] Auto-locking headset '%@'...", name)
        AudioGuard.shared().lockDevice(deviceID)
        updateStatusIcon(.locked)

        sm.logEvent("Headset Connected",
                    details: "'\(name)' connected -> Audio muted and locked",
                    type: "connect_lock")

        if coordinator.isPromptActive {
            NSLog("[AppDelegate] Unlock prompt already active. Skipping duplicate presentation.")
            return
        }

        coordinator.deviceConnected(id: deviceID, name: name)

        // Observe when prompt resolves to update status item
        UnlockWindowController.shared.onCompletion = { [weak self] unlocked in
            guard let self = self else { return }
            if unlocked {
                NSLog("[AppDelegate] Audio unlocked successfully for '%@'", self.activeHeadsetName ?? "")
                AudioGuard.shared().unlockCurrentDevice()
                self.updateStatusIcon(.authorized)
                SecurityManager.shared.logEvent("Unlocked",
                                                  details: "'\(self.activeHeadsetName ?? "Headset")' audio authorized",
                                                  type: "auth_success")
            } else {
                NSLog("[AppDelegate] Authorization rejected or failed for '%@'", self.activeHeadsetName ?? "")
            }
        }
    }

    private func handleHeadsetDisconnected(_ deviceID: AudioDeviceID, name: String) {
        NSLog("[AppDelegate] Headset disconnected: '%@'", name)
        coordinator.deviceDisconnected(id: deviceID, name: name)
        activeDeviceID = kAudioObjectUnknown
        activeHeadsetName = nil

        UnlockWindowController.shared.dismissWindow()
        updateStatusIcon(.idle)

        SecurityManager.shared.logEvent("Headset Disconnected",
                                          details: "'\(name)' disconnected",
                                          type: "disconnect")
    }

    // MARK: - Public Control Methods

    @objc public func lockCurrentHeadset() {
        var devID = activeDeviceID
        if devID == kAudioObjectUnknown {
            devID = AudioGuard.shared().defaultOutputDeviceID()
        }
        if devID != kAudioObjectUnknown && AudioGuard.shared().isBluetoothDevice(devID) {
            let name = AudioGuard.shared().deviceName(forID: devID)
            activeDeviceID = devID
            activeHeadsetName = name
            AudioGuard.shared().lockDevice(devID)
            updateStatusIcon(.locked)

            if coordinator.isPromptActive { return }

            coordinator.deviceConnected(id: devID, name: name)
            UnlockWindowController.shared.onCompletion = { [weak self] unlocked in
                guard let self = self else { return }
                if unlocked {
                    AudioGuard.shared().unlockCurrentDevice()
                    self.updateStatusIcon(.authorized)
                }
            }
        }
    }

    @objc public func unlockCurrentHeadset() {
        if coordinator.isPromptActive { return }

        let name = activeHeadsetName ?? "Bluetooth Headset"
        coordinator.deviceConnected(id: activeDeviceID, name: name)
        UnlockWindowController.shared.onCompletion = { [weak self] unlocked in
            guard let self = self else { return }
            if unlocked {
                AudioGuard.shared().unlockCurrentDevice()
                self.updateStatusIcon(.authorized)
            }
        }
    }

    @objc public func disconnectCurrentHeadset() {
        if let name = activeHeadsetName {
            BluetoothManager.shared.disconnectDevice(named: name)
            AudioGuard.shared().routeAudioToBuiltIn()
            UnlockWindowController.shared.dismissWindow()
            handleHeadsetDisconnected(activeDeviceID, name: name)
        }
    }

    // MARK: - Menu Actions

    @objc private func unlockMenuClicked(_ sender: Any?) {
        unlockCurrentHeadset()
    }

    @objc private func lockMenuClicked(_ sender: Any?) {
        lockCurrentHeadset()
    }

    @objc private func disconnectMenuClicked(_ sender: Any?) {
        disconnectCurrentHeadset()
    }

    @objc private func preferencesMenuClicked(_ sender: Any?) {
        PreferencesWindowController.shared.showPreferences()
    }

    @objc private func changePinMenuClicked(_ sender: Any?) {
        let pwc = PreferencesWindowController.shared
        pwc.showPreferences()
        pwc.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitMenuClicked(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - System Sleep / Lock Notifications

    @objc private func workspaceWillSleep(_ note: Notification) {
        NSLog("[AppDelegate] System going to sleep.")
        if SecurityManager.shared.boolSetting(kSecuritySettingLockOnSleep, defaultValue: true) {
            if activeDeviceID != kAudioObjectUnknown && AudioGuard.shared().isBluetoothDevice(activeDeviceID) {
                AudioGuard.shared().lockDevice(activeDeviceID)
                updateStatusIcon(.locked)
                SecurityManager.shared.logEvent("Sleep Lock", details: "System sleeping -> Headset audio locked", type: "sleep_lock")
            }
        }
    }

    @objc private func workspaceDidWake(_ note: Notification) {
        NSLog("[AppDelegate] System woke up.")
        if AudioGuard.shared().isLocked && !coordinator.isPromptActive {
            coordinator.systemWoke()
            UnlockWindowController.shared.onCompletion = { [weak self] unlocked in
                guard let self = self else { return }
                if unlocked {
                    AudioGuard.shared().unlockCurrentDevice()
                    self.updateStatusIcon(.authorized)
                }
            }
        }
    }

    @objc private func sessionDidResignActive(_ note: Notification) {
        NSLog("[AppDelegate] User session resigned active (screen lock).")
        if SecurityManager.shared.boolSetting(kSecuritySettingLockOnSleep, defaultValue: true) {
            if activeDeviceID != kAudioObjectUnknown && AudioGuard.shared().isBluetoothDevice(activeDeviceID) {
                AudioGuard.shared().lockDevice(activeDeviceID)
                updateStatusIcon(.locked)
                SecurityManager.shared.logEvent("Screen Lock", details: "Screen locked -> Headset audio locked", type: "sleep_lock")
            }
        }
    }

    // MARK: - AudioGuardDelegate

    public func audioGuardDidDetectBluetoothDeviceConnected(_ deviceID: AudioDeviceID, name: String) {
        NSLog("[AppDelegate] AudioGuard detected Bluetooth connected: '%@' (ID: %u)", name, deviceID)
        handleHeadsetConnected(deviceID, name: name)
    }

    public func audioGuardDidDetectBluetoothDeviceDisconnected(_ deviceID: AudioDeviceID, name: String) {
        NSLog("[AppDelegate] AudioGuard detected Bluetooth disconnected: '%@' (ID: %u)", name, deviceID)
        handleHeadsetDisconnected(deviceID, name: name)
    }

    public func audioGuardDidDetectDefaultOutputChanged(_ deviceID: AudioDeviceID, name: String, isBluetooth: Bool) {
        if isBluetooth {
            if currentStatus != .authorized && currentStatus != .locked && !coordinator.isPromptActive {
                handleHeadsetConnected(deviceID, name: name)
            }
        }
    }

    public func audioGuardDidInterceptVolumeTamper(onDevice deviceID: AudioDeviceID) {
        SecurityManager.shared.logEvent("Volume Tamper Intercepted",
                                          details: "Headset physical volume button pressed while locked; forced re-mute",
                                          type: "tamper")
    }

    // MARK: - BluetoothManagerDelegate

    public func bluetoothManagerDidDetectDeviceConnected(_ device: IOBluetoothDevice) {
        NSLog("[AppDelegate] BluetoothManager detected connection: '%@'", device.nameOrAddress ?? "unknown")
    }
}
