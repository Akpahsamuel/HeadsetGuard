# HeadsetGuard 🎧🔒
### Bluetooth Headset Audio Locker & Security Gatekeeper for macOS

[![Build](https://github.com/Akpahsamuel/HeadsetGuard/actions/workflows/build.yml/badge.svg)](https://github.com/Akpahsamuel/HeadsetGuard/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS 11+](https://img.shields.io/badge/platform-macOS%2011%2B-lightgrey)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

HeadsetGuard is free and open source. Contributions are welcome, see [Contributing](#-contributing).

**HeadsetGuard** brings password and biometric authentication to your Bluetooth headsets and earbuds (including AirPods, Sony WH-1000XM, Samsung Galaxy Buds, Bose QC, and generic Bluetooth audio devices).

---

## 🛡 Why HeadsetGuard?

Standard off-the-shelf Bluetooth headsets use fixed firmware pairing (typically Bluetooth "Just Works" or fixed 0000 PINs) and do not have on-device password prompts. If someone borrows, grabs, or connects to your headset, they can immediately hear audio or misuse it without restriction.

**HeadsetGuard solves this by operating as a low-latency CoreAudio and IOBluetooth security gatekeeper:**
1. **Instant Mute & Clamp**: The microsecond your protected Bluetooth headset connects or becomes the audio output, HeadsetGuard instantly sets the output volume to `0.0` and hardware-mutes the device at the CoreAudio driver level.
2. **Visual Unlock Dialog**: A sleek, dark glassmorphic security dialog pops up requesting your master PIN/password or Touch ID / Apple Watch biometrics.
3. **Strict Tamper Interception**: If someone presses physical volume/playback buttons on the headset while it is locked, HeadsetGuard's active guard loop intercepts the change and forces the volume back to zero.
4. **Anti-Theft Drop Safeguard**: If unauthorized password attempts exceed your configured limit (default: 3), HeadsetGuard drops the Bluetooth link via `IOBluetoothDevice.closeConnection()` and redirects audio back to your Mac's internal speakers.
5. **Session-Based Protection**: Once you enter your PIN or use Touch ID, your listening volume is smoothly restored and marked as authorized. When you disconnect or your Mac sleeps, the security lock re-arms automatically.

---

## ✨ Features

- **Menu Bar Status Extra**:
  - `🎧` Monitoring / Armed (No headset connected)
  - `🔒` Headset Connected & **LOCKED** (Audio muted)
  - `🔓` Headset Connected & **AUTHORIZED** (Audio active)
- **Authentication Methods**:
  - Custom Master PIN / Password (salted SHA-256 PBKDF2 with 310,000 iterations, stored in the macOS Keychain)
  - Touch ID / Apple Watch / macOS User authentication via `LocalAuthentication`
- **Preferences & Security Dashboard**:
  - **General**: Toggle auto-lock on connect and lock on sleep/screen-lock (changes require the master PIN).
  - **Password Management**: Set, update, or reset your master PIN.
  - **Protected Headsets List**: Choose "Protect All Bluetooth Audio Devices" or selectively choose specific paired headsets (e.g. your AirPods or Galaxy Buds).
  - **Activity & Audit Log**: Timestamped tracking of device connections, unlock attempts, volume tampering, and disconnections.
- **Built-in CLI Utility**: Scriptable from Terminal (`headsetguard --status`, `--list`, `--lock`, `--disconnect`, etc.).
- **Zero Third-Party Dependencies**: Pure native Swift 6 / SwiftPM / CoreAudio / IOBluetooth / AppKit binary compiling with standard Apple Command Line Tools.

---

## 🚀 Quick Start

### 1. Build and Run
Requires macOS 11+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/Akpahsamuel/HeadsetGuard.git
cd HeadsetGuard
```
```bash
# Build the native macOS app bundle
make build

# Launch HeadsetGuard directly into your macOS Menu Bar
make run
```

### 2. First-Time Setup
1. When you first launch HeadsetGuard, click on the **HeadsetGuard icon (`🎧`)** in your top menu bar.
2. Select **Preferences & Security Dashboard...** (or enter a PIN on the first unlock prompt).
3. Set your desired master PIN / password.

### 3. Install to Applications (Optional)
```bash
make install
```
This copies `HeadsetGuard.app` directly into `/Applications/HeadsetGuard.app`.

Builds are signed with the hardened runtime using an ad-hoc identity by default. For a stable Keychain identity, pass your own certificate: `make build SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"`.

To have HeadsetGuard restart automatically if it is killed (a normal **Quit** stays quit), run `make install-agent`; remove it with `make uninstall-agent`.

If you forget the master PIN, use **Forgot PIN?** on the password tab in Preferences. It asks for your Mac password or Touch ID before letting you set a new one.

---

## 🖥 Terminal CLI Usage

HeadsetGuard includes a built-in CLI interface:

```bash
# View active security status and audio device info
make status
# or: ./bin/headsetguard --status

# List all paired Bluetooth headsets and output devices
make list
# or: ./bin/headsetguard --list

# Manually lock the currently connected headset
./bin/headsetguard --lock

# Emergency disconnect and restore audio to Mac speakers
./bin/headsetguard --disconnect

# View recent security audit logs
make logs
# or: ./bin/headsetguard --logs

# Configure master PIN/password from terminal
./bin/headsetguard --set-password
```

---

## 📁 Project Architecture

```
Headset_Security/
├── Package.swift                     # SwiftPM package manifest (macOS 11+)
├── Makefile                          # Build system & packaging targets
├── LICENSE / CONTRIBUTING.md / SECURITY.md / CODE_OF_CONDUCT.md
├── .github/                          # CI workflow, issue & PR templates
├── resources/
│   ├── Info.plist                    # App bundle metadata (LSUIElement agent)
│   ├── AppIcon.icns                  # High-resolution macOS application icon
│   └── generate_icon.m               # Standalone vector icon generator tool
├── Sources/
│   ├── HeadsetGuard/                 # Main executable bootstrap
│   │   └── main.swift
│   └── HeadsetGuardKit/              # Core framework
│       ├── Audio/                    # AudioHAL protocol, CoreAudioHAL & AudioGuard
│       │   ├── AudioHAL.swift
│       │   └── AudioGuard.swift
│       ├── Bluetooth/                # IOBluetooth connection monitoring & drop logic
│       │   └── BluetoothManager.swift
│       ├── Security/                 # Salted PBKDF2 hashing, Keychain & audit log
│       │   ├── PasswordHasher.swift
│       │   ├── CredentialStore.swift
│       │   ├── SettingsStore.swift
│       │   ├── AuditLog.swift
│       │   └── SecurityManager.swift
│       ├── App/                      # Menu bar controller & lock coordinator
│       │   ├── AppDelegate.swift
│       │   └── LockCoordinator.swift
│       ├── UI/                       # Unlock dialog & preferences dashboard
│       │   ├── UnlockWindowController.swift
│       │   ├── UnlockAttemptPolicy.swift
│       │   └── PreferencesWindowController.swift
│       └── CLI/                      # Command parser & CLI runner
│           ├── Command.swift
│           └── CLIRunner.swift
└── Tests/
    └── HeadsetGuardKitTests/         # Swift Testing automated test suite
```

---

## ⚙️ Setting Up Auto-Start on macOS Login

To have HeadsetGuard launch automatically whenever you turn on or log into your Mac:
1. Open **System Settings** > **General** > **Login Items**.
2. Click the **`+`** button under "Open at Login".
3. Select `/Applications/HeadsetGuard.app` (or `build/HeadsetGuard.app`).
4. HeadsetGuard will now automatically guard your headsets whenever your Mac starts!

---

## 🤝 Contributing

Contributions of all kinds are welcome: bug reports, headset compatibility notes, docs, tests, and code. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first and follow the [Code of Conduct](CODE_OF_CONDUCT.md).

Ideas that would help most:
- Compatibility testing across headset brands and macOS versions
- An automated test target
- Localization
- Signed and notarized release builds

## 🔐 Security

Found a vulnerability? Please don't open a public issue. See [SECURITY.md](SECURITY.md) for private reporting.

HeadsetGuard is a software gatekeeper on your Mac. It cannot stop someone from using the headset with another device.

## 📄 License

Released under the [MIT License](LICENSE).
