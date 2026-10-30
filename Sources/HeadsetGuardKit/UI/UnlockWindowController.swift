import AppKit
import QuartzCore
import LocalAuthentication
import LegacyCore

@objc(UnlockWindowController)
public final class UnlockWindowController: NSWindowController, NSTextFieldDelegate {

    @objc(sharedController)
    public static let shared = UnlockWindowController()

    @objc public var deviceName: String?
    @objc public var onCompletion: ((Bool) -> Void)?

    private var visualEffectView: NSVisualEffectView!
    private var iconImageView: NSImageView!
    private var titleLabel: NSTextField!
    private var deviceLabel: NSTextField!
    private var statusBadge: NSTextField!
    private var passwordField: NSSecureTextField!
    private var unlockButton: NSButton!
    private var touchIDButton: NSButton!
    private var disconnectButton: NSButton!
    private var errorLabel: NSTextField!

    private var attemptPolicy: UnlockAttemptPolicy

    public init() {
        let maxAttempts = SecurityManager.shared.integerSetting(kSecuritySettingMaxFailedAttempts, defaultValue: 3)
        self.attemptPolicy = UnlockAttemptPolicy(maxAttempts: maxAttempts)

        let windowRect = NSRect(x: 0, y: 0, width: 420, height: 410)
        let window = NSWindow(contentRect: windowRect,
                              styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = self.window, let contentView = window.contentView else { return }
        contentView.wantsLayer = true

        visualEffectView = NSVisualEffectView(frame: contentView.bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 18.0
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1.0
        visualEffectView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        contentView.addSubview(visualEffectView)

        let width: CGFloat = 420.0
        var y: CGFloat = 390.0

        // Header Icon
        y -= 70.0
        iconImageView = NSImageView(frame: NSRect(x: (width - 64) / 2.0, y: y, width: 64, height: 64))
        iconImageView.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Security") ?? NSImage(named: NSImage.lockLockedTemplateName)
        iconImageView.contentTintColor = .systemOrange
        visualEffectView.addSubview(iconImageView)

        // Status Badge
        y -= 30.0
        statusBadge = NSTextField(frame: NSRect(x: (width - 160) / 2.0, y: y, width: 160, height: 22))
        statusBadge.isEditable = false
        statusBadge.isSelectable = false
        statusBadge.isBordered = false
        statusBadge.alignment = .center
        statusBadge.stringValue = "AUDIO MUTED & LOCKED"
        statusBadge.font = .boldSystemFont(ofSize: 10.5)
        statusBadge.textColor = .systemRed
        statusBadge.wantsLayer = true
        statusBadge.layer?.backgroundColor = NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.18).cgColor
        statusBadge.layer?.cornerRadius = 6.0
        statusBadge.layer?.masksToBounds = true
        visualEffectView.addSubview(statusBadge)

        // Title
        y -= 32.0
        titleLabel = NSTextField(frame: NSRect(x: 20, y: y, width: width - 40, height: 24))
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBordered = false
        titleLabel.alignment = .center
        titleLabel.stringValue = "Headset Security Authorization"
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.backgroundColor = .clear
        visualEffectView.addSubview(titleLabel)

        // Device Subtitle
        y -= 22.0
        deviceLabel = NSTextField(frame: NSRect(x: 20, y: y, width: width - 40, height: 20))
        deviceLabel.isEditable = false
        deviceLabel.isSelectable = false
        deviceLabel.isBordered = false
        deviceLabel.alignment = .center
        deviceLabel.stringValue = "Bluetooth Headset Connected"
        deviceLabel.font = .systemFont(ofSize: 13, weight: .medium)
        deviceLabel.textColor = .secondaryLabelColor
        deviceLabel.backgroundColor = .clear
        visualEffectView.addSubview(deviceLabel)

        // Password Field
        y -= 52.0
        passwordField = NSSecureTextField(frame: NSRect(x: 50, y: y, width: width - 100, height: 36))
        passwordField.placeholderString = "Enter PIN or Password"
        passwordField.font = .systemFont(ofSize: 15)
        passwordField.alignment = .center
        passwordField.focusRingType = .exterior
        passwordField.target = self
        passwordField.action = #selector(unlockAction(_:))
        passwordField.delegate = self
        visualEffectView.addSubview(passwordField)

        // Error Label
        y -= 24.0
        errorLabel = NSTextField(frame: NSRect(x: 30, y: y, width: width - 60, height: 18))
        errorLabel.isEditable = false
        errorLabel.isSelectable = false
        errorLabel.isBordered = false
        errorLabel.alignment = .center
        errorLabel.stringValue = ""
        errorLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        errorLabel.textColor = .systemRed
        errorLabel.backgroundColor = .clear
        visualEffectView.addSubview(errorLabel)

        // Primary Unlock Button
        y -= 46.0
        unlockButton = NSButton(title: "Unlock Audio Output", target: self, action: #selector(unlockAction(_:)))
        unlockButton.frame = NSRect(x: 50, y: y, width: width - 100, height: 36)
        unlockButton.bezelStyle = .push
        unlockButton.keyEquivalent = "\r"
        unlockButton.font = .systemFont(ofSize: 13, weight: .semibold)
        visualEffectView.addSubview(unlockButton)

        // Secondary Touch ID Button
        y -= 38.0
        touchIDButton = NSButton(title: "Use Touch ID / Mac Password", target: self, action: #selector(touchIDAction(_:)))
        touchIDButton.frame = NSRect(x: 50, y: y, width: width - 100, height: 32)
        touchIDButton.bezelStyle = .push
        touchIDButton.font = .systemFont(ofSize: 12)
        touchIDButton.image = NSImage(systemSymbolName: "touchid", accessibilityDescription: "Touch ID")
        visualEffectView.addSubview(touchIDButton)

        // Disconnect Button
        y -= 34.0
        disconnectButton = NSButton(title: "Disconnect Headset & Block", target: self, action: #selector(disconnectAction(_:)))
        disconnectButton.frame = NSRect(x: 50, y: y, width: width - 100, height: 24)
        disconnectButton.isBordered = false
        disconnectButton.contentTintColor = .systemRed
        disconnectButton.font = .systemFont(ofSize: 11.5, weight: .medium)
        visualEffectView.addSubview(disconnectButton)
    }

    // MARK: - Presentation

    @objc(presentForDevice:completion:)
    public func present(for deviceName: String?, completion: ((Bool) -> Void)?) {
        let resolvedName = (deviceName != nil && !deviceName!.isEmpty) ? deviceName! : "Bluetooth Headset"
        self.deviceName = resolvedName
        self.onCompletion = completion

        let maxAttempts = SecurityManager.shared.integerSetting(kSecuritySettingMaxFailedAttempts, defaultValue: 3)
        self.attemptPolicy = UnlockAttemptPolicy(maxAttempts: maxAttempts)

        self.deviceLabel.stringValue = "Device: \(resolvedName)"
        self.passwordField.stringValue = ""
        self.errorLabel.stringValue = ""
        self.statusBadge.stringValue = "AUDIO MUTED & LOCKED"
        self.statusBadge.textColor = .systemRed
        self.statusBadge.layer?.backgroundColor = NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.18).cgColor

        self.iconImageView.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Security")
        self.iconImageView.contentTintColor = .systemOrange

        let sm = SecurityManager.shared
        self.touchIDButton.isHidden = !sm.biometricsAvailable

        self.window?.center()
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window?.makeFirstResponder(self.passwordField)

        if sm.biometricsAvailable && sm.boolSetting(kSecuritySettingBiometricsEnabled, defaultValue: true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self, let w = self.window, w.isVisible else { return }
                self.touchIDAction(nil)
            }
        }
    }

    @objc(dismissWithCompletion:)
    public func dismiss(unlocked: Bool) {
        self.window?.orderOut(nil)
        let completion = self.onCompletion
        self.onCompletion = nil
        completion?(unlocked)
    }

    @objc
    public func dismissWindow() {
        dismiss(unlocked: false)
    }

    // MARK: - Actions

    @objc private func unlockAction(_ sender: Any?) {
        let entered = passwordField.stringValue
        let sm = SecurityManager.shared

        if !sm.isPasswordConfigured {
            if entered.count < 4 {
                errorLabel.stringValue = "First time setup: Enter a PIN/password (min 4 chars)"
                shakeWindow()
                return
            }
            do {
                try sm.setupMasterPassword(entered)
                handleSuccessfulUnlock()
                return
            } catch {
                errorLabel.stringValue = error.localizedDescription
                shakeWindow()
                return
            }
        }

        if sm.verifyPassword(entered) {
            attemptPolicy.reset()
            handleSuccessfulUnlock()
        } else {
            handleFailedAttempt()
        }
    }

    @objc private func touchIDAction(_ sender: Any?) {
        let sm = SecurityManager.shared
        let reason = "Authorize audio output for \(self.deviceName ?? "Bluetooth Headset")"

        sm.authenticateWithBiometrics(reason: reason) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    self.attemptPolicy.reset()
                    self.handleSuccessfulUnlock()
                } else if let error = error as? NSError, error.code != Int(kLAErrorUserCancel) {
                    self.errorLabel.stringValue = "Touch ID verification failed"
                    self.shakeWindow()
                }
            }
        }
    }

    @objc private func disconnectAction(_ sender: Any?) {
        let target = self.deviceName ?? "Bluetooth Headset"
        SecurityManager.shared.logEvent("Manual Disconnect",
                                          details: "User rejected and disconnected \(target)",
                                          type: "disconnect")

        BluetoothManager.shared().disconnectDeviceNamed(target)
        AudioGuard.shared().routeAudioToBuiltIn()
        dismiss(unlocked: false)
    }

    // MARK: - Unlock Flow

    private func handleSuccessfulUnlock() {
        NSSound(named: "Hero")?.play()

        errorLabel.textColor = .systemGreen
        errorLabel.stringValue = "Authorization Approved!"
        statusBadge.stringValue = "UNLOCKED & AUTHORIZED"
        statusBadge.textColor = .systemGreen
        statusBadge.layer?.backgroundColor = NSColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.18).cgColor

        iconImageView.image = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: "Success")
        iconImageView.contentTintColor = .systemGreen

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.dismiss(unlocked: true)
        }
    }

    private func handleFailedAttempt() {
        NSSound(named: "Funk")?.play()
        shakeWindow()

        let sm = SecurityManager.shared
        let outcome = attemptPolicy.recordFailure()

        switch outcome {
        case .retry(let remaining):
            errorLabel.stringValue = "Incorrect password. \(remaining) attempt\(remaining == 1 ? "" : "s") remaining."
        case .lockedOut:
            errorLabel.stringValue = "Security Limit Reached! Disconnecting..."
            if sm.boolSetting(kSecuritySettingAutoDisconnectOnFailure, defaultValue: true) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.disconnectAction(nil)
                }
            }
        }

        passwordField.stringValue = ""
    }

    private func shakeWindow() {
        guard let layer = self.window?.contentView?.layer else { return }
        let currentX = layer.position.x
        let shake = CAKeyframeAnimation(keyPath: "position.x")
        shake.values = [
            currentX,
            currentX - 12,
            currentX + 12,
            currentX - 8,
            currentX + 8,
            currentX - 4,
            currentX + 4,
            currentX
        ]
        shake.duration = 0.4
        layer.add(shake, forKey: "shakeAnimation")
    }
}
