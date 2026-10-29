import AppKit
import IOBluetooth
import LegacyCore

@objc(PreferencesWindowController)
public final class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    @objc(sharedController)
    public static let shared = PreferencesWindowController()

    private var tabView: NSTabView!

    // Tab 1 controls
    private var autoLockCheckbox: NSButton!
    private var strictMuteCheckbox: NSButton!
    private var lockOnSleepCheckbox: NSButton!
    private var biometricsCheckbox: NSButton!
    private var autoDisconnectCheckbox: NSButton!
    private var maxAttemptsPopup: NSPopUpButton!

    // Tab 2 controls
    private var currentPasswordField: NSSecureTextField!
    private var freshPasswordField: NSSecureTextField!
    private var confirmPasswordField: NSSecureTextField!
    private var passwordStatusLabel: NSTextField!

    // Tab 3 controls
    private var protectAllCheckbox: NSButton!
    private var devicesTableView: NSTableView!
    private var pairedDevices: [IOBluetoothDevice] = []
    private var selectedDevices: Set<String> = []

    // Tab 4 controls
    private var logTableView: NSTableView!
    private var logs: [[String: Any]] = []

    public init() {
        let frame = NSRect(x: 0, y: 0, width: 560, height: 480)
        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "HeadsetGuard Preferences & Security Dashboard"
        window.minSize = NSSize(width: 560, height: 480)

        super.init(window: window)

        let initialDevices = SecurityManager.shared().protectedDevices()
        selectedDevices = Set(initialDevices)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = self.window, let contentView = window.contentView else { return }

        tabView = NSTabView(frame: NSRect(x: 16, y: 16, width: 528, height: 448))
        tabView.autoresizingMask = [.width, .height]

        let tabGeneral = NSTabViewItem(identifier: "general")
        tabGeneral.label = "General Security"
        tabGeneral.view = createGeneralTabView()
        tabView.addTabViewItem(tabGeneral)

        let tabPassword = NSTabViewItem(identifier: "password")
        tabPassword.label = "Password & PIN"
        tabPassword.view = createPasswordTabView()
        tabView.addTabViewItem(tabPassword)

        let tabDevices = NSTabViewItem(identifier: "devices")
        tabDevices.label = "Protected Headsets"
        tabDevices.view = createDevicesTabView()
        tabView.addTabViewItem(tabDevices)

        let tabLogs = NSTabViewItem(identifier: "logs")
        tabLogs.label = "Activity Log"
        tabLogs.view = createLogsTabView()
        tabView.addTabViewItem(tabLogs)

        contentView.addSubview(tabView)
    }

    // MARK: - Tab 1: General Security

    private func createGeneralTabView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 410))
        let sm = SecurityManager.shared()

        var y: CGFloat = 370.0

        let header = NSTextField(frame: NSRect(x: 20, y: y, width: 480, height: 24))
        header.stringValue = "Protection & Locking Rules"
        header.font = .boldSystemFont(ofSize: 14)
        header.isEditable = false
        header.isBordered = false
        header.backgroundColor = .clear
        view.addSubview(header)

        y -= 34.0
        autoLockCheckbox = NSButton(checkboxWithTitle: "Auto-Lock audio whenever a Bluetooth headset connects",
                                    target: self,
                                    action: #selector(settingChanged(_:)))
        autoLockCheckbox.frame = NSRect(x: 24, y: y, width: 460, height: 22)
        autoLockCheckbox.state = sm.boolSetting(kSecuritySettingAutoLockOnConnect, defaultValue: true) ? .on : .off
        view.addSubview(autoLockCheckbox)

        y -= 30.0
        strictMuteCheckbox = NSButton(checkboxWithTitle: "Strict Mute Clamp: intercept and block physical volume buttons while locked",
                                      target: self,
                                      action: #selector(settingChanged(_:)))
        strictMuteCheckbox.frame = NSRect(x: 24, y: y, width: 460, height: 22)
        strictMuteCheckbox.state = sm.boolSetting(kSecuritySettingStrictMute, defaultValue: true) ? .on : .off
        view.addSubview(strictMuteCheckbox)

        y -= 30.0
        lockOnSleepCheckbox = NSButton(checkboxWithTitle: "Re-lock headset audio on Mac sleep or lock screen",
                                       target: self,
                                       action: #selector(settingChanged(_:)))
        lockOnSleepCheckbox.frame = NSRect(x: 24, y: y, width: 460, height: 22)
        lockOnSleepCheckbox.state = sm.boolSetting(kSecuritySettingLockOnSleep, defaultValue: true) ? .on : .off
        view.addSubview(lockOnSleepCheckbox)

        y -= 30.0
        biometricsCheckbox = NSButton(checkboxWithTitle: "Allow Touch ID / Apple Watch / Mac Password for quick unlock",
                                      target: self,
                                      action: #selector(settingChanged(_:)))
        biometricsCheckbox.frame = NSRect(x: 24, y: y, width: 460, height: 22)
        biometricsCheckbox.state = sm.boolSetting(kSecuritySettingBiometricsEnabled, defaultValue: true) ? .on : .off
        view.addSubview(biometricsCheckbox)

        y -= 45.0
        let failHeader = NSTextField(frame: NSRect(x: 20, y: y, width: 480, height: 22))
        failHeader.stringValue = "Anti-Theft & Failure Safeguards"
        failHeader.font = .boldSystemFont(ofSize: 14)
        failHeader.isEditable = false
        failHeader.isBordered = false
        failHeader.backgroundColor = .clear
        view.addSubview(failHeader)

        y -= 32.0
        autoDisconnectCheckbox = NSButton(checkboxWithTitle: "Disconnect and kick Bluetooth device off if password attempts exceed limit",
                                          target: self,
                                          action: #selector(settingChanged(_:)))
        autoDisconnectCheckbox.frame = NSRect(x: 24, y: y, width: 470, height: 22)
        autoDisconnectCheckbox.state = sm.boolSetting(kSecuritySettingAutoDisconnectOnFailure, defaultValue: true) ? .on : .off
        view.addSubview(autoDisconnectCheckbox)

        y -= 36.0
        let attemptsLabel = NSTextField(frame: NSRect(x: 24, y: y, width: 200, height: 22))
        attemptsLabel.stringValue = "Maximum failed password attempts:"
        attemptsLabel.isEditable = false
        attemptsLabel.isBordered = false
        attemptsLabel.backgroundColor = .clear
        view.addSubview(attemptsLabel)

        maxAttemptsPopup = NSPopUpButton(frame: NSRect(x: 230, y: y, width: 90, height: 24), pullsDown: false)
        maxAttemptsPopup.addItems(withTitles: ["3", "5", "10"])
        let cur = sm.integerSetting(kSecuritySettingMaxFailedAttempts, defaultValue: 3)
        maxAttemptsPopup.selectItem(withTitle: "\(cur)")
        maxAttemptsPopup.target = self
        maxAttemptsPopup.action = #selector(settingChanged(_:))
        view.addSubview(maxAttemptsPopup)

        return view
    }

    // MARK: - Tab 2: Password / PIN

    private func createPasswordTabView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 410))
        let sm = SecurityManager.shared()

        var y: CGFloat = 370.0
        let header = NSTextField(frame: NSRect(x: 20, y: y, width: 480, height: 24))
        header.stringValue = sm.isPasswordConfigured ? "Change Master Security PIN / Password" : "Set Up Master Security PIN / Password"
        header.font = .boldSystemFont(ofSize: 14)
        header.isEditable = false
        header.isBordered = false
        header.backgroundColor = .clear
        view.addSubview(header)

        y -= 26.0
        let sub = NSTextField(frame: NSRect(x: 20, y: y, width: 480, height: 20))
        sub.stringValue = "Used to authorize audio streaming whenever your Bluetooth headset connects."
        sub.font = .systemFont(ofSize: 12)
        sub.textColor = .secondaryLabelColor
        sub.isEditable = false
        sub.isBordered = false
        sub.backgroundColor = .clear
        view.addSubview(sub)

        y -= 44.0
        let lblCurrent = NSTextField(frame: NSRect(x: 20, y: y, width: 160, height: 22))
        lblCurrent.stringValue = "Current Password:"
        lblCurrent.isEditable = false
        lblCurrent.isBordered = false
        lblCurrent.backgroundColor = .clear
        view.addSubview(lblCurrent)

        currentPasswordField = NSSecureTextField(frame: NSRect(x: 180, y: y, width: 260, height: 24))
        currentPasswordField.isEnabled = sm.isPasswordConfigured
        currentPasswordField.placeholderString = sm.isPasswordConfigured ? "Enter current password" : "(No password configured yet)"
        view.addSubview(currentPasswordField)

        y -= 36.0
        let lblNew = NSTextField(frame: NSRect(x: 20, y: y, width: 160, height: 22))
        lblNew.stringValue = "New PIN / Password:"
        lblNew.isEditable = false
        lblNew.isBordered = false
        lblNew.backgroundColor = .clear
        view.addSubview(lblNew)

        freshPasswordField = NSSecureTextField(frame: NSRect(x: 180, y: y, width: 260, height: 24))
        freshPasswordField.placeholderString = "At least 4 characters"
        view.addSubview(freshPasswordField)

        y -= 36.0
        let lblConfirm = NSTextField(frame: NSRect(x: 20, y: y, width: 160, height: 22))
        lblConfirm.stringValue = "Confirm New Password:"
        lblConfirm.isEditable = false
        lblConfirm.isBordered = false
        lblConfirm.backgroundColor = .clear
        view.addSubview(lblConfirm)

        confirmPasswordField = NSSecureTextField(frame: NSRect(x: 180, y: y, width: 260, height: 24))
        confirmPasswordField.placeholderString = "Re-enter new password"
        view.addSubview(confirmPasswordField)

        y -= 42.0
        let btnSave = NSButton(title: "Save Password", target: self, action: #selector(savePasswordClicked(_:)))
        btnSave.frame = NSRect(x: 180, y: y, width: 140, height: 32)
        btnSave.bezelStyle = .push
        view.addSubview(btnSave)

        y -= 30.0
        passwordStatusLabel = NSTextField(frame: NSRect(x: 20, y: y, width: 480, height: 22))
        passwordStatusLabel.stringValue = ""
        passwordStatusLabel.isEditable = false
        passwordStatusLabel.isBordered = false
        passwordStatusLabel.backgroundColor = .clear
        passwordStatusLabel.alignment = .center
        view.addSubview(passwordStatusLabel)

        return view
    }

    // MARK: - Tab 3: Protected Devices

    private func createDevicesTabView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 410))
        let sm = SecurityManager.shared()

        var y: CGFloat = 370.0
        let header = NSTextField(frame: NSRect(x: 20, y: y, width: 480, height: 24))
        header.stringValue = "Target Headsets & Bluetooth Devices"
        header.font = .boldSystemFont(ofSize: 14)
        header.isEditable = false
        header.isBordered = false
        header.backgroundColor = .clear
        view.addSubview(header)

        y -= 30.0
        protectAllCheckbox = NSButton(checkboxWithTitle: "Protect ALL Bluetooth Audio Devices (Recommended)",
                                      target: self,
                                      action: #selector(protectAllToggled(_:)))
        protectAllCheckbox.frame = NSRect(x: 24, y: y, width: 460, height: 22)
        protectAllCheckbox.state = sm.boolSetting(kSecuritySettingProtectAllBluetooth, defaultValue: true) ? .on : .off
        view.addSubview(protectAllCheckbox)

        y -= 26.0
        let sub = NSTextField(frame: NSRect(x: 24, y: y, width: 480, height: 18))
        sub.stringValue = "Or select specific paired headsets below to lock:"
        sub.font = .systemFont(ofSize: 11.5)
        sub.textColor = .secondaryLabelColor
        sub.isEditable = false
        sub.isBordered = false
        sub.backgroundColor = .clear
        view.addSubview(sub)

        y -= 210.0
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: y, width: 480, height: 200))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        devicesTableView = NSTableView(frame: scrollView.bounds)
        let colCheck = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        colCheck.title = "Protect"
        colCheck.width = 60.0
        devicesTableView.addTableColumn(colCheck)

        let colName = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        colName.title = "Device Name"
        colName.width = 240.0
        devicesTableView.addTableColumn(colName)

        let colStatus = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        colStatus.title = "Status"
        colStatus.width = 150.0
        devicesTableView.addTableColumn(colStatus)

        devicesTableView.dataSource = self
        devicesTableView.delegate = self
        scrollView.documentView = devicesTableView
        view.addSubview(scrollView)

        y -= 40.0
        let btnRefresh = NSButton(title: "Refresh Paired Headsets", target: self, action: #selector(refreshDevicesClicked(_:)))
        btnRefresh.frame = NSRect(x: 20, y: y, width: 180, height: 30)
        btnRefresh.bezelStyle = .push
        view.addSubview(btnRefresh)

        reloadPairedDevices()
        return view
    }

    // MARK: - Tab 4: Activity Log

    private func createLogsTabView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 410))

        let y: CGFloat = 370.0
        let header = NSTextField(frame: NSRect(x: 20, y: y, width: 300, height: 24))
        header.stringValue = "Security Audit & Event Log"
        header.font = .boldSystemFont(ofSize: 14)
        header.isEditable = false
        header.isBordered = false
        header.backgroundColor = .clear
        view.addSubview(header)

        let btnClear = NSButton(title: "Clear Log", target: self, action: #selector(clearLogsClicked(_:)))
        btnClear.frame = NSRect(x: 380, y: y, width: 120, height: 26)
        btnClear.bezelStyle = .push
        view.addSubview(btnClear)

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: y - 320.0, width: 480, height: 310))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        logTableView = NSTableView(frame: scrollView.bounds)

        let colTime = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time"))
        colTime.title = "Timestamp"
        colTime.width = 130.0
        logTableView.addTableColumn(colTime)

        let colEvent = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("event"))
        colEvent.title = "Event"
        colEvent.width = 130.0
        logTableView.addTableColumn(colEvent)

        let colDetails = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("details"))
        colDetails.title = "Details"
        colDetails.width = 200.0
        logTableView.addTableColumn(colDetails)

        logTableView.dataSource = self
        logTableView.delegate = self
        scrollView.documentView = logTableView
        view.addSubview(scrollView)

        reloadLogs()
        return view
    }

    // MARK: - Actions

    @objc public func showPreferences() {
        self.window?.center()
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reloadPairedDevices()
        reloadLogs()
    }

    @objc private func settingChanged(_ sender: Any?) {
        let sm = SecurityManager.shared()
        sm.setBoolSetting(kSecuritySettingAutoLockOnConnect, value: autoLockCheckbox.state == .on)
        sm.setBoolSetting(kSecuritySettingStrictMute, value: strictMuteCheckbox.state == .on)
        sm.setBoolSetting(kSecuritySettingLockOnSleep, value: lockOnSleepCheckbox.state == .on)
        sm.setBoolSetting(kSecuritySettingBiometricsEnabled, value: biometricsCheckbox.state == .on)
        sm.setBoolSetting(kSecuritySettingAutoDisconnectOnFailure, value: autoDisconnectCheckbox.state == .on)

        if let selectedTitle = maxAttemptsPopup.titleOfSelectedItem, let attempts = Int(selectedTitle), attempts > 0 {
            sm.setIntegerSetting(kSecuritySettingMaxFailedAttempts, value: attempts)
        }

        AudioGuard.shared().strictMuteEnforcement = (strictMuteCheckbox.state == .on)
    }

    @objc private func protectAllToggled(_ sender: Any?) {
        let protectAll = (protectAllCheckbox.state == .on)
        SecurityManager.shared().setBoolSetting(kSecuritySettingProtectAllBluetooth, value: protectAll)
        devicesTableView.reloadData()
    }

    @objc private func savePasswordClicked(_ sender: Any?) {
        let sm = SecurityManager.shared()
        let curr = currentPasswordField.stringValue
        let newP = freshPasswordField.stringValue
        let conf = confirmPasswordField.stringValue

        if newP.count < 4 {
            passwordStatusLabel.textColor = .systemRed
            passwordStatusLabel.stringValue = "New password must be at least 4 characters."
            return
        }
        if newP != conf {
            passwordStatusLabel.textColor = .systemRed
            passwordStatusLabel.stringValue = "New passwords do not match."
            return
        }

        do {
            if sm.isPasswordConfigured {
                try sm.changePassword(from: curr, to: newP)
            } else {
                try sm.setupMasterPassword(newP)
            }
            passwordStatusLabel.textColor = .systemGreen
            passwordStatusLabel.stringValue = "Master password successfully updated!"
            currentPasswordField.stringValue = ""
            freshPasswordField.stringValue = ""
            confirmPasswordField.stringValue = ""
            currentPasswordField.isEnabled = true
        } catch {
            passwordStatusLabel.textColor = .systemRed
            passwordStatusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func refreshDevicesClicked(_ sender: Any?) {
        reloadPairedDevices()
    }

    @objc private func clearLogsClicked(_ sender: Any?) {
        SecurityManager.shared().clearLogs()
        reloadLogs()
    }

    private func reloadPairedDevices() {
        pairedDevices = BluetoothManager.shared().pairedAudioDevices()
        devicesTableView?.reloadData()
    }

    private func reloadLogs() {
        logs = SecurityManager.shared().recentLogs() as? [[String: Any]] ?? []
        logTableView?.reloadData()
    }

    // MARK: - Table View Data Source & Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == devicesTableView {
            return pairedDevices.count
        } else if tableView == logTableView {
            return logs.count
        }
        return 0
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }

        if tableView == devicesTableView {
            guard row < pairedDevices.count else { return nil }
            let dev = pairedDevices[row]
            let colId = column.identifier.rawValue

            if colId == "check" {
                let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(deviceCheckToggled(_:)))
                check.tag = row
                let protectAll = SecurityManager.shared().boolSetting(kSecuritySettingProtectAllBluetooth, defaultValue: true)
                if protectAll {
                    check.state = .on
                    check.isEnabled = false
                } else {
                    check.isEnabled = true
                    let name = dev.nameOrAddress ?? ""
                    check.state = selectedDevices.contains(name) ? .on : .off
                }
                return check
            } else if colId == "name" {
                let txt = NSTextField(labelWithString: dev.nameOrAddress ?? "Unknown")
                txt.font = .systemFont(ofSize: 12, weight: .medium)
                return txt
            } else if colId == "status" {
                let isConn = dev.isConnected()
                let stat = isConn ? "Connected 🎧" : "Paired (Offline)"
                let txt = NSTextField(labelWithString: stat)
                txt.textColor = isConn ? .systemGreen : .secondaryLabelColor
                txt.font = .systemFont(ofSize: 11.5)
                return txt
            }
        } else if tableView == logTableView {
            guard row < logs.count else { return nil }
            let entry = logs[row]
            let colId = column.identifier.rawValue

            if colId == "time" {
                return NSTextField(labelWithString: (entry["timestamp"] as? String) ?? "")
            } else if colId == "event" {
                let txt = NSTextField(labelWithString: (entry["event"] as? String) ?? "")
                txt.font = .systemFont(ofSize: 11.5, weight: .semibold)
                return txt
            } else if colId == "details" {
                return NSTextField(labelWithString: (entry["details"] as? String) ?? "")
            }
        }
        return nil
    }

    @objc private func deviceCheckToggled(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < pairedDevices.count else { return }
        let dev = pairedDevices[row]
        guard let name = dev.nameOrAddress else { return }

        if sender.state == .on {
            selectedDevices.insert(name)
        } else {
            selectedDevices.remove(name)
        }

        SecurityManager.shared().setProtectedDevices(Array(selectedDevices))
    }
}
