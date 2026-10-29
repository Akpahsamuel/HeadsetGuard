import AppKit
import HeadsetGuardKit
import LegacyCore

let args = Array(CommandLine.arguments.dropFirst())
let command = Command.parse(args)

if command == .app {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
} else {
    let runner = CLIRunner()
    exit(runner.run(command))
}
