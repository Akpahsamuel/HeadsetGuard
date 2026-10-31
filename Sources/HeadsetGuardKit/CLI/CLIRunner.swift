import Foundation
import CoreAudio

public struct CLIRunner {
    public init() {}

    private func printUsage() {
        print("HeadsetGuard - Bluetooth Headset Security & Audio Locker for macOS\n")
        print("Usage:")
        print("  HeadsetGuard                 Run full menu bar application and security daemon")
        print("  HeadsetGuard --status        Show current audio and Bluetooth security status")
        print("  HeadsetGuard --list          List all detected Bluetooth headsets and paired devices")
        print("  HeadsetGuard --lock          Manually lock current active Bluetooth headset")
        print("  HeadsetGuard --unlock        Prompt to unlock active Bluetooth headset")
        print("  HeadsetGuard --disconnect    Disconnect active Bluetooth headset immediately")
        print("  HeadsetGuard --set-password  Set or change master password from terminal")
        print("  HeadsetGuard --logs          Display recent security audit log events")
        print("  HeadsetGuard --help          Show this help message\n")
    }

    private func readPasswordInput(prompt: String = "Enter new Master PIN or Password (min 4 characters): ") -> String? {
        if isatty(STDIN_FILENO) != 0, let passC = getpass(prompt) {
            return String(cString: passC)
        }
        print(prompt, terminator: "")
        fflush(stdout)
        guard let line = readLine(strippingNewline: true) else { return nil }
        return line
    }

    private func padRight(_ text: String, width: Int) -> String {
        if text.count < width {
            return text.padding(toLength: width, withPad: " ", startingAt: 0)
        }
        return text
    }

    public func run(_ command: Command) -> Int32 {
        switch command {
        case .help:
            printUsage()
            return 0

        case .status:
            let ag = AudioGuard.shared
            let defID = ag.defaultOutputDeviceID()
            let rawDefName = ag.deviceName(forID: defID)
            let defName = rawDefName.isEmpty ? "Unknown" : rawDefName
            let isBT = ag.isBluetoothDevice(defID)
            let sm = SecurityManager.shared

            print("=== HeadsetGuard Status ===")
            print("Master Password Configured: \(sm.isPasswordConfigured ? "YES" : "NO (First-time setup needed)")")
            print("Touch ID / Biometrics Available: \(sm.biometricsAvailable ? "YES" : "NO")")
            print("Default Output: \(defName) (ID: \(defID))")
            print("Default Output is Bluetooth: \(isBT ? "YES" : "NO")")
            print("Current Audio Guard State: \(ag.isLocked ? "LOCKED (Muted)" : "UNLOCKED / Normal")")
            if ag.isLocked {
                print("Locked Device: \(ag.lockedDeviceName ?? "Unknown") (ID: \(ag.lockedDeviceID))")
            }
            return 0

        case .list:
            print("=== Paired Bluetooth Audio Devices ===")
            let paired = BluetoothManager.shared.pairedAudioDevices()
            if paired.isEmpty {
                print("No paired Bluetooth audio devices found.")
            } else {
                for dev in paired {
                    let name = dev.nameOrAddress ?? ""
                    let addr = dev.addressString ?? ""
                    let connected = dev.isConnected() ? "YES 🎧" : "NO"
                    let paddedName = padRight(name, width: 30)
                    print("  • \(paddedName) [Addr: \(addr), Connected: \(connected)]")
                }
            }

            print("\n=== Active CoreAudio Output Devices ===")
            let outputs = AudioGuard.shared.allOutputDevices()
            for info in outputs {
                let devName = (info["name"] as? String) ?? "Unknown"
                let devID = (info["id"] as? NSNumber)?.uint32Value ?? 0
                let isBT = (info["isBluetooth"] as? NSNumber)?.boolValue ?? false
                let paddedDevName = padRight(devName, width: 30)
                print("  • \(paddedDevName) [ID: \(devID), Bluetooth: \(isBT ? "YES" : "NO")]")
            }
            return 0

        case .lock:
            let ag = AudioGuard.shared
            let defID = ag.defaultOutputDeviceID()
            if defID != kAudioObjectUnknown && ag.isBluetoothDevice(defID) {
                let name = ag.deviceName(forID: defID)
                ag.lockDevice(defID)
                print("Successfully locked and muted Bluetooth headset '\(name)' (ID: \(defID)).")
                return 0
            } else {
                print("No active Bluetooth headset detected on default output to lock.")
                return 1
            }

        case .unlock:
            let ag = AudioGuard.shared
            if ag.isLocked {
                ag.unlockCurrentDevice()
                print("Successfully unlocked active Bluetooth headset.")
                return 0
            } else {
                print("No locked Bluetooth headset to unlock.")
                return 0
            }

        case .disconnect:
            let ag = AudioGuard.shared
            let defID = ag.defaultOutputDeviceID()
            let name = ag.deviceName(forID: defID)
            if !name.isEmpty {
                BluetoothManager.shared.disconnectDevice(named: name)
                ag.routeAudioToBuiltIn()
                print("Disconnected '\(name)' and restored audio to built-in speakers.")
                return 0
            }
            print("No active device found to disconnect.")
            return 1

        case .setPassword:
            let sm = SecurityManager.shared
            if sm.isPasswordConfigured {
                guard let current = readPasswordInput(prompt: "Enter CURRENT Master PIN or Password: ") else { return 1 }
                guard sm.verifyPassword(current) else {
                    print("Error: Current password is incorrect.")
                    return 1
                }
            }
            if let input = readPasswordInput() {
                let newPass = input.trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    try SecurityManager.shared.setupMasterPassword(newPass)
                    print("Master PIN/Password successfully configured!")
                    return 0
                } catch {
                    print("Error: \(error.localizedDescription)")
                    return 1
                }
            }
            return 1

        case .logs:
            print("=== Recent Security Audit Logs ===")
            let logs = SecurityManager.shared.recentLogs()
            if logs.isEmpty {
                print("No log entries recorded yet.")
            } else {
                for log in logs {
                    let timestamp = (log["timestamp"] as? String) ?? ""
                    let event = (log["event"] as? String) ?? ""
                    let details = (log["details"] as? String) ?? ""
                    let paddedEvent = padRight(event, width: 22)
                    print("[\(timestamp)] \(paddedEvent): \(details)")
                }
            }
            return 0

        case .unknown(let arg):
            print("Unknown argument: \(arg)")
            print("Run 'HeadsetGuard --help' for usage.")
            return 1

        case .app:
            return 0
        }
    }
}
